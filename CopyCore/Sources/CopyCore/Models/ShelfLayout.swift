import Foundation

public enum ShelfLayout {
    /// - Parameter screenFrame: 整屏 frame (`NSScreen.frame`), 不是 `visibleFrame`。
    ///   面板设计上要盖住 Dock、紧贴屏幕最下缘: 窗口层级是 `.statusBar` (见
    ///   `KeyablePanel`), 故意越过 Dock。传 `visibleFrame` 会让面板缩到 Dock 上方。
    public static func frame(screenFrame: CGRect, height: CGFloat, floating: Bool) -> CGRect {
        let inset: CGFloat = floating ? 12 : 0
        return CGRect(x: screenFrame.minX + inset, y: screenFrame.minY + inset,
                      width: max(1, screenFrame.width - inset * 2), height: height)
    }
}
