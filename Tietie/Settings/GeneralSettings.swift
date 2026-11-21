import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// 「通用」页: 语言与外观 / 启动与菜单栏 / 权限。
struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?
    @State private var shelfHotkeySet = true
    @State private var accessibilityTrusted = AXIsProcessTrusted()
    @State private var pasteboardBehavior = NSPasteboard.general.accessBehavior
    /// 点「授权」时剪贴板是空的, 系统不会弹提示, 也就无法让贴贴进入设置列表。
    @State private var clipboardNeedsContent = false

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

            SettingsDivider()

            // ── 权限 ───────────────────────────────────────────────────
            // 两个权限的申请入口都放在这里: onboarding 只出现一次, 之后权限被撤销
            // 或剪贴板被改成「询问」时, 用户需要一个能重新申请的固定位置。
            SettingsRow(label: String(localized: "Accessibility:"), help: accessibilityHelp) {
                Button(accessibilityTrusted
                       ? String(localized: "Open Settings")
                       : String(localized: "Grant Access")) {
                    requestAccessibility()
                }
                .buttonStyle(KleinButtonStyle(prominent: !accessibilityTrusted))
            }

            // 26 及更早默认不强制剪贴板权限, 没有可申请的东西; 只有系统已经记录过
            // 访问行为(或系统强制)时才显示这一行。
            if showsClipboardRow {
                SettingsRow(label: String(localized: "Clipboard:"), help: clipboardHelp) {
                    Button(pasteboardBehavior == .default
                           ? String(localized: "Grant Access")
                           : String(localized: "Open Settings")) {
                        requestClipboardAccess()
                    }
                    .buttonStyle(KleinButtonStyle(prominent: pasteboardBehavior == .default))
                }
            }

        }
        .onAppear {
            refreshLaunchAtLoginStatus()
            shelfHotkeySet = KeyboardShortcuts.getShortcut(for: .toggleShelf) != nil
            refreshPermissionState()
        }
        // 用户在系统设置里改完权限切回来, 状态要跟着变, 不用重开设置窗口。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
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

    // MARK: - 权限

    /// 26 及更早默认不强制剪贴板权限, 那一行没有意义; 系统已经记录过访问行为时
    /// (`.ask`/`.alwaysAllow`/`.alwaysDeny`) 才显示。
    private var showsClipboardRow: Bool {
        PermissionGuide.pasteboardPrivacyIsEnforced || pasteboardBehavior != .default
    }

    private var accessibilityHelp: String? {
        if accessibilityTrusted { return String(localized: "Granted.") }
        return String(
            format: String(localized: "Pasting needs this. Turn on Tietie under Privacy & Security > %@."),
            PermissionGuide.accessibilityPaneTitle
        )
    }

    private var clipboardHelp: String? {
        switch pasteboardBehavior {
        case .alwaysAllow:
            return String(localized: "Granted.")
        case .ask:
            return String(localized: "Listed in System Settings. Set Tietie to Always Allow so saving history doesn't ask on every copy.")
        case .alwaysDeny:
            return String(localized: "Denied in System Settings.")
        default:
            return clipboardNeedsContent
                ? String(localized: "The clipboard is empty. Copy any text, then grant access again.")
                : String(localized: "Tietie has to ask once before it appears in the list. Copy any text, then grant access.")
        }
    }

    private func refreshPermissionState() {
        accessibilityTrusted = AXIsProcessTrusted()
        pasteboardBehavior = NSPasteboard.general.accessBehavior
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        PermissionGuide.openAccessibilitySettings()
    }

    /// 27 的系统提示只在程序化读取剪贴板内容时出现, 这次读取同时也是贴贴进入
    /// 「从其他 App 粘贴」列表的前提。读取之后状态离开 `.default` 才打开面板;
    /// 空剪贴板没有内容可读, 系统不会提示, 也就不该把用户送进一个找不到贴贴的面板。
    private func requestClipboardAccess() {
        clipboardNeedsContent = false
        guard pasteboardBehavior == .default else {
            PermissionGuide.openPasteboardSettings()
            return
        }
        _ = NSPasteboard.general.pasteboardItems
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            refreshPermissionState()
            if pasteboardBehavior == .default {
                clipboardNeedsContent = true
            } else {
                PermissionGuide.openPasteboardSettings()
            }
        }
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
