import SwiftUI

/// 设置窗口顶部工具栏的标签页, 按显示顺序。标签名和图标只在这里定义一次。
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general    // 语言、外观、启动、菜单栏
    case shortcuts  // 打开、粘贴栈、快捷粘贴等快捷键
    case history    // 保留时长、候选数、存储
    case panel      // 外观（材质/着色/字号/亮度）、行为（记忆/共享屏幕）
    case action     // 复制（音效/触感）、粘贴（换行/⇧⌘V 来源）、卡片（编号/收藏/预览/OCR）
    case privacy    // 捕获规则

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .shortcuts: return String(localized: "Shortcuts")
        case .history: return String(localized: "History")
        case .panel: return String(localized: "Panel")
        case .action: return String(localized: "Actions")
        case .privacy: return String(localized: "Privacy")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "command"
        case .history: return "clock.arrow.circlepath"
        case .panel: return "macwindow"
        case .action: return "hand.point.up"
        case .privacy: return "hand.raised"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "Language, appearance, startup and menu bar")
        case .shortcuts: return String(localized: "Open the shelf, the paste stack and quick paste")
        case .history: return String(localized: "Retention, candidate count and storage")
        case .panel: return String(localized: "Panel appearance and display behavior")
        case .action: return String(localized: "Copy, paste and card actions")
        case .privacy: return String(localized: "Capture rules and sensitive content")
        }
    }
}
