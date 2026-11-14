import Foundation

/// 搜索结果卡片上显示的那一段文字: 以最早出现的查询词为锚点截取一个窗口, 并给出窗口内
/// 每个查询词的位置供高亮 (照 tbmail 的 clip(text, position, width) 做法)。卡片原本固定
/// 显示开头 300 个字符, 命中在后面时卡片上看不到命中处。
///
/// 「出现」与搜索同一个定义: 归一化 (`SearchText.normalize`) 后的子串。做法是用共享的
/// `SearchFoldTable` 把原文一遍折叠成归一化文本, 在里面找查询词, 再映射回原文位置。表还没
/// 建好、或文本里有逐字符查表不可靠的字符 (组合符号等, 约 0.05% 的条目) 时, 退回旧做法:
/// Foundation 的大小写 + 全半角不敏感查找, 找不到再逐字符归一化前 `slowScanLimit` 个字符。
/// 只在前 `scanLimit` 个字符里定位, 更深处的命中返回 nil, 由调用方按原样显示开头。
public struct SearchSnippet: Equatable, Sendable {
    /// 窗口里的原文 (未加省略号)。
    public let text: String
    /// 查询词在 `text` 中的位置, 以 Character 计, 升序、互不重叠。
    public let highlights: [Range<Int>]
    /// 窗口前面还有内容 (显示时加 "…")。
    public let truncatedStart: Bool
    /// 窗口后面还有内容。
    public let truncatedEnd: Bool

    public static let scanLimit = 20_000
    static let slowScanLimit = 5_000
    static let maxHighlights = 64

    /// - Parameters:
    ///   - length: 窗口最多多少个字符 (卡片显示上限)。
    ///   - lead: 锚点前保留多少个字符; 这段里有换行时从换行后开始, 让窗口从整行起头。
    /// - Returns: 查询词都不在 `text` 的前 `scanLimit` 个字符里时为 nil。
    public static func make(text: String, query: String, length: Int = 300, lead: Int = 40) -> SearchSnippet? {
        make(text: text, query: query, length: length, lead: lead, table: SearchFoldTable.current)
    }

    /// `table` 为 nil 时只走旧做法 (测试用它分别覆盖两条路径)。
    static func make(text: String, query: String, length: Int, lead: Int, table: SearchFoldTable?) -> SearchSnippet? {
        let words = SearchText.words(query)
        guard !words.isEmpty, !text.isEmpty else { return nil }
        let scope = text.prefix(scanLimit)
        let folded = table?.fold(scope)

        let anchor: String.Index?
        if let folded {
            anchor = words.compactMap { folded.find(Array($0.utf8)) }.min()
                .map { characterStart(scope.utf8.index(scope.startIndex, offsetBy: folded.rawStart($0)), in: text) }
        } else {
            anchor = words.compactMap { firstRange(of: $0, in: scope)?.lowerBound }.min()
        }
        guard let anchor else { return nil }

        var start = scope.index(anchor, offsetBy: -lead, limitedBy: scope.startIndex) ?? scope.startIndex
        if let newline = scope[start..<anchor].lastIndex(where: \.isNewline) {
            start = scope.index(after: newline)
        }
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        let window = text[start..<end]

        // 窗口可能比 scope 多出一截, 所以单独折叠; 折叠不了时高亮也走旧做法。
        let ranges: [Range<String.Index>]
        if folded != nil, let foldedWindow = table?.fold(window) {
            ranges = highlights(of: words, in: window, folded: foldedWindow, text: text)
        } else {
            ranges = fallbackHighlights(of: words, in: window)
        }
        let offsets = merge(ranges.map {
            window.distance(from: window.startIndex, to: $0.lowerBound)
                ..< window.distance(from: window.startIndex, to: $0.upperBound)
        })
        return SearchSnippet(text: String(window), highlights: offsets,
                             truncatedStart: start > text.startIndex, truncatedEnd: end < text.endIndex)
    }

    private static func highlights(of words: [String], in window: Substring, folded: SearchFolded, text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for word in words {
            let needle = Array(word.utf8)
            var from = 0
            while ranges.count < maxHighlights, let hit = folded.find(needle, from: from) {
                let lower = characterStart(window.utf8.index(window.startIndex, offsetBy: folded.rawStart(hit)), in: text)
                let upper = characterEnd(window.utf8.index(window.startIndex, offsetBy: folded.rawEnd(lastByte: hit + needle.count - 1)), in: text)
                ranges.append(lower..<upper)
                from = folded.folded(forRaw: window.utf8.distance(from: window.startIndex, to: upper))
            }
        }
        return ranges
    }

    private static func fallbackHighlights(of words: [String], in window: Substring) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for word in words {
            var from = window.startIndex
            while ranges.count < maxHighlights, from < window.endIndex,
                  let hit = firstRange(of: word, in: window[from...]) {
                ranges.append(hit)
                from = hit.upperBound > hit.lowerBound ? hit.upperBound : window.index(after: hit.lowerBound)
            }
        }
        return ranges
    }

    /// 字节位置所在 Character 的起点 (命中可能落在 emoji 组合序列等多码点字符的中间)。
    private static func characterStart(_ index: String.Index, in text: String) -> String.Index {
        var i = index
        while i > text.startIndex, i.samePosition(in: text) == nil { i = text.unicodeScalars.index(before: i) }
        return i
    }

    /// 字节位置所在 Character 的结束处。
    private static func characterEnd(_ index: String.Index, in text: String) -> String.Index {
        var i = index
        while i < text.endIndex, i.samePosition(in: text) == nil { i = text.unicodeScalars.index(after: i) }
        return i
    }

    private static func firstRange(of word: String, in text: Substring) -> Range<String.Index>? {
        if let hit = text.range(of: word, options: [.caseInsensitive, .widthInsensitive]) { return hit }
        return normalizedRange(of: word, in: text.prefix(slowScanLimit))
    }

    /// 逐字符按 `SearchText.normalize` 映射后查找, 命中映射回原文的字符范围。
    private static func normalizedRange(of word: String, in text: Substring) -> Range<String.Index>? {
        let needle = Array(word.unicodeScalars)
        guard !needle.isEmpty else { return nil }
        var scalars: [Unicode.Scalar] = []
        var owners: [String.Index] = []
        var index = text.startIndex
        while index < text.endIndex {
            for scalar in SearchText.normalize(String(text[index])).unicodeScalars {
                scalars.append(scalar)
                owners.append(index)
            }
            index = text.index(after: index)
        }
        guard scalars.count >= needle.count else { return nil }
        for i in 0...(scalars.count - needle.count) where scalars[i] == needle[0] {
            if Array(scalars[i..<(i + needle.count)]) == needle {
                let last = owners[i + needle.count - 1]
                return owners[i]..<text.index(after: last)
            }
        }
        return nil
    }

    private static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, range.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }
}
