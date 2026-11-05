import SwiftUI

/// 设置窗口的统一排版: 经典 macOS 偏好设置的两栏格式。左栏是右对齐的标签 (带冒号),
/// 右栏是控件, 控件下面可以跟一行灰色说明。各页面只用这里的几个组件拼, 不各自写间距。
enum SettingsLayout {
    /// 整个设置窗口内容区的宽度, 各页面相同, 切换标签时窗口只变高度。
    static let paneWidth: CGFloat = 620
    /// 左栏标签宽度。中文最长「以纯文本粘贴最新：」约 115pt; 英文最长
    /// "Paste Latest as Plain Text:" 约 165pt, 比这里宽, 英文界面下这一个标签会折行。
    static let labelWidth: CGFloat = 150
    static let rowSpacing: CGFloat = 14
    static let columnSpacing: CGFloat = 12
    /// 右栏说明文字的最大宽度, 超过就换行。
    static let helpWidth: CGFloat = 360
}

/// 一页设置的外框: 统一的内边距和行距, 固定宽度。
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(width: SettingsLayout.paneWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 一行设置: 左栏标签 (可以为空, 用于同一组的后续控件), 右栏控件 + 可选说明。
struct SettingsRow<Control: View>: View {
    var label: String = ""
    var help: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.columnSpacing) {
            Text(label)
                .frame(width: SettingsLayout.labelWidth, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            VStack(alignment: .leading, spacing: 5) {
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

/// 两组设置之间的分隔线, 左右缩进与内容对齐。
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}
