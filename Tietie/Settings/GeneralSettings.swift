import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// 「通用」页: 语言与外观 / 启动与菜单栏 / 快捷键。
struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?
    @State private var shelfHotkeySet = true

    var body: some View {
        SettingsPane {
            // ── 语言与外观 ─────────────────────────────────────────────
            SettingsRow(label: String(localized: "Language:"),
                        help: String(localized: "Restart Tietie for language changes to take effect.")) {
                Picker("", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in Text(lang.title).tag(lang) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }

            SettingsRow(label: String(localized: "Appearance:"),
                        help: String(localized: "Applies to the shelf, Paste Stack and Settings.")) {
                Picker("", selection: $settings.shelfTheme) {
                    ForEach(ShelfTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                .labelsHidden().pickerStyle(.radioGroup).horizontalRadioGroupLayout()
            }

            SettingsDivider()

            // ── 启动与菜单栏 ───────────────────────────────────────────
            SettingsRow(label: String(localized: "Startup:"), help: launchAtLoginHelp) {
                Toggle(String(localized: "Launch at Login"), isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)
            }

            SettingsRow(label: String(localized: "Menu Bar:"), help: menuBarHelp) {
                Toggle(String(localized: "Hide the Menu Bar Icon"), isOn: $settings.hideMenuBarIcon)
                    .toggleStyle(.checkbox)
                    .disabled(!shelfHotkeySet && !settings.hideMenuBarIcon)
            }

            SettingsDivider()

            // ── 快捷键 ────────────────────────────────────────────────
            SettingsRow(label: String(localized: "Open Tietie:")) {
                KeyboardShortcuts.Recorder(for: .toggleShelf) { _ in
                    shelfHotkeySet = KeyboardShortcuts.getShortcut(for: .toggleShelf) != nil
                    settings.onShelfHotkeyChange?()
                }
            }
            SettingsRow(label: String(localized: "Paste Stack:")) {
                KeyboardShortcuts.Recorder(for: .togglePasteStack)
            }
            SettingsRow(label: String(localized: "Next Pinboard:")) {
                KeyboardShortcuts.Recorder(for: .nextPinboard)
            }
            SettingsRow(label: String(localized: "Quick Paste Latest:"),
                        help: String(localized: "Pastes your most recent item into the current app without opening Tietie.")) {
                KeyboardShortcuts.Recorder(for: .quickPasteLatest)
            }
            SettingsRow(label: String(localized: "Paste Latest as Plain Text:"),
                        help: String(localized: "Same, without any formatting.")) {
                KeyboardShortcuts.Recorder(for: .pasteLatestPlainText)
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "In the Shelf:")) {
                VStack(alignment: .leading, spacing: 6) {
                    ShortcutHintLine(keys: "⌥1–9", text: String(localized: "Switch to a tab"))
                    ShortcutHintLine(keys: "⌘1–9", text: String(localized: "Paste that card"))
                    ShortcutHintLine(keys: "⌘F",   text: String(localized: "Search"))
                    ShortcutHintLine(keys: "⇧↩",   text: String(localized: "Paste as plain text"))
                }
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
        if !shelfHotkeySet { return String(localized: "Set the Open Tietie shortcut before hiding the menu bar icon.") }
        let key = KeyboardShortcuts.getShortcut(for: .toggleShelf)?.description ?? "⌥⌘V"
        return String(format: String(localized: "Tietie stays available with %@; Settings is in the shelf's ⋯ menu."), key)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLoginEnabled }, set: { setLaunchAtLogin($0) })
    }

    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(format: String(localized: "Couldn't update Launch at Login: %@"), error.localizedDescription)
        }
        refreshLaunchAtLoginStatus()
    }
}

// ── 面板内快捷键说明行 ─────────────────────────────────────────────────────
private struct ShortcutHintLine: View {
    let keys: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            KeyCap(text: keys).frame(minWidth: 52, alignment: .leading)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
