import Foundation

/// 搜索结果卡片上显示的那一段文字: 以最早出现的查询词为锚点截取一个窗口, 并给出窗口内
/// 每个查询词的位置供高亮 (照 tbmail 的 clip(text, position, width) 做法)。卡片原本固定
/// 显示开头 300 个字符, 命中在后面时卡片上看不到命中处。
///
/// 定位在原文上做 (归一化后的文本和原文字符位置不一一对应), 分三级, 前一级找不到才走下一级:
/// 1. 字节查找: 查询词只由 ASCII 字母数字和汉字组成时, 在原文 UTF-8 字节里直接找 (ASCII
///    字母按大小写折叠比较)。长文里比 Foundation 快一个数量级 (实测每次按键 25 张卡
///    P90 7.6→1.9ms)。
/// 2. Foundation 的大小写 + 全半角不敏感查找, 覆盖 ß/ss、全角、连字、半角片假名。
/// 3. 逐字符按 `SearchText.normalize` 映射查找, 覆盖破折号变体、①。
/// 第 1 级适用的词, 后两级只查前 `variantScanLimit` 个字符: 这类词在长文后半段只以变体
/// 形式出现 (如只有 "Straße" 没有 "strasse") 时返回 nil, 卡片显示开头; 文中既有原形又有
/// 变体时, 锚点落在原形上。其他词 (含标点、假名等) 第 2 级查前 `scanLimit` 个字符。
/// 超长条目更深处的命中返回 nil, 由调用方按原样显示开头。
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
    static let variantScanLimit = 5_000
    static let slowScanLimit = 5_000
    static let maxHighlights = 64

    /// - Parameters:
    ///   - length: 窗口最多多少个字符 (卡片显示上限)。
    ///   - lead: 锚点前保留多少个字符; 这段里有换行时从换行后开始, 让窗口从整行起头。
    /// - Returns: 查询词都不在 `text` 的前 `scanLimit` 个字符里时为 nil。
    public static func make(text: String, query: String, length: Int = 300, lead: Int = 40) -> SearchSnippet? {
        // 与 SearchText.words 同样的拆词, 但保留原词: 走不走字节查找要看用户输入的原词。
        let pairs = query.split(whereSeparator: \.isWhitespace).compactMap { raw -> (raw: Substring, word: String)? in
            let word = SearchText.normalize(String(raw))
            return word.isEmpty ? nil : (raw, word)
        }
        let words = pairs.map(\.word)
        guard !words.isEmpty, !text.isEmpty else { return nil }
        let scope = text.prefix(scanLimit)
        guard let anchor = pairs.compactMap({ anchorIndex(raw: $0.raw, word: $0.word, in: scope) }).min() else { return nil }

        var start = scope.index(anchor, offsetBy: -lead, limitedBy: scope.startIndex) ?? scope.startIndex
        if let newline = scope[start..<anchor].lastIndex(where: \.isNewline) {
            start = scope.index(after: newline)
        }
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        let window = text[start..<end]

        var ranges: [Range<String.Index>] = []
        for word in words {
            var from = window.startIndex
            while ranges.count < maxHighlights, from < window.endIndex,
                  let hit = firstRange(of: word, in: window[from...]) {
                ranges.append(hit)
                from = hit.upperBound > hit.lowerBound ? hit.upperBound : window.index(after: hit.lowerBound)
            }
        }
        let offsets = merge(ranges.map {
            window.distance(from: window.startIndex, to: $0.lowerBound)
                ..< window.distance(from: window.startIndex, to: $0.upperBound)
        })
        return SearchSnippet(text: String(window), highlights: offsets,
                             truncatedStart: start > text.startIndex, truncatedEnd: end < text.endIndex)
    }

    /// 查询词在 `scope` 里第一次出现的位置 (见类型注释里的三级查找)。
    private static func anchorIndex(raw: Substring, word: String, in scope: Substring) -> String.Index? {
        guard isByteSearchable(raw: raw, word: word) else { return firstRange(of: word, in: scope)?.lowerBound }
        if let hit = byteSearch(Array(word.utf8), in: scope) { return hit }
        let head = scope.prefix(variantScanLimit)
        // 原文里没有任何能归一化出字母数字或汉字的字符时, 后两级不可能找到, 省掉这两次扫描
        // (正文里没有、命中在标题或来源 app 的卡片最常见)。
        if head.unicodeScalars.allSatisfy(isVariantFree) { return nil }
        return firstRange(of: word, in: head)?.lowerBound
    }

    /// 这个字符经 `SearchText.normalize` 不会变出原本没有的 ASCII 字母数字或汉字, 所以不会
    /// 成为字节查找漏掉的变体。范围由测试逐个字符校验 (SearchSnippetTests)。不在这些范围里
    /// 的字符 (全角字母数字、带圈数字、ß、上下标、康熙部首、兼容汉字等) 一律视为可能是变体。
    static func isVariantFree(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x7F,                       // ASCII
             0x300...0x36F,                     // 组合符号
             0x370...0x4FF,                     // 希腊、西里尔
             0x2000...0x206F,                   // 通用标点
             0x2190...0x22FF,                   // 箭头、数学运算符
             0x2600...0x27BF,                   // 杂项符号、装饰符号
             0x3000...0x3037, 0x303B...0x303F,  // CJK 符号标点 (除 〸〹〺)
             0x3040...0x30FF,                   // 平假名、片假名
             0x3400...0x4DBF, 0x4E00...0x9FFF,  // 汉字
             0xFE00...0xFE0F,                   // 变体选择符
             0xFF01...0xFF0F, 0xFF1A...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65,  // 全角标点、半角 CJK 标点
             0x1F300...0x1FAFF,                 // emoji
             0x20000...0x2A6DF, 0x2A700...0x2EBEF, 0x30000...0x3134F:  // 汉字扩展区
            return true
        default:
            return false
        }
    }

    /// 原词只含 ASCII 字母数字和汉字, 且归一化只做了 ASCII 小写。全角字母、标点、假名、
    /// 兼容汉字都排除: 它们在原文里常以另一种宽度出现, 字节查找会错过更早的那一处。
    static func isByteSearchable(raw: Substring, word: String) -> Bool {
        let isHanOrAlnum = raw.unicodeScalars.allSatisfy { s in
            switch s.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2A6DF, 0x2A700...0x2EBEF, 0x30000...0x3134F: return true
            default: return false
            }
        }
        return isHanOrAlnum && String(raw).lowercased() == word
    }

    /// `needle` (已小写) 在 `scope` 的 UTF-8 字节里第一次出现的位置, ASCII 字母按大小写折叠
    /// 比较。多字节 UTF-8 的每个字节都 ≥ 0x80, 折叠不会碰到它们, 命中也只会落在字符的
    /// 首字节上。
    static func byteSearch(_ needle: [UInt8], in scope: Substring) -> String.Index? {
        guard !needle.isEmpty else { return nil }
        let folds = needle.contains { $0 >= 0x61 && $0 <= 0x7A }
        func find(_ hay: UnsafeBufferPointer<UInt8>) -> Int? {
            guard needle.count <= hay.count, let base = hay.baseAddress else { return nil }
            if !folds {
                return needle.withUnsafeBufferPointer { n in
                    memmem(base, hay.count, n.baseAddress!, n.count).map { UnsafeRawPointer($0) - UnsafeRawPointer(base) }
                }
            }
            let first = needle[0]
            var i = 0
            let last = hay.count - needle.count
            while i <= last {
                let c = hay[i]
                if (c >= 0x41 && c <= 0x5A ? c | 0x20 : c) == first {
                    var j = 1
                    while j < needle.count {
                        let h = hay[i + j]
                        if (h >= 0x41 && h <= 0x5A ? h | 0x20 : h) != needle[j] { break }
                        j += 1
                    }
                    if j == needle.count { return i }
                }
                i += 1
            }
            return nil
        }
        let offset = scope.utf8.withContiguousStorageIfAvailable(find) ?? Array(scope.utf8).withUnsafeBufferPointer(find)
        return offset.map { scope.utf8.index(scope.startIndex, offsetBy: $0) }
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
