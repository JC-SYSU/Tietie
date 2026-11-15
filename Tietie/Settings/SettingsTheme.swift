import SwiftUI

/// 设置窗口的视觉常量。数值取自觅见的设置界面，主题色换成克莱因蓝。
enum SettingsTheme {
    /// 克莱因蓝 #002FA7。
    static let klein = Color(red: 0, green: 47 / 255, blue: 167 / 255)
    /// 克莱因蓝在深色外观下提亮一档，保持对比度。
    static let kleinDark = Color(red: 0.36, green: 0.50, blue: 0.90)

    /// 浅色画布：觅见的暖白。
    static let canvasLight = Color(red: 0.957, green: 0.957, blue: 0.945)
    static let canvasDark = Color(nsColor: .windowBackgroundColor)

    /// 侧边栏选中底色。
    static let sidebarSelectedLight = Color(red: 0.87, green: 0.90, blue: 0.96)
    static let sidebarSelectedDark = Color(red: 0.10, green: 0.16, blue: 0.30)

    /// 未选中控件底色与描边。
    static let controlFillLight = Color.white.opacity(0.60)
    static let controlFillDark = Color.white.opacity(0.07)
    static let controlBorderLight = Color(red: 211 / 255, green: 216 / 255, blue: 220 / 255)
    static let controlBorderDark = Color.white.opacity(0.18)

    /// 正文 / 次要文字。
    static let bodyLight = Color(red: 66 / 255, green: 75 / 255, blue: 85 / 255)

    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 700
    static let sidebarWidth: CGFloat = 150
    static let contentWidth: CGFloat = 712
    static let sidebarItemWidth: CGFloat = 136
    static let sidebarItemHeight: CGFloat = 42
    static let sidebarItemSpacing: CGFloat = 4
    static let sidebarInset: CGFloat = 16
    static let labelColumn: CGFloat = 150
    static let controlCorner: CGFloat = 7
    static let checkboxSize: CGFloat = 16
}

extension View {
    @ViewBuilder
    func settingsCanvas() -> some View {
        self.background(
            SettingsCanvasBackground()
                .ignoresSafeArea()
        )
    }
}

private struct SettingsCanvasBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        (scheme == .dark ? SettingsTheme.canvasDark : SettingsTheme.canvasLight)
    }
}
