import Foundation

/// 用户的捕获规则: 一张白名单定「收哪些」, 一张黑名单定「哪些不收或限时保留」。
///
/// 判定顺序 (用户定的「白名单优先」): 白名单开启时先只纳入命中的内容, 没命中的直接
/// 丢弃; 纳入的再过黑名单。白名单关闭 = 全部纳入。两张表各有总开关, 关掉时规则
/// 保留但不生效。判定实现在 `CaptureEvaluator`。
///
/// 存在 UserDefaults 里 (JSON)。解码对缺字段宽容: 以后加字段时旧数据照常读出, 新字段
/// 取默认值, 不会因为一个字段解不出来就把整套规则丢掉。
public struct CaptureRules: Codable, Equatable, Sendable {
    public var whitelist = Whitelist()
    public var blacklist = Blacklist()

    public init() {}

    /// 全新安装的规则: 白名单关; 黑名单开, 只启用误报很少的两项预设 (密钥与令牌直接
    /// 不存、验证码 5 分钟后删除)。银行卡号、身份证号默认关: 19 位订单号这类数字串
    /// 可能恰好通过 Luhn 校验, 由用户自己决定。
    public static var factoryDefault: CaptureRules {
        var rules = CaptureRules()
        rules.blacklist.presets = SensitivePreset.allCases.map { preset in
            switch preset {
            case .secrets: return PresetSetting(preset: preset, enabled: true, action: .drop)
            case .verificationCode: return PresetSetting(preset: preset, enabled: true, action: .expire(minutes: 5))
            case .bankCard, .chineseID: return PresetSetting(preset: preset, enabled: false, action: .drop)
            }
        }
        return rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        whitelist = (try? c.decode(Whitelist.self, forKey: .whitelist)) ?? Whitelist()
        blacklist = (try? c.decode(Blacklist.self, forKey: .blacklist)) ?? Blacklist()
    }
}

/// 命中黑名单后的处理。
public enum RuleAction: Codable, Equatable, Hashable, Sendable {
    /// 不保存。
    case drop
    /// 保存, 复制后过 N 分钟自动删除 (收藏或放进收藏板的条目不删)。
    case expire(minutes: Int)

    /// 设置页可选的限时档位 (分钟)。
    public static let expireChoices = [1, 5, 10, 30, 60]

    /// 两个动作都命中时取更严的: 不保存 > 限时短的 > 限时长的。
    public func stricter(_ other: RuleAction) -> RuleAction {
        switch (self, other) {
        case (.drop, _), (_, .drop): return .drop
        case let (.expire(a), .expire(b)): return .expire(minutes: min(a, b))
        }
    }
}

/// 一条关键词规则。普通关键词按 `SearchText.normalize` 归一化后做子串匹配 (忽略大小写、
/// 全半角, 与搜索同一套规则); 正则匹配原文, 大小写由用户在正则里用 `(?i)` 控制。
public struct KeywordRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var pattern: String
    public var isRegex: Bool
    /// 只有黑名单用; 白名单里的关键词只决定纳入, 这个字段忽略。
    public var action: RuleAction

    public init(id: UUID = UUID(), pattern: String = "", isRegex: Bool = false, action: RuleAction = .drop) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        pattern = (try? c.decode(String.self, forKey: .pattern)) ?? ""
        isRegex = (try? c.decode(Bool.self, forKey: .isRegex)) ?? false
        action = (try? c.decode(RuleAction.self, forKey: .action)) ?? .drop
    }
}

/// 白名单: 开启后只收同时满足各项条件的内容。类型必须在勾选范围内; 来源 app、关键词
/// 的列表为空表示不限制, 不为空时要命中其中一项。
public struct Whitelist: Codable, Equatable, Sendable {
    public var enabled = false
    public var kinds: Set<ItemKind> = Set(ItemKind.selectable)
    public var apps: [String] = []
    public var keywords: [KeywordRule] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        kinds = (try? c.decode(Set<ItemKind>.self, forKey: .kinds)) ?? Set(ItemKind.selectable)
        apps = (try? c.decode([String].self, forKey: .apps)) ?? []
        keywords = (try? c.decode([KeywordRule].self, forKey: .keywords)) ?? []
    }
}

/// 黑名单: 任意一项命中就按它的动作处理。类型、来源 app、通用剪贴板、长度大小限制
/// 命中一律不保存; 关键词和敏感内容预设可以选「不保存」或「限时保留」。
public struct Blacklist: Codable, Equatable, Sendable {
    public var enabled = true
    public var kinds: Set<ItemKind> = []
    public var apps: [String] = []
    public var keywords: [KeywordRule] = []
    public var presets: [PresetSetting] = SensitivePreset.allCases.map { PresetSetting(preset: $0) }
    public var limits = SizeLimits()
    /// 不收从 iPhone、iPad 或其他 Mac 通过通用剪贴板接力过来的内容。
    public var skipUniversalClipboard = false

    public init() {}

    public func preset(_ preset: SensitivePreset) -> PresetSetting {
        presets.first { $0.preset == preset } ?? PresetSetting(preset: preset)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        kinds = (try? c.decode(Set<ItemKind>.self, forKey: .kinds)) ?? []
        apps = (try? c.decode([String].self, forKey: .apps)) ?? []
        keywords = (try? c.decode([KeywordRule].self, forKey: .keywords)) ?? []
        // 按预设逐个合并: 以后新增的预设不在旧数据里, 取默认值 (关闭)。
        let saved = (try? c.decode([PresetSetting].self, forKey: .presets)) ?? []
        presets = SensitivePreset.allCases.map { p in saved.first { $0.preset == p } ?? PresetSetting(preset: p) }
        limits = (try? c.decode(SizeLimits.self, forKey: .limits)) ?? SizeLimits()
        skipUniversalClipboard = (try? c.decode(Bool.self, forKey: .skipUniversalClipboard)) ?? false
    }
}

public struct PresetSetting: Codable, Equatable, Hashable, Sendable {
    public var preset: SensitivePreset
    public var enabled: Bool
    public var action: RuleAction

    public init(preset: SensitivePreset, enabled: Bool = false, action: RuleAction = .drop) {
        self.preset = preset
        self.enabled = enabled
        self.action = action
    }
}

/// 长度和大小限制, 每项单独开关。命中即不保存。
public struct SizeLimits: Codable, Equatable, Sendable {
    /// 去掉首尾空白后少于 N 个字符的文本不存 (挡误复制的单个字符)。
    public var minTextLengthEnabled = false
    public var minTextLength = 2
    /// 纯文本 UTF-8 超过 N KB 的不存。
    public var maxTextKBEnabled = false
    public var maxTextKB = 1024
    /// 长边小于 N 像素的图片不存 (挡小图标)。
    public var minImagePixelsEnabled = false
    public var minImagePixels = 64
    /// 超过 N MB 的图片不存。
    public var maxImageMBEnabled = false
    public var maxImageMB = 20

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SizeLimits()
        minTextLengthEnabled = (try? c.decode(Bool.self, forKey: .minTextLengthEnabled)) ?? d.minTextLengthEnabled
        minTextLength = (try? c.decode(Int.self, forKey: .minTextLength)) ?? d.minTextLength
        maxTextKBEnabled = (try? c.decode(Bool.self, forKey: .maxTextKBEnabled)) ?? d.maxTextKBEnabled
        maxTextKB = (try? c.decode(Int.self, forKey: .maxTextKB)) ?? d.maxTextKB
        minImagePixelsEnabled = (try? c.decode(Bool.self, forKey: .minImagePixelsEnabled)) ?? d.minImagePixelsEnabled
        minImagePixels = (try? c.decode(Int.self, forKey: .minImagePixels)) ?? d.minImagePixels
        maxImageMBEnabled = (try? c.decode(Bool.self, forKey: .maxImageMBEnabled)) ?? d.maxImageMBEnabled
        maxImageMB = (try? c.decode(Int.self, forKey: .maxImageMB)) ?? d.maxImageMB
    }
}

extension ItemKind: CaseIterable {
    public static let allCases: [ItemKind] = [.text, .richText, .link, .image, .file, .color]
    /// 规则里能选的类型。文件不入库 (`ClipboardMonitor.snapshot`), 不列出。
    public static let selectable: [ItemKind] = [.text, .richText, .link, .image, .color]
}
