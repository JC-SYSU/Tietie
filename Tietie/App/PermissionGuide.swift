import AppKit
import Foundation

/// 系统设置里的权限面板名称。macOS 27 把「辅助功能」并进了「设备控制与数据访问」，
/// 27.3 beta 2 又把它拆开；深链一直能用，但文案里的面板名必须跟着系统版本走，
/// 否则用户照着旧名字在系统设置里找不到入口。
///
/// 27.0–27.2 的英文名是按中文名直译的，未在 27 实机上核对；改动前先看系统设置实际显示。
enum PermissionGuide {
    // MARK: - 深链

    /// 27 仍接受这两个 anchor。系统不认识 anchor 时会退回「隐私与安全性」根页，
    /// 不会报错。
    private static let accessibilityAnchor = "Privacy_Accessibility"
    private static let pasteboardAnchor = "Privacy_Pasteboard"

    static func openAccessibilitySettings() {
        open(anchor: accessibilityAnchor)
    }

    static func openPasteboardSettings() {
        open(anchor: pasteboardAnchor)
    }

    private static func open(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 面板名称

    /// 当前系统里装「辅助功能」开关的那个面板名。
    static var accessibilityPaneTitle: String {
        if isAtLeast(major: 27, minor: 3) {
            // 27.3 beta 2 拆成「System & App Protection Override」和「Accessibility」，
            // 合成按键事件仍然归 Accessibility。
            return String(localized: "Accessibility")
        }
        if isAtLeast(major: 27, minor: 0) {
            return String(localized: "Device Control & Data Access")
        }
        return String(localized: "Accessibility")
    }

    /// 剪贴板权限的面板名，27.2 起是「从其他 App 粘贴」。
    static var pasteboardPaneTitle: String {
        String(localized: "Paste from Other Apps")
    }

    /// macOS 27 起程序化读取剪贴板默认要先询问；26 及更早默认不询问
    /// （开发者预览期需要手动打开 EnablePasteboardPrivacyDeveloperPreview）。
    /// 在旧系统上 `.default` 表示「没有这道限制」，不是「还没授权」。
    static var pasteboardPrivacyIsEnforced: Bool {
        isAtLeast(major: 27, minor: 0)
    }

    private static func isAtLeast(major: Int, minor: Int) -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion != major { return version.majorVersion > major }
        return version.minorVersion >= minor
    }
}
