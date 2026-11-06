import AppKit
import Foundation
import Observation

/// Optional feedback played after Copy successfully records a clipboard change. Every
/// case but `off` is one of the fourteen sounds macOS ships in `/System/Library/Sounds`,
/// listed in the order the system itself lists them, and the picker shows each under the
/// name the system uses, so what a screener reads here is what they would read in Sound
/// settings. Raw values are persisted in UserDefaults, so keep them stable across
/// releases.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: Self { self }
    var title: String {
        switch self {
        case .system: return String(localized: "Follow System")
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

enum CopySound: String, CaseIterable, Identifiable {
    case off
    case basso, blow, bottle, frog, funk, glass, hero
    case morse, ping, pop, purr, sosumi, submarine, tink

    var id: Self { self }

    /// The sound's file name under `/System/Library/Sounds`. Capitalising the raw value
    /// is the whole mapping, because every sound macOS ships is a single capitalised
    /// word. A name that ever stops resolving simply plays nothing (see `CopySoundPlayer`).
    var systemSoundName: NSSound.Name? {
        guard self != .off else { return nil }
        return NSSound.Name(rawValue.capitalized)
    }

    var title: String {
        systemSoundName ?? String(localized: "Off")
    }
}

/// 面板背景材质 (设置 → 面板)。前三种是 Liquid Glass (`Glass`, macOS 26+), 后三种是
/// macOS 26 以前的 `NSVisualEffectView` 毛玻璃材质。系统开了「降低透明度」时一律用
/// `.hudWindow` 实体材质, 不看这里。
enum PanelMaterial: String, CaseIterable, Identifiable {
    case glassRegular, glassClear, glassIdentity
    case hudWindow, sidebar, windowBackground

    var id: Self { self }
    var title: String {
        switch self {
        case .glassRegular: return String(localized: "Liquid Glass – Regular")
        case .glassClear: return String(localized: "Liquid Glass – Clear")
        case .glassIdentity: return String(localized: "No Material")
        case .hudWindow: return String(localized: "HUD Window")
        case .sidebar: return String(localized: "Sidebar")
        case .windowBackground: return String(localized: "Window Background")
        }
    }
    /// 液态玻璃 regular / clear 用 `Glass.tint` 给材质本身上色; HUD / 边栏 / 窗口背景
    /// 没有着色接口, 叠一层同色半透明。无材质没有可着色的面。
    var supportsTint: Bool { self != .glassIdentity }
}

/// 按住 ⌘ 时卡片编号的显示样式 (设置 → 卡片)。
enum NumberHintStyle: String, CaseIterable, Identifiable {
    /// 色带右侧的时间换成「⌘1」小键帽, 卡片内容不遮。
    case bandKeycap
    /// 卡片不动, 底部快捷键图例换成一排键帽, 每枚正对一张卡。
    case keyRail
    /// 整张卡变淡, 右下角浮出大号细体数字。
    case editorial

    var id: Self { self }
    var title: String {
        switch self {
        case .bandKeycap: return String(localized: "Keycap in Header")
        case .keyRail: return String(localized: "Keycaps Below Cards")
        case .editorial: return String(localized: "Large Numbers")
        }
    }
}

/// Persisted appearance choice shared by the shelf, Paste Stack and Settings.
enum ShelfTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: return String(localized: "Follow System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// 末尾换行去除的作用范围。去换行本身始终开启, 这里只选是否连系统剪贴板一起改写
/// (见 `ClipboardMonitor.rewritesSystemClipboard`)。Raw value 存 UserDefaults, 保持稳定。
enum TrailingNewlineScope: String, CaseIterable, Identifiable {
    case history
    case systemClipboard

    var id: Self { self }
    var title: String {
        switch self {
        case .history: return String(localized: "Copy History Only")
        case .systemClipboard: return String(localized: "Also System Clipboard")
        }
    }
}

/// How long unfavorited, unpinned history items are kept before pruning.
enum RetentionPeriod: String, CaseIterable {
    case unlimited
    case day
    case week
    case month
    case threeMonths

    /// The earliest `lastUsedAt` to keep; `nil` means keep everything.
    var cutoff: Date? {
        let now = Date()
        switch self {
        case .unlimited:
            return nil
        case .day:
            return Calendar.current.date(byAdding: .day, value: -1, to: now)
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            return Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            return Calendar.current.date(byAdding: .month, value: -3, to: now)
        }
    }

    var title: String {
        switch self {
        case .unlimited: return String(localized: "Unlimited")
        case .day: return String(localized: "1 Day")
        case .week: return String(localized: "1 Week")
        case .month: return String(localized: "1 Month")
        case .threeMonths: return String(localized: "3 Months")
        }
    }

    /// Shortest-to-longest order for the History pane's `StepSlider`, ending in Unlimited
    /// (the default) at the far right. The `enum`'s own declaration order leads with
    /// `.unlimited`, which is the right default but the wrong slider position.
    static let sliderOrder: [RetentionPeriod] = [.day, .week, .month, .threeMonths, .unlimited]
}

/// UserDefaults-backed app settings. Mutating `excludedBundleIDs` (directly or via
/// `addExcludedApp`/`removeExcludedApp`) fires `onRulesChange` so the coordinator can
/// push a fresh `RulesEngine` into the clipboard monitor.
@MainActor
@Observable
final class SettingsStore {
    static let retentionKey = "retentionPeriod"
    static let fetchLinkPreviewsKey = "fetchLinkPreviews"
    static let recognizeImageTextKey = "recognizeImageText"
    static let excludedBundleIDsKey = "excludedBundleIDs"
    static let hideDuringScreenSharingKey = "hideDuringScreenSharing"
    static let favoritesEnabledKey = "favoritesEnabled"
    static let floatingShelfKey = "floatingShelf"
    static let compactShelfKey = "compactShelf"
    static let shelfThemeKey = "shelfTheme"
    static let shelfProDarkKey = "shelfProDark"
    static let hideMenuBarIconKey = "hideMenuBarIcon"
    static let doubleClickToPasteKey = "doubleClickToPaste"
    static let copySoundKey = "copySound"
    static let hapticFeedbackKey = "hapticFeedback"
    static let appLanguageKey = "appLanguage"
    static let candidateLimitKey = "candidateLimit"
    static let trailingNewlineScopeKey = "trailingNewlineScope"
    static let numberHintStyleKey = "numberHintStyle"
    static let panelMaterialKey = "panelMaterial"
    static let panelTintHexKey = "panelTintHex"
    static let panelTintOpacityKey = "panelTintOpacity"
    static let panelFontSizeKey = "panelFontSize"
    static let cardBrightnessKey = "cardBrightness"
    static let dimsScreenKey = "dimsScreenBehindShelf"

    var retention: RetentionPeriod {
        didSet {
            guard retention != oldValue else { return }
            defaults.set(retention.rawValue, forKey: Self.retentionKey)
        }
    }

    var fetchLinkPreviews: Bool {
        didSet {
            guard fetchLinkPreviews != oldValue else { return }
            defaults.set(fetchLinkPreviews, forKey: Self.fetchLinkPreviewsKey)
        }
    }

    var recognizeImageText: Bool {
        didSet {
            guard recognizeImageText != oldValue else { return }
            defaults.set(recognizeImageText, forKey: Self.recognizeImageTextKey)
        }
    }

    var excludedBundleIDs: [String] {
        didSet {
            guard excludedBundleIDs != oldValue else { return }
            persistExcludedBundleIDs()
            onRulesChange?(Set(excludedBundleIDs))
        }
    }

    /// When true, the shelf panel and Paste Stack palette set `NSWindowSharingType.none`
    /// so they're excluded from screen recordings/captures/shares (see
    /// `ShelfPanelController.setHideDuringScreenSharing`/`PasteStackController`'s
    /// equivalent). Defaults to false: Copy is visible in screenshots and recordings
    /// out of the box (so people can capture and share it), and hiding is opt-in.
    var hideDuringScreenSharing: Bool {
        didSet {
            guard hideDuringScreenSharing != oldValue else { return }
            defaults.set(hideDuringScreenSharing, forKey: Self.hideDuringScreenSharingKey)
            onHideDuringScreenSharingChange?(hideDuringScreenSharing)
        }
    }

    /// Narrower/shorter cards and a shorter shelf panel, so more items fit at a glance.
    /// `ShelfRootView`/`ItemCardView` read this live (via `ShelfViewModel.settings`,
    /// since both are `@Observable`), and `onCompactShelfChange` pushes it to
    /// `ShelfPanelController` so the panel's own frame height adapts, mirroring
    /// `hideDuringScreenSharing`'s wiring above.
    var compactShelf: Bool {
        didSet {
            guard compactShelf != oldValue else { return }
            defaults.set(compactShelf, forKey: Self.compactShelfKey)
            onCompactShelfChange?(compactShelf)
        }
    }

    /// Whether the shelf floats clear of the screen edge instead of sitting flush against
    /// it. Off by default, so the shelf stays edge attached. `onFloatingShelfChange` pushes
    /// it to the panel controller, which re-frames the window live.
    var floatingShelf: Bool {
        didSet {
            guard floatingShelf != oldValue else { return }
            defaults.set(floatingShelf, forKey: Self.floatingShelfKey)
            onFloatingShelfChange?(floatingShelf)
        }
    }
    @ObservationIgnored var onFloatingShelfChange: ((Bool) -> Void)?

    /// Hides favorites presentation without deleting saved marks or retention protection.
    var favoritesEnabled: Bool {
        didSet {
            guard favoritesEnabled != oldValue else { return }
            defaults.set(favoritesEnabled, forKey: Self.favoritesEnabledKey)
            onFavoritesEnabledChange?(favoritesEnabled)
        }
    }
    @ObservationIgnored var onFavoritesEnabledChange: ((Bool) -> Void)?

    /// The appearance the shelf, paste stack and Settings window follow. `.system` tracks
    /// the OS. `.dark` is the old "pro dark" look: a forced dark appearance plus an
    /// electric-blue accent, regardless of the system appearance or accent color, so the
    /// app can match its own marketing look. `onShelfThemeChange` pushes it to the panel
    /// controllers (which set the window appearance live); `ShelfRootView` reads it via
    /// `ShelfViewModel.settings` to apply the tint. Replaces the older `shelfProDark`
    /// flag, which `init` still reads once to migrate anyone who had it on.
    var shelfTheme: ShelfTheme {
        didSet {
            guard shelfTheme != oldValue else { return }
            defaults.set(shelfTheme.rawValue, forKey: Self.shelfThemeKey)
            onShelfThemeChange?(shelfTheme)
        }
    }

    /// When true, `AppDelegate` removes the `NSStatusItem` so Copy runs with no menu
    /// bar icon at all, relying on the shelf's own drawer menu (and the shelf summon
    /// hotkey) instead. Defaults to false: the icon is shown out of the box, and
    /// going menu-bar-free is opt-in. `AppDelegate` applies an anti-stranding guard on
    /// top of this value — it refuses to actually hide the icon if the shelf summon
    /// hotkey is unset — so this property alone doesn't guarantee the icon is hidden.
    var hideMenuBarIcon: Bool {
        didSet {
            guard hideMenuBarIcon != oldValue else { return }
            defaults.set(hideMenuBarIcon, forKey: Self.hideMenuBarIconKey)
            onHideMenuBarIconChange?(hideMenuBarIcon)
        }
    }

    /// When true, a plain click on a shelf card only selects it (no paste) — pasting
    /// takes a double-click or ⏎. Defaults to true: this is the safer default, since a
    /// stray single click can no longer paste a card into whatever app is frontmost.
    /// Read live at click time via `ShelfViewModel.settings` (both `@Observable`), so
    /// there's no change-hook to wire — unlike `compactShelf`/`hideMenuBarIcon`, nothing
    /// outside SwiftUI needs to react to this changing.
    var doubleClickToPaste: Bool {
        didSet {
            guard doubleClickToPaste != oldValue else { return }
            defaults.set(doubleClickToPaste, forKey: Self.doubleClickToPasteKey)
        }
    }

    /// Sound feedback for successful clipboard captures. Off is the intentional
    /// default so installing or updating Copy never adds noise without consent.
    var copySound: CopySound {
        didSet {
            guard copySound != oldValue else { return }
            defaults.set(copySound.rawValue, forKey: Self.copySoundKey)
        }
    }

    /// Trackpad haptics on shelf interactions (tab switches, filing a card, pasting…).
    /// On by default: the taps are subtle and only fire for things the user did. Mirrored
    /// into `Haptics.isEnabled` so call sites don't need the store.
    var hapticFeedback: Bool {
        didSet {
            guard hapticFeedback != oldValue else { return }
            defaults.set(hapticFeedback, forKey: Self.hapticFeedbackKey)
            Haptics.isEnabled = hapticFeedback
        }
    }

    /// UI 语言。写入 `AppleLanguages` 并要求重启生效——系统框架无法在运行时切换。
    var appLanguage: AppLanguage {
        didSet {
            guard appLanguage != oldValue else { return }
            defaults.set(appLanguage.rawValue, forKey: Self.appLanguageKey)
            switch appLanguage {
            case .system:
                defaults.removeObject(forKey: "AppleLanguages")
            case .zhHans, .en:
                defaults.set([appLanguage.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    /// 搜索结果候选上限。10/25/50 三档, 由设置面板选定。
    var candidateLimit: Int {
        didSet {
            guard candidateLimit != oldValue else { return }
            defaults.set(candidateLimit, forKey: Self.candidateLimitKey)
        }
    }

    /// 默认只处理 Copy 历史; 改成系统剪贴板时经 `onTrailingNewlineScopeChange` 推给监视器。
    var trailingNewlineScope: TrailingNewlineScope {
        didSet {
            guard trailingNewlineScope != oldValue else { return }
            defaults.set(trailingNewlineScope.rawValue, forKey: Self.trailingNewlineScopeKey)
            onTrailingNewlineScopeChange?(trailingNewlineScope)
        }
    }
    @ObservationIgnored var onTrailingNewlineScopeChange: ((TrailingNewlineScope) -> Void)?

    /// 面板背景材质。面板视图直接读, 改了立即生效。
    var panelMaterial: PanelMaterial {
        didSet { if panelMaterial != oldValue { defaults.set(panelMaterial.rawValue, forKey: Self.panelMaterialKey) } }
    }
    /// 玻璃着色颜色, "RRGGBB" (不带 #)。
    var panelTintHex: String {
        didSet { if panelTintHex != oldValue { defaults.set(panelTintHex, forKey: Self.panelTintHexKey) } }
    }
    /// 玻璃着色不透明度 0–1, 步进 0.1; 0 表示不着色。
    var panelTintOpacity: Double {
        didSet { if panelTintOpacity != oldValue { defaults.set(panelTintOpacity, forKey: Self.panelTintOpacityKey) } }
    }
    /// 面板上直接压在玻璃上的文字 (标签、快捷键图例、页码) 的字号, 10–15pt。
    var panelFontSize: Double {
        didSet {
            guard panelFontSize != oldValue else { return }
            defaults.set(panelFontSize, forKey: Self.panelFontSizeKey)
            onPanelFontSizeChange?(panelFontSize)
        }
    }
    @ObservationIgnored var onPanelFontSizeChange: ((Double) -> Void)?
    /// 唤出面板时整个屏幕变暗。
    var dimsScreen: Bool {
        didSet {
            guard dimsScreen != oldValue else { return }
            defaults.set(dimsScreen, forKey: Self.dimsScreenKey)
            onDimsScreenChange?(dimsScreen)
        }
    }
    @ObservationIgnored var onDimsScreenChange: ((Bool) -> Void)?
    /// 卡片底色的 HDR 亮度倍数, 1.0 = 普通白。大于 1 时用屏幕的 HDR 余量让卡片比
    /// SDR 白更亮; 屏幕不支持 HDR 时看起来和 1.0 一样。
    var cardBrightness: Double {
        didSet { if cardBrightness != oldValue { defaults.set(cardBrightness, forKey: Self.cardBrightnessKey) } }
    }

    /// 按住 ⌘ 时的编号样式。面板视图直接读 (SettingsStore 是 @Observable), 不需要回调。
    var numberHintStyle: NumberHintStyle {
        didSet {
            guard numberHintStyle != oldValue else { return }
            defaults.set(numberHintStyle.rawValue, forKey: Self.numberHintStyleKey)
        }
    }

    @ObservationIgnored var onRulesChange: ((Set<String>) -> Void)?
    /// Fired by the About pane's "View Onboarding Again" button. Wired to
    /// `AppCoordinator.showOnboarding()`, which re-presents the welcome flow from step 0.
    @ObservationIgnored var onShowOnboarding: (() -> Void)?
    @ObservationIgnored var onHideDuringScreenSharingChange: ((Bool) -> Void)?
    @ObservationIgnored var onCompactShelfChange: ((Bool) -> Void)?
    @ObservationIgnored var onShelfThemeChange: ((ShelfTheme) -> Void)?
    @ObservationIgnored var onHideMenuBarIconChange: ((Bool) -> Void)?
    /// Not backed by a stored property here — the shelf summon hotkey itself lives in
    /// `KeyboardShortcuts`' own storage (see `KeyboardShortcuts.Name.toggleShelf`), not
    /// in `SettingsStore`. This is a pure passthrough notification: `GeneralSettings`
    /// calls it from the `.toggleShelf` `KeyboardShortcuts.Recorder`'s `onChange`, and
    /// `AppDelegate` uses it as the third trigger to re-run its `hideMenuBarIcon`
    /// anti-stranding guard (`applyHideMenuBarIconSetting`) — that guard must re-check
    /// even when `hideMenuBarIcon` itself didn't change, since clearing the hotkey while
    /// already hidden is exactly the case it exists to catch.
    @ObservationIgnored var onShelfHotkeyChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.retentionKey), let period = RetentionPeriod(rawValue: raw) {
            retention = period
        } else {
            retention = .unlimited
        }
        // 出厂默认值 (2026-11-06 起) 取自作者本机当时的设置: HUD 窗口材质、复制音效 Pop、
        // 隐藏菜单栏图标、共享屏幕时隐藏、界面简体中文、不排除任何 app、唤出时屏幕变暗。
        panelMaterial = defaults.string(forKey: Self.panelMaterialKey).flatMap(PanelMaterial.init(rawValue:)) ?? .hudWindow
        panelTintHex = defaults.string(forKey: Self.panelTintHexKey) ?? "FFFFFF"
        panelTintOpacity = Self.clamp(defaults.object(forKey: Self.panelTintOpacityKey) as? Double ?? 0, 0, 1)
        panelFontSize = Self.clamp(defaults.object(forKey: Self.panelFontSizeKey) as? Double ?? 11, 10, 15)
        dimsScreen = (defaults.object(forKey: Self.dimsScreenKey) as? Bool) ?? true
        cardBrightness = Self.clamp(defaults.object(forKey: Self.cardBrightnessKey) as? Double ?? 1, 1, 2)
        numberHintStyle = defaults.string(forKey: Self.numberHintStyleKey)
            .flatMap(NumberHintStyle.init(rawValue:)) ?? .bandKeycap
        fetchLinkPreviews = false
        recognizeImageText = false
        hideDuringScreenSharing = (defaults.object(forKey: Self.hideDuringScreenSharingKey) as? Bool) ?? true
        favoritesEnabled = (defaults.object(forKey: Self.favoritesEnabledKey) as? Bool) ?? true
        floatingShelf = (defaults.object(forKey: Self.floatingShelfKey) as? Bool) ?? false
        compactShelf = (defaults.object(forKey: Self.compactShelfKey) as? Bool) ?? false
        if let raw = defaults.string(forKey: Self.shelfThemeKey), let saved = ShelfTheme(rawValue: raw) {
            shelfTheme = saved
        } else {
            let migrated: ShelfTheme = defaults.bool(forKey: Self.shelfProDarkKey) ? .dark : .system
            shelfTheme = migrated
            defaults.set(migrated.rawValue, forKey: Self.shelfThemeKey)
        }
        hideMenuBarIcon = (defaults.object(forKey: Self.hideMenuBarIconKey) as? Bool) ?? true
        doubleClickToPaste = (defaults.object(forKey: Self.doubleClickToPasteKey) as? Bool) ?? true
        copySound = defaults.string(forKey: Self.copySoundKey)
            .flatMap(CopySound.init(rawValue:)) ?? .pop
        let haptics = (defaults.object(forKey: Self.hapticFeedbackKey) as? Bool) ?? true
        hapticFeedback = haptics
        Haptics.isEnabled = haptics
        if let raw = defaults.string(forKey: Self.appLanguageKey), let lang = AppLanguage(rawValue: raw) {
            appLanguage = lang
        } else {
            // 出厂简体中文。init 里给属性赋值不触发 didSet, 这里手动写入 AppleLanguages,
            // 系统才按中文加载 .lproj (首次启动的界面是英文, 下次启动起变中文)。
            appLanguage = .zhHans
            defaults.set(AppLanguage.zhHans.rawValue, forKey: Self.appLanguageKey)
            if defaults.object(forKey: "AppleLanguages") == nil {
                defaults.set([AppLanguage.zhHans.rawValue], forKey: "AppleLanguages")
            }
        }
        let savedLimit = defaults.object(forKey: Self.candidateLimitKey) as? Int
        candidateLimit = [10, 25, 50].contains(savedLimit) ? savedLimit! : 25
        trailingNewlineScope = defaults.string(forKey: Self.trailingNewlineScopeKey)
            .flatMap(TrailingNewlineScope.init(rawValue:)) ?? .history
        if let data = defaults.data(forKey: Self.excludedBundleIDsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            excludedBundleIDs = decoded.sorted()
        } else if defaults.object(forKey: Self.excludedBundleIDsKey) == nil,
                  !defaults.bool(forKey: "hasOnboarded") {
            // Only a new profile gets defaults; preserve existing lists, including [].
            // 出厂不排除任何 app (作者本机设置)。密码管理器标记为隐藏的内容另有规则拦截,
            // 不靠这个列表。
            excludedBundleIDs = []
            persistExcludedBundleIDs()
        } else {
            excludedBundleIDs = []
        }
        // 设置面板已移除以下选项, 统一固定值: 标准尺寸 / 边缘附着 / 点击选中。
        compactShelf = false
        floatingShelf = false
        doubleClickToPaste = true
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    func addExcludedApp(bundleID: String) {
        guard !excludedBundleIDs.contains(bundleID) else { return }
        excludedBundleIDs = (excludedBundleIDs + [bundleID]).sorted()
    }

    func removeExcludedApp(bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    private func persistExcludedBundleIDs() {
        guard let data = try? JSONEncoder().encode(excludedBundleIDs) else { return }
        defaults.set(data, forKey: Self.excludedBundleIDsKey)
    }
}
