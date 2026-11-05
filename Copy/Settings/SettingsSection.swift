import SwiftUI

/// 设置窗口顶部工具栏的标签页, 按显示顺序。标签名和图标只在这里定义一次。
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case cards
    case copyPaste
    case shortcuts
    case history
    case privacy
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .cards: return String(localized: "Cards")
        case .copyPaste: return String(localized: "Copy & Paste")
        case .shortcuts: return String(localized: "Shortcuts")
        case .history: return String(localized: "History")
        case .privacy: return String(localized: "Privacy")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .cards: return "rectangle.on.rectangle"
        case .copyPaste: return "doc.on.clipboard"
        case .shortcuts: return "command"
        case .history: return "clock.arrow.circlepath"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}
