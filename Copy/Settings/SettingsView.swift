import CopyCore
import SwiftUI

/// 每个标签页的 SwiftUI 内容, 由 `SettingsWindowController` 分别装进 `NSTabViewController`
/// 的子页面。窗口外观 (浅色/深色) 跟随 `SettingsStore.shelfTheme`, 强调色统一用品牌蓝。
struct SettingsView: View {
    let section: SettingsSection
    let settings: SettingsStore
    let store: ItemStore

    var body: some View {
        content
            .tint(Tokens.electricBlue)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general:  GeneralSettings(settings: settings)
        case .history:  HistorySettings(settings: settings, store: store)
        case .panel:    PanelSettings(settings: settings)
        case .action:   ActionSettings(settings: settings)
        case .privacy:  PrivacySettings(settings: settings, store: store)
        }
    }
}
