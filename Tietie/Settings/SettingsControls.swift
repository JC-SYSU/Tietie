import AppKit
import KeyboardShortcuts
import SwiftUI

// 设置窗口的自绘控件。外观规格照搬觅见：圆角 7、12/13pt 字、克莱因蓝选中态，
// 不出现系统默认的开关、滑块和下拉按钮外观。

// MARK: - 复选框

struct KleinCheckboxStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 11) {
                box(on: configuration.isOn)
                configuration.label
                    .font(.system(size: 13))
                    .foregroundStyle(scheme == .dark ? Color(nsColor: .labelColor) : SettingsTheme.bodyLight)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func box(on: Bool) -> some View {
        let onColor = scheme == .dark ? SettingsTheme.kleinDark : SettingsTheme.klein
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(on ? onColor : (scheme == .dark ? SettingsTheme.controlFillDark : SettingsTheme.controlFillLight))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(on ? onColor : (scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight),
                        lineWidth: 1)
            if on {
                Path { path in
                    path.move(to: CGPoint(x: 3.5, y: 8))
                    path.addLine(to: CGPoint(x: 7, y: 11))
                    path.addLine(to: CGPoint(x: 12.5, y: 5))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: SettingsTheme.checkboxSize, height: SettingsTheme.checkboxSize)
    }
}

// MARK: - 按钮

struct KleinButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let accent = scheme == .dark ? SettingsTheme.kleinDark : SettingsTheme.klein
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(prominent ? Color.white : (scheme == .dark ? Color(nsColor: .labelColor) : SettingsTheme.bodyLight))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                    .fill(prominent ? accent
                          : (scheme == .dark ? SettingsTheme.controlFillDark : SettingsTheme.controlFillLight))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                    .stroke(prominent ? accent
                            : (scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight),
                            lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous))
    }
}

/// 只有图标的方形按钮，用于加减、删除。
struct KleinIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(scheme == .dark ? Color(nsColor: .labelColor) : SettingsTheme.bodyLight)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                    .fill(scheme == .dark ? SettingsTheme.controlFillDark : SettingsTheme.controlFillLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                    .stroke(scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - 分段控件

struct KleinSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                KleinSegment(title: option.title, isSelected: selection == option.value) {
                    selection = option.value
                }
            }
        }
    }
}

private struct KleinSegment: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = scheme == .dark ? SettingsTheme.kleinDark : SettingsTheme.klein
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : (scheme == .dark ? Color(nsColor: .labelColor) : SettingsTheme.bodyLight))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                        .fill(isSelected ? accent
                              : (scheme == .dark ? SettingsTheme.controlFillDark : SettingsTheme.controlFillLight))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                        .stroke(isSelected ? accent
                                : (scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 下拉

struct KleinPopUp<Value: Hashable>: NSViewRepresentable {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13)
        button.addItems(withTitles: options.map { $0.title })
        if let index = options.firstIndex(where: { $0.value == selection }) {
            button.selectItem(at: index)
        }
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        guard let index = options.firstIndex(where: { $0.value == selection }) else { return }
        if button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    final class Coordinator: NSObject {
        var parent: KleinPopUp
        init(_ parent: KleinPopUp) { self.parent = parent }

        @objc func changed(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}

// MARK: - 滑块

struct KleinSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    @Environment(\.colorScheme) private var scheme

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knob: CGFloat = 14
            let usable = max(0, width - knob)
            let x = usable * fraction
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(scheme == .dark ? 0.18 : 0.10))
                    .frame(height: 3)
                Capsule(style: .continuous)
                    .fill(scheme == .dark ? SettingsTheme.kleinDark : SettingsTheme.klein)
                    .frame(width: x + knob / 2, height: 3)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = usable > 0 ? min(1, max(0, gesture.location.x / usable)) : 0
                        var newValue = range.lowerBound + Double(ratio) * (range.upperBound - range.lowerBound)
                        if step > 0 {
                            newValue = (newValue / step).rounded() * step
                        }
                        value = min(range.upperBound, max(range.lowerBound, newValue))
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - 步进器

struct KleinStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { if value > range.lowerBound { value -= 1 } }
            Rectangle()
                .fill(scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight)
                .frame(width: 1, height: 16)
            stepButton("plus") { if value < range.upperBound { value += 1 } }
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                .fill(scheme == .dark ? SettingsTheme.controlFillDark : SettingsTheme.controlFillLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                .stroke(scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight, lineWidth: 1)
        )
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 文本框

struct KleinTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var scheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12))
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(scheme == .dark ? SettingsTheme.controlFillDark : Color.white.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight, lineWidth: 1)
            )
    }
}

// MARK: - 快捷键录制

/// 自绘的快捷键录制按钮，替代 KeyboardShortcuts 自带的系统外观 Recorder。
struct KleinShortcutRecorder: View {
    let name: KeyboardShortcuts.Name
    var onChange: (() -> Void)? = nil

    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var recording = false
    @State private var monitor: Any?
    @Environment(\.colorScheme) private var scheme

    private var title: String {
        if recording { return String(localized: "Press keys…") }
        if let shortcut { return shortcut.description }
        return String(localized: "Set Shortcut")
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(minWidth: 96)
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                            .fill(recording
                                  ? (scheme == .dark ? SettingsTheme.kleinDark.opacity(0.25) : SettingsTheme.klein.opacity(0.12))
                                  : (scheme == .dark ? SettingsTheme.controlFillDark : SettingsTheme.controlFillLight))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsTheme.controlCorner, style: .continuous)
                            .stroke(recording
                                    ? (scheme == .dark ? SettingsTheme.kleinDark : SettingsTheme.klein)
                                    : (scheme == .dark ? SettingsTheme.controlBorderDark : SettingsTheme.controlBorderLight),
                                    lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if shortcut != nil && !recording {
                Button {
                    KeyboardShortcuts.setShortcut(nil, for: name)
                    shortcut = nil
                    onChange?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear"))
            }
        }
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                KeyboardShortcuts.setShortcut(nil, for: name)
                shortcut = nil
                stop()
                onChange?()
                return nil
            }
            guard let candidate = KeyboardShortcuts.Shortcut(event: event) else { return event }
            KeyboardShortcuts.setShortcut(candidate, for: name)
            shortcut = candidate
            stop()
            onChange?()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

// MARK: - 品牌展示

/// 通用页顶部的品牌区：左边图标，右边名称与来源说明。
struct SettingsBrandView: View {
    var body: some View {
        HStack(spacing: 18) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 5) {
                Text("Tietie")
                    .font(.system(size: 28, weight: .bold))
                Text("Forked from Copy")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }
}

// MARK: - 页头

struct SettingsPageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
