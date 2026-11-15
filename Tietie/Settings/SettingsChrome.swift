import SwiftUI

/// 设置窗口的统一排版：左侧边栏 + 右侧内容区，内容区按觅见的列结构排布。
/// 左列标签固定 150pt，控件从该列之后开始，说明文字跟在控件下方。
enum SettingsLayout {
    /// 侧边栏宽度（含右侧 6pt 留白，按钮宽 136）。
    static let sidebarWidth: CGFloat = 158
    static let contentWidth: CGFloat = 712
    /// 分隔线到内容区左边缘的距离。
    static let contentLeading: CGFloat = 11
    static var windowWidth: CGFloat { sidebarWidth + 1 + contentLeading + contentWidth + 18 }
    /// 固定窗口高度；内容超出时 ScrollView 负责滚动。
    static let windowHeight: CGFloat = 700
    /// 每页视图的宽度。
    static let paneWidth: CGFloat = contentWidth
    /// 标签列宽度，控件从这一列之后开始。
    static let labelWidth: CGFloat = 150
    static let rowSpacing: CGFloat = 22
    static let columnSpacing: CGFloat = 0
    /// 说明文字的最大宽度。
    static let helpWidth: CGFloat = 534
    /// 页面内容的内边距。
    static let paneInset: CGFloat = 12
}

/// 一页设置的外框：统一的内边距和行距，固定宽度。
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
            content
        }
        .padding(.horizontal, SettingsLayout.paneInset)
        .padding(.top, 16)
        .padding(.bottom, 30)
        .frame(width: SettingsLayout.paneWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 一行设置：左列标签，右侧控件 + 可选说明。
struct SettingsRow<Control: View>: View {
    var label: String = ""
    var help: String? = nil
    @ViewBuilder let control: Control
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(scheme == .dark ? Color(nsColor: .labelColor) : SettingsTheme.bodyLight)
                .frame(width: SettingsLayout.labelWidth, alignment: .leading)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                control
                if let help {
                    SettingsHelp(help)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 控件下方的灰色说明文字。
struct SettingsHelp: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: SettingsLayout.helpWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 两组设置之间的分隔线，左右缩进与内容对齐。
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.vertical, 10)
    }
}

/// 分组小标题（12pt 粗体），用于把同一页里的控件分组。
struct SettingsGroupTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}
