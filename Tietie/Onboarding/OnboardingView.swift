import AppKit
import ApplicationServices
import Combine
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Paged first-run flow, shown once by `AppCoordinator.showOnboarding()` and gated on
/// the `"hasOnboarded"` UserDefaults flag (set in `finish()`). Steps are computed once
/// at init rather than as a fixed `CaseIterable` list because the clipboard-access page
/// only makes sense on macOS versions where `NSPasteboard.accessBehavior` exists.
struct OnboardingView: View {
    private enum Step: Equatable {
        case welcome
        case accessibility
        case clipboardAccess
        case hotkey
        case done
    }

    let onFinish: () -> Void

    private let steps: [Step]
    @State private var stepIndex = 0
    /// Drives the direction of the step transition so advancing slides left and going
    /// back slides right, matching the shelf's own directional motion.
    @State private var goingForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        var steps: [Step] = [.welcome, .accessibility]
        if Self.supportsClipboardAccessPrivacy {
            steps.append(.clipboardAccess)
        }
        steps.append(contentsOf: [.hotkey, .done])
        self.steps = steps
    }

    /// `NSPasteboard.accessBehavior` is only declared `API_AVAILABLE(macos(15.4))`; on
    /// older systems the clipboard-access step would have nothing to explain or show,
    /// so it's dropped from `steps` entirely rather than shown in some degraded form.
    private static var supportsClipboardAccessPrivacy: Bool {
        if #available(macOS 15.4, *) {
            return true
        }
        return false
    }

    private var currentStep: Step { steps[stepIndex] }
    private var isFirstStep: Bool { stepIndex == 0 }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    private var continueTitle: String {
        if isLastStep { return "Finish" }
        if currentStep == .welcome { return "Get Started" }
        return "Continue"
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(stepIndex)
                .transition(stepTransition)

            VStack(spacing: 16) {
                ProgressDots(count: steps.count, current: stepIndex)
                HStack {
                    if !isFirstStep {
                        Button("Back") {
                            goingForward = false
                            withAnimation(.easeOut(duration: 0.22)) { stepIndex -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(continueTitle) { advance() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .welcome:
            WelcomeStep()
        case .accessibility:
            AccessibilityStep()
        case .clipboardAccess:
            ClipboardAccessStep()
        case .hotkey:
            HotkeyStep()
        case .done:
            DoneStep()
        }
    }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            goingForward = true
            withAnimation(.easeOut(duration: 0.22)) { stepIndex += 1 }
        }
    }

    /// A directional slide (advance left, back right), degrading to a plain crossfade
    /// under Reduce Motion.
    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity))
    }

    /// The last step's Finish action: records that onboarding is done so it never shows
    /// again, best-effort enables Launch at Login (mirrors `GeneralSettings`'s toggle,
    /// but a failure here shouldn't block finishing onboarding), then hands off to the
    /// window controller's `onFinish` to actually hide the window.
    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        try? SMAppService.mainApp.register()
        onFinish()
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StepHeading: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Welcome to Tietie")
                .font(.title2.weight(.semibold))
            Text("A visual shelf for everything you copy.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("Press ⌥⌘V anytime to open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AccessibilityStep: View {
    @State private var isTrusted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            // 标题不写「辅助功能」: 27.0–27.2 该面板叫「设备控制与数据访问」,
            // 用户按标题里的名字去系统设置里找会落空。
            StepHeading(symbol: "accessibility", title: "Paste Permission")
            Text(
                String(
                    format: String(localized: "Tietie pastes into the app you are using. Allow it under Privacy & Security > %@."),
                    PermissionGuide.accessibilityPaneTitle
                )
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Open Accessibility Settings") { requestAccess() }
                .buttonStyle(.bordered)
            StatusRow(isGranted: isTrusted, grantedText: "Access granted", pendingText: "Not granted yet")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isTrusted = AXIsProcessTrusted() }
        .onReceive(timer) { _ in isTrusted = AXIsProcessTrusted() }
    }

    private func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        PermissionGuide.openAccessibilitySettings()
    }
}

private struct ClipboardAccessStep: View {
    @State private var behavior = NSPasteboard.general.accessBehavior
    /// 点过「请求权限」但系统没弹窗: 剪贴板是空的, 没有内容可读就不会触发提示。
    @State private var nothingToRead = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            StepHeading(symbol: "clipboard", title: "Clipboard Access")
            Text("Tietie reads the clipboard in the background to save your history. macOS asks once, then you can pin the answer in System Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // 先有鸡还是先有蛋: 触发过第一次系统提示之前, 贴贴不会出现在那个列表里
            // (NSPasteboard.AccessBehavior 文档: 状态保持 .default, 应用不显示)。
            // 所以先引导触发一次读取, 再让人去设置里固定「始终允许」。
            if needsSetup {
                Text("Tietie only shows up in that list after it has asked once, so request access first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Request Clipboard Access") { requestAccess() }
                    .buttonStyle(.borderedProminent)
                if nothingToRead {
                    Text("The clipboard is empty. Copy any text, then request access again.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            } else if behavior != .default {
                Button("Open Privacy Settings") { PermissionGuide.openPasteboardSettings() }
                    .buttonStyle(.bordered)
            }

            statusRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshStatus() }
        .onReceive(timer) { _ in refreshStatus() }
    }

    /// 27 起 `.default` 表示还没触发过系统提示，贴贴也还没进列表。
    private var needsSetup: Bool {
        behavior == .default && PermissionGuide.pasteboardPrivacyIsEnforced
    }

    @ViewBuilder
    private var statusRow: some View {
        let (symbol, tint, text): (String, Color, LocalizedStringKey) = {
            switch behavior {
            case .alwaysAllow:
                return ("checkmark.circle.fill", .green, "Access granted")
            case .ask:
                return ("exclamationmark.circle", .secondary, "Listed in System Settings · set Tietie to Always Allow")
            case .alwaysDeny:
                return ("xmark.circle", .orange, "Denied by System Settings")
            default:
                // 26 及更早默认不强制剪贴板权限，`.default` 在这里是「没有这道限制」。
                return PermissionGuide.pasteboardPrivacyIsEnforced
                    ? ("circle", .secondary, "Not requested yet")
                    : ("checkmark.circle", .secondary, "No permission needed on this version of macOS")
            }
        }()

        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func refreshStatus() {
        behavior = NSPasteboard.general.accessBehavior
    }

    /// 读一次剪贴板内容, 让系统弹出第一次访问提示。这个提示本身就是让贴贴进入
    /// 「从其他 App 粘贴」列表的触发条件; 空剪贴板没有内容可读, 系统不会提示。
    private func requestAccess() {
        nothingToRead = false
        _ = NSPasteboard.general.pasteboardItems
        // 提示是异步的, 稍等一下再读状态: 状态没离开 .default 就说明没弹窗。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            refreshStatus()
            nothingToRead = behavior == .default
        }
    }
}

private struct StatusRow: View {
    let isGranted: Bool
    let grantedText: LocalizedStringKey
    let pendingText: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)
            Text(isGranted ? grantedText : pendingText)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct HotkeyStep: View {
    var body: some View {
        VStack(spacing: 16) {
            StepHeading(symbol: "keyboard", title: "Hotkey")
            KeyboardShortcuts.Recorder("Open Tietie:", name: .toggleShelf)
            Text("You can change this anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.green)
            Text("You are all set.")
                .font(.title2.weight(.semibold))
            Text("Tietie lives in your menu bar, ready when you need it.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
