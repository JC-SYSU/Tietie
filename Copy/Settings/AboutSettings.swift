import AppKit
import SwiftUI

/// 「关于」页: 图标、名称、版本、项目链接, 居中排列。The Sparkle update UI is absent
/// from this local build (see the note in `AppDelegate`).
struct AboutSettings: View {
    @Bindable var settings: SettingsStore

    private static let repoURL = URL(string: "https://github.com/tarikbc/Copy")!
    private static let issuesURL = URL(string: "https://github.com/tarikbc/Copy/issues/new")!
    private static let licenseURL = URL(string: "https://github.com/tarikbc/Copy/blob/main/LICENSE")!

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Copy")
                .font(.system(size: 22, weight: .semibold))
            Text(versionString)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A visual shelf for your clipboard.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 16) {
                Button(String(localized: "View on GitHub")) { NSWorkspace.shared.open(Self.repoURL) }
                Button(String(localized: "Report an Issue")) { NSWorkspace.shared.open(Self.issuesURL) }
                Button(String(localized: "License (GPL-3.0)")) { NSWorkspace.shared.open(Self.licenseURL) }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .padding(.top, 14)

            Button(String(localized: "View Onboarding Again")) { settings.onShowOnboarding?() }
                .padding(.top, 10)

            Text("© 2026 Tarik Caramanico · GPL-3.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: SettingsLayout.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(format: String(localized: "Version %@ (%@)"), short, build)
    }
}
