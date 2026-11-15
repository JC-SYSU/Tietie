import TietieCore
import SwiftUI

/// 每个标签页的 SwiftUI 内容，由 `SettingsWindowController` 分别装进独立宿主视图。
/// 视觉沿用觅见：19pt 页标题 + 12pt 副标题，控件由 `SettingsControls.swift` 自绘。
struct SettingsView: View {
    let section: SettingsSection
    let settings: SettingsStore
    let store: ItemStore

    var body: some View {
        content
            .tint(SettingsTheme.klein)
            .toggleStyle(KleinCheckboxStyle())
            .textFieldStyle(KleinTextFieldStyle())
    }

    @ViewBuilder private var content: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(title: section.title)
                    .padding(.horizontal, SettingsLayout.paneInset)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                switch section {
                case .general:  GeneralSettings(settings: settings)
                case .shortcuts: ShortcutsSettings(settings: settings)
                case .history:  HistorySettings(settings: settings, store: store)
                case .panel:    PanelSettings(settings: settings)
                case .action:   ActionSettings(settings: settings)
                case .privacy:  PrivacySettings(settings: settings, store: store)
                }
            }
            .frame(width: SettingsLayout.contentWidth, alignment: .topLeading)
        }
        .frame(width: SettingsLayout.contentWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .settingsCanvas()
    }
}
