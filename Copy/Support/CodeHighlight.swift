import SwiftUI
import CopyCore

/// Token → color mapping for on-device syntax highlighting. This is CONTENT coloring
/// on the code glyphs themselves (like Xcode's editor), not chrome — it's intentionally
/// separate from any card/border styling. Colors are SwiftUI's named system colors,
/// which are dynamic (each has a light- and dark-appearance variant baked in), so they
/// read correctly in both without any extra branching here.
enum CodeHighlightPalette {
    static func color(for kind: TokenKind) -> Color {
        switch kind {
        case .keyword: return .purple
        case .string: return .red
        case .comment: return .secondary
        case .number: return .teal
        case .type: return .blue
        case .plain: return .primary
        }
    }
}

/// Builds a single concatenated `Text` from `text` with each `token`'s substring
/// colored per `CodeHighlightPalette`; everything outside a token range is left at the
/// default (primary) color. Font is intentionally left to the caller's `.font(...)`
/// modifier on the returned `Text` — every run here is otherwise plain, so one outer
/// `.font()` cascades to the whole concatenation, matching how the plain-text path
/// already applies `Tokens.bodyMono`/mono system font today.
func highlightedText(_ text: String, tokens: [HighlightToken]) -> Text {
    guard !tokens.isEmpty else { return Text(text) }
    let ns = text as NSString
    let length = ns.length
    var result = Text(verbatim: "")
    var cursor = 0
    for token in tokens.sorted(by: { $0.range.location < $1.range.location }) {
        // Defensive: `SyntaxHighlighter` guarantees sorted, non-overlapping,
        // in-bounds ranges, but this is a display path — a malformed token should
        // never crash the shelf, just be skipped.
        guard token.range.location >= cursor, token.range.location + token.range.length <= length else { continue }
        if token.range.location > cursor {
            result = result + Text(ns.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
        }
        result = result + Text(ns.substring(with: token.range))
            .foregroundColor(CodeHighlightPalette.color(for: token.kind))
        cursor = token.range.location + token.range.length
    }
    if cursor < length {
        result = result + Text(ns.substring(with: NSRange(location: cursor, length: length - cursor)))
    }
    return result
}

/// Caches `CodeDetector`/`SyntaxHighlighter` results so scrolling the shelf or
/// reopening the preview doesn't re-tokenize on every render. Entries are keyed by
/// `"<item uuid>#<cap>"` — the cap is part of the key because the card (short cap) and
/// the preview pane (longer cap) ask about the same item at different lengths, and
/// keying by uuid alone would have them evict each other on every switch. An entry is
/// recomputed whenever the capped text it was built from no longer matches (covers
/// `EditItemSheet` rewriting an item's `plainText` after the cache already has it).
@MainActor
final class CodeHighlightCache {
    static let shared = CodeHighlightCache()

    private struct Entry {
        let textHash: Int
        let language: CodeLanguage?
        let tokens: [HighlightToken]
    }

    private var entries: [String: Entry] = [:]
    /// Bounds memory for very long shelf histories. Eviction is a blunt "clear
    /// everything" rather than real LRU bookkeeping — simple, and at this scale
    /// (a few hundred small entries) the occasional full recompute is unnoticeable.
    private let capacity = 500

    func result(for text: String, uuid: String, cap: Int) -> (language: CodeLanguage?, tokens: [HighlightToken]) {
        let capped = String(text.prefix(cap))
        let hash = capped.hashValue
        let key = "\(uuid)#\(cap)"
        if let entry = entries[key], entry.textHash == hash {
            return (entry.language, entry.tokens)
        }
        let language = CodeDetector.detect(capped)
        let tokens = language.map { SyntaxHighlighter.tokens(for: capped, language: $0) } ?? []
        if entries.count >= capacity { entries.removeAll() }
        entries[key] = Entry(textHash: hash, language: language, tokens: tokens)
        return (language, tokens)
    }
}

/// 搜索时卡片显示的命中窗口 (`SearchSnippet`), 按 条目 + 内容 + 查询 缓存: SwiftUI 会反复
/// 求值卡片 body, 而长条目的定位要扫描上万字符。内容变了 (编辑) 由 contentHash 区分。
@MainActor
final class SearchSnippetCache {
    static let shared = SearchSnippetCache()

    private struct Key: Hashable {
        let uuid: String
        let contentHash: String
        let query: String
    }

    private var entries: [Key: SearchSnippet?] = [:]
    /// 与 `CodeHighlightCache` 相同的粗放上限: 满了整体清空。
    private let capacity = 500

    func snippet(for item: ClipItem, query: String) -> SearchSnippet? {
        let key = Key(uuid: item.uuid, contentHash: item.contentHash, query: query)
        if let cached = entries[key] { return cached }
        let made = SearchSnippet.make(text: item.plainText ?? "", query: query)
        // 折叠表还没建好时算出的是旧做法的结果, 不缓存, 表建好后重算。
        guard SearchFoldTable.current != nil else { return made }
        if entries.count >= capacity { entries.removeAll() }
        entries[key] = made
        return made
    }
}

/// 搜索命中处的样式: 半透明黄底 + 加粗, 文字颜色不动, 代码条目的语法着色仍然可见。
/// 卡片、OCR 摘要共用。
enum SearchHighlightStyle {
    static let background = Color.yellow.opacity(0.45)

    static func apply(to run: inout AttributedSubstring) {
        run.swiftUI.backgroundColor = background
        run.inlinePresentationIntent = .stronglyEmphasized
    }
}

/// 搜索命中窗口的语法着色 token。窗口文字随查询变化, 按 条目 + 窗口文字 缓存,
/// 免得 SwiftUI 每次求值卡片 body 都重跑一遍正则。
@MainActor
final class SnippetTokenCache {
    static let shared = SnippetTokenCache()

    private struct Key: Hashable {
        let uuid: String
        let text: String
    }

    private var entries: [Key: [HighlightToken]] = [:]
    private let capacity = 500

    func tokens(for text: String, uuid: String, language: CodeLanguage) -> [HighlightToken] {
        let key = Key(uuid: uuid, text: text)
        if let cached = entries[key] { return cached }
        let made = SyntaxHighlighter.tokens(for: text, language: language)
        if entries.count >= capacity { entries.removeAll() }
        entries[key] = made
        return made
    }
}

/// 命中窗口渲染成 Text: 查询词叠 `SearchHighlightStyle`, 有 `tokens` (窗口文字上的语法
/// 着色, UTF-16 区间) 时同时着色; 被截断的一端加 "…"。
func searchSnippetText(_ snippet: SearchSnippet, tokens: [HighlightToken] = []) -> Text {
    var body = AttributedString(snippet.text)
    let text = snippet.text
    let utf16 = text.utf16
    for token in tokens where token.kind != .plain {
        guard token.range.location >= 0, token.range.location + token.range.length <= utf16.count,
              let lo16 = utf16.index(utf16.startIndex, offsetBy: token.range.location, limitedBy: utf16.endIndex),
              let hi16 = utf16.index(lo16, offsetBy: token.range.length, limitedBy: utf16.endIndex),
              let lo = String.Index(lo16, within: text), let hi = String.Index(hi16, within: text),
              let alo = AttributedString.Index(lo, within: body), let ahi = AttributedString.Index(hi, within: body)
        else { continue }
        body[alo..<ahi].swiftUI.foregroundColor = CodeHighlightPalette.color(for: token.kind)
    }
    // highlights 以 Character 计。
    let chars = Array(text.indices) + [text.endIndex]
    for range in snippet.highlights where range.lowerBound >= 0 && range.upperBound < chars.count {
        guard let lo = AttributedString.Index(chars[range.lowerBound], within: body),
              let hi = AttributedString.Index(chars[range.upperBound], within: body) else { continue }
        SearchHighlightStyle.apply(to: &body[lo..<hi])
    }
    var result = AttributedString(snippet.truncatedStart ? "…" : "")
    result.append(body)
    if snippet.truncatedEnd { result.append(AttributedString("…")) }
    return Text(result)
}
