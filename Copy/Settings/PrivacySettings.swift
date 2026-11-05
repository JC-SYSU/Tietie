import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Excluded-apps management: Copy never captures clipboard content while one of these
/// apps is frontmost (enforced by `RulesEngine`, pushed by `SettingsStore.onRulesChange`).
struct PrivacySettings: View {
    @Bindable var settings: SettingsStore
    @State private var selectedBundleID: String?

    var body: some View {
        SettingsPane {
            SettingsRow(label: String(localized: "Screen Sharing:"),
                        help: String(localized: "Keeps your clipboard history out of screenshots, screen recordings and shared screens.")) {
                Toggle(String(localized: "Hide Copy windows during screen sharing"), isOn: $settings.hideDuringScreenSharing)
                    .toggleStyle(.checkbox)
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "Excluded Apps:"),
                        help: String(localized: "Copy records nothing while one of these apps is in front. Concealed content from password managers is never recorded.")) {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if settings.excludedBundleIDs.isEmpty {
                            // 文字放在列表顶部: 这一行按首行基线和左栏标签对齐,
                            // 文字居中会把「排除的 App：」拉到列表中间。
                            Text("No excluded apps")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        } else {
                            List(settings.excludedBundleIDs, id: \.self, selection: $selectedBundleID) { bundleID in
                                excludedAppRow(bundleID)
                            }
                            .listStyle(.bordered(alternatesRowBackgrounds: true))
                        }
                    }
                    .frame(width: SettingsLayout.helpWidth, height: 150)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

                    // 经典的 + / − 按钮条, 贴在列表下沿。
                    HStack(spacing: 0) {
                        Button { addExcludedApp() } label: {
                            Image(systemName: "plus").frame(width: 24, height: 20)
                        }
                        .accessibilityLabel(String(localized: "Add App"))
                        Divider().frame(height: 14)
                        Button { removeSelectedApp() } label: {
                            Image(systemName: "minus").frame(width: 24, height: 20)
                        }
                        .accessibilityLabel(String(localized: "Remove App"))
                        .disabled(selectedBundleID == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .frame(width: SettingsLayout.helpWidth)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .overlay(Rectangle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
                    .offset(y: -1)
                }
            }
        }
    }

    private func excludedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let icon = AppIconCache.icon(forBundleID: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(forBundleID: bundleID))
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        settings.addExcludedApp(bundleID: bundleID)
    }

    private func removeSelectedApp() {
        guard let selectedBundleID else { return }
        settings.removeExcludedApp(bundleID: selectedBundleID)
        self.selectedBundleID = nil
    }
}
