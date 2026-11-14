import SwiftUI
import AppKit
import TietieCore
import UniformTypeIdentifiers

enum Tokens {
    static let cardWidth: CGFloat = 184
    /// 244 → 200: 面板整体降高 (用户要求不放大字号而是降低面板), 正文 11 → 8 行。
    static let cardHeight: CGFloat = 200
    static let cardGap: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let shelfPadding: CGFloat = 20

    /// Compact shelf mode (`SettingsStore.compactShelf`): narrower/shorter cards and a
    /// tighter grid, so more items fit at a glance. `cardWidth(compact:)`/`cardHeight(compact:)`
    /// etc. below are what call sites should read rather than branching on the raw
    /// constants directly.
    static let compactCardWidth: CGFloat = 132
    static let compactCardHeight: CGFloat = 168
    static let compactCardGap: CGFloat = 8
    static let compactShelfPadding: CGFloat = 14

    /// 卡头 app 色带高度 (色带内放图标 + app 名 + 时间)。
    static let cardBandHeight: CGFloat = 30
    static let compactCardBandHeight: CGFloat = 24
    static func cardBandHeight(compact: Bool) -> CGFloat { compact ? compactCardBandHeight : cardBandHeight }

    static func cardWidth(compact: Bool) -> CGFloat { compact ? compactCardWidth : cardWidth }
    static func cardHeight(compact: Bool) -> CGFloat { compact ? compactCardHeight : cardHeight }
    static func cardGap(compact: Bool) -> CGFloat { compact ? compactCardGap : cardGap }
    static func shelfPadding(compact: Bool) -> CGFloat { compact ? compactShelfPadding : shelfPadding }

    /// 多巴胺色板: 新建收藏板自动轮转分配主题色的来源, 编辑弹层的预设色点同源。
    /// 存不带 # 的 hex, 与 `Pinboard.tint` 的存储格式一致。
    static let dopaminePalette: [(name: String, hex: String)] = [
        ("Coral", "FF6B6B"),     // 珊瑚红
        ("Tangerine", "FF9F43"), // 橘
        ("Sunshine", "FFD93D"),  // 柠檬黄
        ("Leaf", "6BCB77"),      // 叶绿
        ("Mint", "06D6A0"),      // 薄荷青
        ("Sky", "4CC9F0"),       // 天蓝
        ("Iris", "5E60CE"),      // 鸢尾蓝紫
        ("Orchid", "9B5DE5"),    // 兰紫
        ("Fuchsia", "F15BB5"),   // 品红
    ]

    /// Regular clipboard prose uses the native system face; code keeps monospace.
    static let cardBody = Font.system(size: 12)
    static let bodyMono = Font.system(size: 11, design: .monospaced)
    static let caption = Font.system(size: 10, weight: .medium)
    static let cardTitle = Font.system(size: 11, weight: .semibold)
    /// Secondary-but-prominent label style: `ItemCardView`'s custom-title row and its
    /// link-card host name. One step up from `cardTitle`, shared so both read at the
    /// same size/weight instead of each carrying its own literal.
    static let cardSubtitle = Font.system(size: 12, weight: .semibold)

    /// The marketing "electric blue" accent, used as the fixed tint in the pro-dark
    /// shelf so the app matches its own brand look regardless of the system accent.
    static let electricBlue = Color(red: 0.298, green: 0.616, blue: 1.0) // #4C9DFF

    static func color(fromHex hex: String) -> Color {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            return .gray
        }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    /// Converts a SwiftUI `Color` back to a "#RRGGBB" hex string, matching
    /// `PasteboardReading.colorHex()`'s sRGB formatting so a re-copied color round-trips
    /// through the same representation a captured color would.
    static func hex(from color: Color) -> String {
        let srgb = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return String(format: "#%02X%02X%02X",
                      Int(round(srgb.redComponent * 255)),
                      Int(round(srgb.greenComponent * 255)),
                      Int(round(srgb.blueComponent * 255)))
    }

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Resolves the icon to show for a `.file` item from its first captured path's
    /// extension. Multi-file drops store one path per line in `plainText`; only the
    /// first matters here since the file glyph is otherwise identical across the
    /// batch. Shared between `ItemCardView`'s card icon and `PreviewPane`'s larger one.
    static func fileType(for item: ClipItem) -> UTType {
        let ext = (item.plainText?.components(separatedBy: "\n").first as NSString?)?.pathExtension ?? ""
        return UTType(filenameExtension: ext) ?? .data
    }
}

/// 全 app 共用的动效参数。调整整体手感只改这里。
///
/// 规则: 过冲只给面板里面的元素 (卡片约 3%, 小元素约 8%), 面板本身不过冲 (会在屏幕底边
/// 露缝); 退场不过冲、比进场短、用加速曲线; 依次出现总长不超过 200ms; 大面积透明度
/// 变化不用起步很快的曲线 (会像闪一下); 只动位移/缩放/透明度。「减弱动态效果」开启时,
/// 各调用处退回纯淡入淡出。
enum Motion {
    /// 悬停、开关等即时反馈。
    static let quick = Animation.easeOut(duration: 0.12)
    /// 普通状态变化。
    static let standard = Animation.easeOut(duration: 0.22)
    /// 退场: 加速离开, 结尾不减速。
    static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.16)
    /// 卡片落位: 约 3% 过冲后回落。
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.75)
    /// 小元素 (键帽、角标、新卡片) 弹出: 约 8% 过冲。
    static let pop = Animation.spring(response: 0.26, dampingFraction: 0.65)
    /// 依次出现时相邻两个的间隔。
    static let stagger: Double = 0.015

    /// 打开面板时卡片依次从下方弹上来。觉得每次唤出都要等一下, 改成 false 即可。
    static let cardCascadeOnOpen = true
    /// 选中的卡片轻微放大。不想要改成 false 即可。
    static let liftSelectedCard = true
    /// 选中卡片放大的倍数。
    static let selectedCardScale: CGFloat = 1.02

    /// AppKit 侧 (面板窗口) 用的时长和曲线, 和上面的 SwiftUI 动画对应。
    enum Panel {
        /// 打开: 内容上升的时长, 曲线前段快、落点利落 (Material 3 emphasized decelerate)。
        static let openDuration: TimeInterval = 0.24
        static let openCurve = CAMediaTimingFunction(controlPoints: 0.05, 0.7, 0.1, 1)
        /// 打开: 面板透明度单独用普通减速, 免得一下子冒出来。
        static let fadeInDuration: TimeInterval = 0.2
        static let fadeInCurve = CAMediaTimingFunction(name: .easeOut)
        /// 关闭 (含拖出卡片时缩回): 加速下沉。
        static let closeDuration: TimeInterval = 0.16
        /// 回车粘贴时的关闭, 更短, 文字早点落到目标 app。
        static let pasteCloseDuration: TimeInterval = 0.12
        static let closeCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
    }

    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
