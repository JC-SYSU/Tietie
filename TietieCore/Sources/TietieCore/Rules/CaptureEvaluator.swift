import Foundation
import ImageIO

/// 交给规则判断的一条内容。捕获时由 `CapturedItem` 构造; 用规则清理历史时由库里的
/// 条目构造 (见 `ItemStore.ruleCandidates()`)。
public struct RuleSubject: Sendable {
    public enum ImageSource: Sendable { case data(Data), file(URL) }

    public var kind: ItemKind
    /// 用来匹配关键词和预设的文本。图片为 nil (图片不做关键词和预设判断)。
    public var text: String?
    public var sourceBundleID: String?
    /// 来自通用剪贴板 (剪贴板里带 `com.apple.is-remote-clipboard` 标记)。
    public var isRemote: Bool
    public var image: ImageSource?
    public var imageBytes: Int

    public init(kind: ItemKind, text: String?, sourceBundleID: String?, isRemote: Bool = false,
                image: ImageSource? = nil, imageBytes: Int = 0) {
        self.kind = kind
        self.text = text
        self.sourceBundleID = sourceBundleID
        self.isRemote = isRemote
        self.image = image
        self.imageBytes = imageBytes
    }

    public init(captured: CapturedItem, isRemote: Bool) {
        self.init(kind: captured.kind, text: captured.kind == .image ? nil : captured.plainText,
                  sourceBundleID: captured.sourceBundleID, isRemote: isRemote)
        if captured.kind == .image {
            // 入库时只留一份 PNG (见 ImageFileStore.primaryImage), 大小按 PNG 算; 只有 TIFF 时按 TIFF。
            let reps = captured.representations
            let rep = reps.first { $0.uti == "public.png" } ?? reps.first { $0.uti == "public.tiff" } ?? reps.first
            image = rep.map { .data($0.data) }
            imageBytes = rep?.data.count ?? 0
        }
    }

    /// 图片长边像素。只读文件头, 不解码整张图。
    func imageLongSide() -> Int? {
        let source: CGImageSource?
        switch image {
        case .data(let data): source = CGImageSourceCreateWithData(data as CFData, nil)
        case .file(let url): source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case nil: return nil
        }
        guard let source,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return max(w, h)
    }
}

/// 规则的标识。`key` 用作命中计数的存储键, 规则改名 (改关键词内容) 时计数跟着 id 走。
public enum RuleRef: Hashable, Sendable {
    case whitelistKind
    case whitelistApp
    case whitelistKeyword
    case blacklistKind(ItemKind)
    case blacklistApp(String)
    case universalClipboard
    case minTextLength, maxTextSize, minImagePixels, maxImageSize
    case preset(SensitivePreset)
    case blacklistKeyword(UUID)

    public var key: String {
        switch self {
        case .whitelistKind: return "wl.kind"
        case .whitelistApp: return "wl.app"
        case .whitelistKeyword: return "wl.keyword"
        case .blacklistKind(let k): return "bl.kind.\(k.rawValue)"
        case .blacklistApp(let id): return "bl.app.\(id)"
        case .universalClipboard: return "bl.remote"
        case .minTextLength: return "bl.limit.minText"
        case .maxTextSize: return "bl.limit.maxText"
        case .minImagePixels: return "bl.limit.minImage"
        case .maxImageSize: return "bl.limit.maxImage"
        case .preset(let p): return "bl.preset.\(p.rawValue)"
        case .blacklistKeyword(let id): return "bl.keyword.\(id.uuidString)"
        }
    }

    /// 白名单里的三项是「没命中」才生效, 其余是「命中」生效。
    public var isWhitelistMiss: Bool {
        switch self {
        case .whitelistKind, .whitelistApp, .whitelistKeyword: return true
        default: return false
        }
    }
}

public struct RuleHit: Equatable, Sendable {
    public let rule: RuleRef
    public let action: RuleAction
}

public struct CaptureVerdict: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case keep
        case expire(minutes: Int)
        case drop
    }

    public var outcome: Outcome = .keep
    /// 决定结果的那条规则 (命中计数只记它)。保留时为 nil。
    public var decidedBy: RuleRef?
    /// 命中的全部规则, 按判定顺序。捕获时一旦能定「不保存」就停, 这里只有前几条;
    /// 设置页的规则测试会跑完全部规则。
    public var hits: [RuleHit] = []
    /// 超过时间预算没跑完、按「未命中」处理的正则 (关键词规则 id)。
    public var timedOutKeywords: [UUID] = []
    /// 超过时间预算没跑完的预设。
    public var timedOutPresets: [SensitivePreset] = []

    public static let keep = CaptureVerdict()
}

/// 编译好的一套规则, 负责判定。规则变了就重建一个 (正则只在这里编译一次)。
///
/// 判定顺序: 白名单 (类型 → 来源 app → 关键词, 任一项不满足即不保存, 不再看黑名单)
/// → 黑名单 (类型 → 来源 app → 通用剪贴板 → 长度大小 → 敏感内容预设 → 关键词)。
/// 便宜的先判; 捕获时一旦能定「不保存」就停。多条黑名单命中时取最严的动作。
public struct CaptureEvaluator: @unchecked Sendable { // 只含不可变的已编译正则
    public let rules: CaptureRules
    /// 文本只看前这么多个 UTF-16 单元 (约 64K 字), 再长的文本后半段不判断。
    public static let scanLimit = 65_536
    /// 一次捕获里所有正则加起来的时间预算。超时的正则按「未命中」处理并在设置页提示。
    public static let captureBudget: TimeInterval = 0.05

    struct CompiledKeyword {
        let rule: KeywordRule
        let normalized: String?
        let regex: BudgetedRegex?
    }

    private let whitelistKeywords: [CompiledKeyword]
    private let blacklistKeywords: [CompiledKeyword]
    private let whitelistApps: Set<String>
    private let blacklistApps: Set<String>

    private static let secretRegexes = SensitiveDetector.secretPatterns.compactMap(compile)
    private static let cardRegex = compile(SensitiveDetector.cardPattern)!
    private static let idRegex = compile(SensitiveDetector.idPattern)!
    private static let codeKeywordRegex = compile(SensitiveDetector.codeKeywordPattern)!
    private static let codeDigitsRegex = compile(SensitiveDetector.codeDigitsPattern)!

    public init(rules: CaptureRules) {
        self.rules = rules
        whitelistKeywords = Self.compileKeywords(rules.whitelist.keywords)
        blacklistKeywords = Self.compileKeywords(rules.blacklist.keywords)
        whitelistApps = Set(rules.whitelist.apps)
        blacklistApps = Set(rules.blacklist.apps)
    }

    static func compile(_ pattern: String) -> BudgetedRegex? {
        (try? NSRegularExpression(pattern: pattern)).map(BudgetedRegex.init)
    }

    /// 空关键词和写错的正则不参与判断 (设置页会标出写错的正则)。
    static func compileKeywords(_ rules: [KeywordRule]) -> [CompiledKeyword] {
        rules.compactMap { rule in
            if rule.isRegex {
                guard !rule.pattern.isEmpty, let rx = compile(rule.pattern) else { return nil }
                return CompiledKeyword(rule: rule, normalized: nil, regex: rx)
            }
            let n = SearchText.normalize(rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines))
            return n.isEmpty ? nil : CompiledKeyword(rule: rule, normalized: n, regex: nil)
        }
    }

    /// 正则写错时返回系统给的错误说明, 写对或为空时返回 nil。
    public static func regexError(_ pattern: String) -> String? {
        guard !pattern.isEmpty else { return nil }
        do { _ = try NSRegularExpression(pattern: pattern); return nil } catch { return error.localizedDescription }
    }

    public enum Preflight: Equatable, Sendable {
        case proceed
        case decided(CaptureVerdict)
    }

    /// 读剪贴板内容之前就能定的部分: 来源 app 和通用剪贴板。这里定了「不保存」, 剪贴板
    /// 内容一个字节都不读 (与原来「排除的 app」行为一致)。
    public func preflight(sourceBundleID: String?, isRemote: Bool) -> Preflight {
        if rules.whitelist.enabled, !whitelistApps.isEmpty,
           !(sourceBundleID.map(whitelistApps.contains) ?? false) {
            return .decided(Self.dropped(.whitelistApp))
        }
        if rules.blacklist.enabled {
            if let id = sourceBundleID, blacklistApps.contains(id) { return .decided(Self.dropped(.blacklistApp(id))) }
            if rules.blacklist.skipUniversalClipboard, isRemote { return .decided(Self.dropped(.universalClipboard)) }
        }
        return .proceed
    }

    static func dropped(_ rule: RuleRef) -> CaptureVerdict {
        CaptureVerdict(outcome: .drop, decidedBy: rule, hits: [RuleHit(rule: rule, action: .drop)])
    }
}

extension CaptureEvaluator {
    /// - Parameter exhaustive: true = 跑完全部规则, 列出所有命中 (设置页的规则测试);
    ///   false = 能定「不保存」就停 (捕获时)。
    public func evaluate(_ subject: RuleSubject, exhaustive: Bool = false,
                         budget: TimeInterval = CaptureEvaluator.captureBudget) -> CaptureVerdict {
        let deadline = Date().addingTimeInterval(budget)
        var verdict = CaptureVerdict()
        var scan = subject.text.map(ScanText.init)

        // 白名单: 先纳入。不满足就不保存, 黑名单不用再看。
        if rules.whitelist.enabled {
            var miss: RuleRef?
            if !rules.whitelist.kinds.contains(subject.kind) {
                miss = .whitelistKind
            } else if !whitelistApps.isEmpty, !(subject.sourceBundleID.map(whitelistApps.contains) ?? false) {
                miss = .whitelistApp
            } else if !whitelistKeywords.isEmpty, subject.kind != .image, scan != nil {
                // 图片没有文本, 不做关键词判断。
                var matched = false
                for kw in whitelistKeywords {
                    switch Self.match(kw, in: &scan!, deadline: deadline) {
                    case .matched: matched = true
                    case .timedOut: verdict.timedOutKeywords.append(kw.rule.id)
                    case .notMatched: break
                    }
                    if matched { break }
                }
                if !matched { miss = .whitelistKeyword }
            }
            if let miss {
                verdict.outcome = .drop
                verdict.decidedBy = miss
                verdict.hits.append(RuleHit(rule: miss, action: .drop))
                return verdict
            }
        }

        guard rules.blacklist.enabled else { return verdict }
        let bl = rules.blacklist
        var c = Collector(verdict: verdict, exhaustive: exhaustive)

        if bl.kinds.contains(subject.kind), c.hit(.blacklistKind(subject.kind), .drop) { return c.finish() }
        if let id = subject.sourceBundleID, blacklistApps.contains(id), c.hit(.blacklistApp(id), .drop) { return c.finish() }
        if bl.skipUniversalClipboard, subject.isRemote, c.hit(.universalClipboard, .drop) { return c.finish() }

        let limits = bl.limits
        if let text = subject.text {
            if limits.minTextLengthEnabled, Self.isShorter(text, than: limits.minTextLength),
               c.hit(.minTextLength, .drop) { return c.finish() }
            if limits.maxTextKBEnabled, text.utf8.count > limits.maxTextKB * 1024,
               c.hit(.maxTextSize, .drop) { return c.finish() }
        }
        if subject.kind == .image {
            if limits.maxImageMBEnabled, subject.imageBytes > limits.maxImageMB * 1_048_576,
               c.hit(.maxImageSize, .drop) { return c.finish() }
            if limits.minImagePixelsEnabled, let side = subject.imageLongSide(), side < limits.minImagePixels,
               c.hit(.minImagePixels, .drop) { return c.finish() }
        }

        guard scan != nil else { return c.finish() }
        for setting in bl.presets where setting.enabled {
            switch Self.detect(setting.preset, in: &scan!, source: subject.sourceBundleID, deadline: deadline) {
            case .matched: if c.hit(.preset(setting.preset), setting.action) { return c.finish() }
            case .timedOut: c.verdict.timedOutPresets.append(setting.preset)
            case .notMatched: break
            }
        }
        for kw in blacklistKeywords {
            switch Self.match(kw, in: &scan!, deadline: deadline) {
            case .matched: if c.hit(.blacklistKeyword(kw.rule.id), kw.rule.action) { return c.finish() }
            case .timedOut: c.verdict.timedOutKeywords.append(kw.rule.id)
            case .notMatched: break
            }
        }
        return c.finish()
    }

    /// 汇总黑名单命中: 动作取最严, 记下决定结果的那条规则。
    struct Collector {
        var verdict: CaptureVerdict
        let exhaustive: Bool
        var action: RuleAction?

        /// 返回 true 表示可以停了 (已定「不保存」且不是在跑完整测试)。
        mutating func hit(_ rule: RuleRef, _ newAction: RuleAction) -> Bool {
            verdict.hits.append(RuleHit(rule: rule, action: newAction))
            let merged = action.map { $0.stricter(newAction) } ?? newAction
            if merged != action { action = merged; verdict.decidedBy = rule }
            return merged == .drop && !exhaustive
        }

        func finish() -> CaptureVerdict {
            var v = verdict
            switch action {
            case .drop?: v.outcome = .drop
            case .expire(let m)?: v.outcome = .expire(minutes: m)
            case nil: v.outcome = .keep
            }
            return v
        }
    }

    /// 去掉首尾空白后是否少于 n 个字符。只数到第 n 个字符, 长文本不会整段遍历或复制。
    static func isShorter(_ text: String, than n: Int) -> Bool {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }),
              let last = text.lastIndex(where: { !$0.isWhitespace }) else { return 0 < n }
        return text[first...last].prefix(n).count < n
    }
}

/// 参与判断的文本: 只取前 `CaptureEvaluator.scanLimit` 个 UTF-16 单元 (切在完整字符边界上),
/// 归一化版本第一次用到时才算。
struct ScanText {
    let raw: NSString
    private var normalizedCache: NSString?

    init(_ text: String) {
        let ns = text as NSString
        if ns.length > CaptureEvaluator.scanLimit {
            let cut = ns.rangeOfComposedCharacterSequence(at: CaptureEvaluator.scanLimit).location
            raw = ns.substring(to: cut) as NSString
        } else {
            raw = ns
        }
    }

    mutating func normalized() -> NSString {
        if let normalizedCache { return normalizedCache }
        let n = SearchText.normalize(raw as String) as NSString
        normalizedCache = n
        return n
    }
}

extension CaptureEvaluator {
    static func match(_ kw: CompiledKeyword, in scan: inout ScanText, deadline: Date) -> BudgetedRegex.Result {
        if let needle = kw.normalized {
            // 按 UTF-16 逐单元比较, 与搜索的字节语义一致 (搜「1」能命中「1️⃣」)。
            return scan.normalized().range(of: needle, options: .literal).location != NSNotFound ? .matched : .notMatched
        }
        guard let rx = kw.regex else { return .notMatched }
        return rx.firstMatch(in: scan.raw, deadline: deadline).0
    }

    static func detect(_ preset: SensitivePreset, in scan: inout ScanText, source: String?,
                       deadline: Date) -> BudgetedRegex.Result {
        let text = scan.raw
        switch preset {
        case .secrets:
            var timedOut = false
            for rx in secretRegexes {
                switch rx.firstMatch(in: text, deadline: deadline).0 {
                case .matched: return .matched
                case .timedOut: timedOut = true
                case .notMatched: break
                }
            }
            return timedOut ? .timedOut : .notMatched
        case .bankCard:
            return cardRegex.firstMatch(in: text, deadline: deadline, where: SensitiveDetector.isValidCard)
        case .chineseID:
            return idRegex.firstMatch(in: text, deadline: deadline, where: SensitiveDetector.isValidChineseID)
        case .verificationCode:
            guard text.length <= SensitiveDetector.codeTextLimit else { return .notMatched }
            let trimmed = (text as String).trimmingCharacters(in: .whitespacesAndNewlines)
            if source == SensitiveDetector.messagesBundleID,
               (4...8).contains(trimmed.count), trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return .matched
            }
            guard codeKeywordRegex.firstMatch(in: text, deadline: deadline).0 == .matched else { return .notMatched }
            return codeDigitsRegex.firstMatch(in: text, deadline: deadline).0
        }
    }
}
