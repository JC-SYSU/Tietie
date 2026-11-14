import Foundation

/// 搜索的归一化契约 (照 tbmail textnorm.normalize): 写入端 (`item_search` 表, 由
/// SQLite 触发器调 `sqlFunctionName` 维护) 和查询端 (`words`) 必须走同一个 `normalize`,
/// 否则 LIKE 会悄悄漏结果。改动这里的任何规则都要把 `rulesVersion` 加一, 启动时
/// `DatabaseManager.refreshSearchTextIfNeeded()` 会据此重算全部行。
///
/// 规则: 纯 ASCII 只转小写; 否则 NFKC (全角→半角、连字拆开、①→1 等) → 破折号
/// (Unicode Pd 类 + U+2212 减号) 统一成 "-" → 大小写折叠 (ß→ss)。不做模糊匹配、
/// 不去重音: 查询词必须在某个字段里连续出现。
public enum SearchText {
    /// 规则版本。只在改了 `normalize` 的行为时加一。
    public static let rulesVersion = 1

    /// 存在 `search_meta` 里的版本戳。带上系统版本和 build 号, 因为 NFKC 和大小写折叠
    /// 用的是系统自带的 Unicode 数据, 升级 macOS 可能改变结果。不用
    /// `operatingSystemVersionString`: 它随界面语言变化, 换个语言就会白白触发全库重算。
    public static var stamp: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "rules=\(rulesVersion);os=\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)(\(osBuild))"
    }

    private static var osBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "?" }
        return String(cString: buffer)
    }

    /// 触发器调用的 SQLite 函数名, 由 `DatabaseManager` 在每条连接上注册。
    public static let sqlFunctionName = "copy_search_text"

    /// 参与搜索的字段, 顺序即 `searchText` 里的拼接顺序 (也是 SQL 函数的参数顺序)。
    public static let fields = ["plainText", "title", "linkTitle", "appName", "recognizedText"]

    public static func normalize(_ text: String) -> String {
        if text.utf8.allSatisfy({ $0 < 0x80 }) { return text.lowercased() }
        let nfkc = text.precomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in nfkc.unicodeScalars {
            let isDash = scalar.properties.generalCategory == .dashPunctuation || scalar.value == 0x2212
            scalars.append(isDash ? "-" : scalar)
        }
        // folding(.caseInsensitive) 是完整的大小写折叠 (ß/ẞ→ss、ᾈ→ἀι), lowercased() 不是。
        return String(scalars).folding(options: [.caseInsensitive], locale: nil)
    }

    /// 各字段分别归一化后用换行拼接, 换行让多词查询可以分别落在不同字段 ("safari
    /// invoice" 能命中从 Safari 复制的、正文含 invoice 的条目), 而单个词不会跨字段。
    public static func joined(_ values: [String?]) -> String {
        values.compactMap { $0 }.filter { !$0.isEmpty }.map(normalize).joined(separator: "\n")
    }

    /// 查询拆词: 先按空白拆, 再逐词归一化 (与 tbmail 相同的顺序)。词间 AND、顺序无关。
    public static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }.filter { !$0.isEmpty }
    }

    /// 一个词的 LIKE 模式, 转义 %、_、\ (配合 ESCAPE '\')。`searchText` 已归一化,
    /// 所以这个 LIKE 就是精确的子串匹配, 不需要再在 Swift 里复核。
    static func likePattern(_ word: String) -> String {
        "%" + word
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }
}
