import CoreGraphics

/// 每页卡片数与总页数的纯计算。
///
/// 之所以独立成无状态函数: 这两个值以前缓存进视图模型, 靠「系统通知 → 面板改帧 →
/// SwiftUI 几何回调 → 重算」四段链路更新。任一环静默, 缓存就停在旧值, 只有重启
/// 重建视图树才自愈 (切换显示器后卡片数不刷新, 用户报告)。现在每次布局直接用当前
/// 宽度算, 不存在可失效的缓存。
public enum PageCapacity {
    /// 一行里能放下几张卡片。入参都是布局实测值, 不读取任何全局状态。
    /// - Parameters:
    ///   - viewportWidth: 卡片行可用宽度 (面板宽度)。
    ///   - cardWidth: 单卡宽度。
    ///   - gap: 卡片间距。
    ///   - padding: 行两侧内边距 (单侧)。
    ///   - dividerReserve: 收藏分隔线额外占用的宽度 (无分隔线传 0)。
    public static func count(viewportWidth: CGFloat,
                             cardWidth: CGFloat,
                             gap: CGFloat,
                             padding: CGFloat,
                             dividerReserve: CGFloat = 0) -> Int {
        guard viewportWidth > 0, cardWidth > 0 else { return 1 }
        let available = viewportWidth - 2 * padding - dividerReserve
        return max(1, Int((available + gap) / (cardWidth + gap)))
    }

    /// 总页数 (至少 1 页)。
    public static func pageCount(itemCount: Int, capacity: Int) -> Int {
        let capacity = max(1, capacity)
        return max(1, (max(0, itemCount) + capacity - 1) / capacity)
    }

    /// 页码上限 (0 基), 用于越界收敛。
    public static func maxPageIndex(itemCount: Int, capacity: Int) -> Int {
        max(0, pageCount(itemCount: itemCount, capacity: capacity) - 1)
    }
}
