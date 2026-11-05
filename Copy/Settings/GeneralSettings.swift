import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// 「通用」页: 语言、外观、登录时启动、菜单栏图标。
///
/// Launch at Login isn't part of `SettingsStore` (it's the `SMAppService` login-item
/// registration, not a UserDefaults value), so this view owns local state and re-reads
/// the service's actual status after every attempted change rather than trusting the
/// toggle's intent.
struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?
    /// Mirrors whether `.toggleShelf` currently has a shortcut, for the menu-bar toggle's
    /// disabled/help state. Tracked in `@State` and refreshed `onAppear`, since nothing
    /// else here is `@Observable`-tracked to that shortcut.
    @State private var shelfHotkeySet = true

    var body: some View {
        SettingsPane {
            SettingsRow(label: String(localized: "Language:"),
                        help: String(localized: "Restart Copy for language changes to take effect.")) {
                Picker("", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in Text(lang.title).tag(lang) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(label: String(localized: "Appearance:"),
                        help: String(localized: "Applies to the shelf, Paste Stack and Settings.")) {
                Picker("", selection: $settings.shelfTheme) {
                    ForEach(ShelfTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "Startup:"), help: launchAtLoginHelp) {
                Toggle(String(localized: "Launch at Login"), isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)
            }

            SettingsRow(label: String(localized: "Menu Bar:"), help: menuBarHelp) {
                // Only blocks turning the toggle ON without a hotkey — never blocks turning
                // it OFF, so a user who's already stranded can always self-rescue.
                // AppDelegate's guard is still the authoritative check either way.
                Toggle(String(localized: "Hide the Menu Bar Icon"), isOn: $settings.hideMenuBarIcon)
                    .toggleStyle(.checkbox)
                    .disabled(!shelfHotkeySet && !settings.hideMenuBarIcon)
            }
        }
        .onAppear {
            refreshLaunchAtLoginStatus()
            shelfHotkeySet = KeyboardShortcuts.getShortcut(for: .toggleShelf) != nil
        }
    }

    private var launchAtLoginHelp: String? {
        if let launchAtLoginError { return launchAtLoginError }
        if launchAtLoginNeedsApproval { return String(localized: "Waiting for approval in System Settings.") }
        return nil
    }

    private var menuBarHelp: String {
        if !shelfHotkeySet {
            return String(localized: "Set the Open Copy shortcut before hiding the menu bar icon.")
        }
        let key = KeyboardShortcuts.getShortcut(for: .toggleShelf)?.description ?? "⌥⌘V"
        return String(format: String(localized: "Copy stays available with %@; Settings is in the shelf's ⋯ menu."), key)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLoginEnabled }, set: { setLaunchAtLogin($0) })
    }

    /// `.requiresApproval` counts as "on" (registration did succeed), with help text
    /// distinguishing it from a plain, unregistered off.
    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(format: String(localized: "Couldn't update Launch at Login: %@"), error.localizedDescription)
        }
        refreshLaunchAtLoginStatus()
    }
}

/// 「卡片」页: 面板里显示多少张、收藏、链接预览、图片文字识别。
/// 放在这个文件里是为了不新增源文件 (新增要重新生成 xcodeproj)。
struct CardsSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsPane {
            SettingsRow(label: String(localized: "Show:"),
                        help: String(localized: "Maximum number of items shown in the shelf at once.")) {
                Picker("", selection: $settings.candidateLimit) {
                    ForEach([10, 25, 50], id: \.self) { n in
                        Text(String(format: String(localized: "%d cards"), n)).tag(n)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            SettingsRow(label: String(localized: "⌘ Numbers:"),
                        help: String(localized: "How card numbers appear while you hold ⌘. Press ⌘ and a number to paste that card.")) {
                Picker("", selection: $settings.numberHintStyle) {
                    ForEach(NumberHintStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            SettingsRow(label: String(localized: "Favorites:"),
                        help: String(localized: "Favorites stay at the front and are never cleaned up automatically. Turning this off keeps the ones you saved.")) {
                Toggle(String(localized: "Enable Favorites"), isOn: $settings.favoritesEnabled)
                    .toggleStyle(.checkbox)
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "Links:"),
                        help: String(localized: "Copy loads titles and icons for copied links from the web.")) {
                Toggle(String(localized: "Fetch Link Previews"), isOn: $settings.fetchLinkPreviews)
                    .toggleStyle(.checkbox)
            }

            SettingsRow(label: String(localized: "Images:"),
                        help: String(localized: "Makes text in copied images searchable. Runs entirely on your Mac.")) {
                Toggle(String(localized: "Recognize Text in Images"), isOn: $settings.recognizeImageText)
                    .toggleStyle(.checkbox)
            }
        }
    }
}

/// 「复制与粘贴」页: 去末尾换行、复制音效、触感反馈。
struct CopyPasteSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsPane {
            SettingsRow(label: String(localized: "Trailing Line Breaks:"),
                        help: String(localized: "Always removed from Copy's history and from what Copy pastes. \"Also System Clipboard\" cleans the clipboard right after you copy, so a plain ⌘V is clean too; the source app may then paste its own content with less formatting.")) {
                Picker("", selection: $settings.trailingNewlineScope) {
                    ForEach(TrailingNewlineScope.allCases) { scope in Text(scope.title).tag(scope) }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "Copy Sound:"),
                        help: String(localized: "Plays after Copy captures a new clipboard item.")) {
                Picker("", selection: $settings.copySound) {
                    ForEach(CopySound.allCases) { sound in Text(sound.title).tag(sound) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: settings.copySound) { _, sound in
                    CopySoundPlayer.shared.play(sound)
                }
            }

            SettingsRow(label: String(localized: "Haptics:"),
                        help: String(localized: "A light tap on the trackpad when you switch tabs, file a card on a pinboard, or paste.")) {
                Toggle(String(localized: "Haptic Feedback"), isOn: $settings.hapticFeedback)
                    .toggleStyle(.checkbox)
            }
        }
    }
}
