import SwiftUI

/// A small keyboard-key chip (e.g. ⏎, Space, ⇧⌘V), shared by the shelf's first-run
/// empty-state hints and the dismissible keyboard legend along the shelf footer.
struct KeyCap: View {
    let text: String
    /// 面板里由 `.environment(\.panelFontSize, …)` 传入; 其他地方 (设置窗口、引导)
    /// 没有设, 用默认 11。
    @Environment(\.panelFontSize) private var panelFontSize

    var body: some View {
        Text(text)
            .font(.system(size: panelFontSize - 0.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
                    )
            )
            .accessibilityLabel(text)
    }
}

/// A key chip followed by a short label, for legends and first-run hints.
struct KeyHint: View {
    let key: String
    let label: String
    @Environment(\.panelFontSize) private var panelFontSize

    var body: some View {
        HStack(spacing: 5) {
            KeyCap(text: key)
            Text(label)
                .font(.system(size: panelFontSize))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(label)")
    }
}

/// 面板文字字号 (设置 → 面板, 10–15pt)。面板根视图注入; 未注入时 11pt。
private struct PanelFontSizeKey: EnvironmentKey {
    static let defaultValue: Double = 11
}

extension EnvironmentValues {
    var panelFontSize: Double {
        get { self[PanelFontSizeKey.self] }
        set { self[PanelFontSizeKey.self] = newValue }
    }
}
