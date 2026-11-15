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
            SettingsBrandView()

            SettingsDivider()

            // ── 语言与外观 ─────────────────────────────────────────────
            SettingsRow(label: String(localized: "Language:"),
                        help: String(localized: "Restart Tietie for language changes to take effect.")) {
                KleinPopUp(options: AppLanguage.allCases.map { ($0, $0.title) },
                           selection: $settings.appLanguage)
                    .frame(width: 280)
            }

            SettingsRow(label: String(localized: "Appearance:"),
                        help: String(localized: "Applies to the shelf, Paste Stack and Settings.")) {
                KleinSegmented(options: ShelfTheme.allCases.map { ($0, $0.title) },
                               selection: $settings.shelfTheme)
                    .frame(width: 300)
            }

            SettingsDivider()

            // ── 启动与菜单栏 ───────────────────────────────────────────
            SettingsRow(label: String(localized: "Startup:"), help: launchAtLoginHelp) {
                Toggle(String(localized: "Launch at Login"), isOn: launchAtLoginBinding)
            }

            SettingsRow(label: String(localized: "Menu Bar:"), help: menuBarHelp) {
                Toggle(String(localized: "Hide the Menu Bar Icon"), isOn: $settings.hideMenuBarIcon)
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
