import SwiftUI

/// 「面板」页: 外观（材质/着色/字号/亮度）/ 行为（记忆收藏夹/记忆筛选/共享屏幕时隐藏）。
struct PanelSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsPane {
            // ── 外观 ──────────────────────────────────────────────────
            SettingsRow(label: String(localized: "Material:"),
                        help: String(localized: "Liquid Glass needs macOS 26. With Reduce Transparency on, the panel always uses HUD Window.")) {
                KleinPopUp(options: PanelMaterial.allCases.map { ($0, $0.title) },
                           selection: $settings.panelMaterial)
                    .frame(width: 300)
            }

            SettingsRow(label: String(localized: "Tint:"),
                        help: String(localized: "Liquid Glass is tinted in the material itself, so refraction and highlights stay; HUD Window, Sidebar and Window Background get a color layer on top. 0 turns it off.")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ColorPicker("", selection: tintColorBinding, supportsOpacity: false).labelsHidden()
                        Text(verbatim: "#" + settings.panelTintHex)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    labeledSlider(value: $settings.panelTintOpacity, range: 0...1, step: 0.1,
                                  text: String(format: "%.1f", settings.panelTintOpacity))
                }
                .disabled(!settings.panelMaterial.supportsTint)
            }

            SettingsRow(label: String(localized: "Text Size:"),
                        help: String(localized: "Tabs, the shortcut legend and the page number on the panel. The panel grows a little for larger sizes.")) {
                labeledSlider(value: $settings.panelFontSize, range: 10...15, step: 1,
                              text: String(format: "%.0f pt", settings.panelFontSize))
            }

            SettingsRow(label: String(localized: "Card Brightness:"),
                        help: String(localized: "Above 1.0, cards use the display's HDR range and get brighter than normal white, so they stand out from the glass. Needs macOS 26 and an HDR display; uses a little more power.")) {
                labeledSlider(value: $settings.cardBrightness, range: 1...2, step: 0.1,
                              text: String(format: "%.1f×", settings.cardBrightness))
            }

            SettingsDivider()

            // ── 行为 ──────────────────────────────────────────────────
            SettingsRow(label: String(localized: "Screen Sharing:"),
                        help: String(localized: "Keeps your clipboard history out of screenshots, screen recordings and shared screens.")) {
                Toggle(String(localized: "Hide Tietie windows during screen sharing"), isOn: $settings.hideDuringScreenSharing)
            }

            SettingsRow(label: String(localized: "Remember Tab:"),
                        help: String(localized: "Keep the current pinboard tab when the panel is dismissed and reopened.")) {
                Toggle(String(localized: "Remember the active pinboard"), isOn: $settings.rememberTab)
            }

            SettingsRow(label: String(localized: "Remember Filter:"),
                        help: String(localized: "Keep the search filters (tokens) across open/close. Any unfinished text being typed is cleared either way.")) {
                Toggle(String(localized: "Remember the search filters"), isOn: $settings.rememberFilter)
            }
        }
    }

    private func labeledSlider(value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        HStack(spacing: 10) {
            KleinSlider(value: value, range: range, step: step).frame(width: 220)
            Text(verbatim: text)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
    }

    private var tintColorBinding: Binding<Color> {
        Binding(
            get: { Tokens.color(fromHex: settings.panelTintHex) },
            set: { settings.panelTintHex = String(Tokens.hex(from: $0).dropFirst()) })
    }
}
