import TietieCore
import SwiftUI

/// 「历史」页: 保留与候选 / 存储用量。
struct HistorySettings: View {
    @Bindable var settings: SettingsStore
    let store: ItemStore

    var body: some View {
        SettingsPane {
            // ── 保留与候选 ─────────────────────────────────────────────
            SettingsRow(label: String(localized: "Keep History:"), help: retentionHelp) {
                StepSlider(labels: RetentionPeriod.sliderOrder.map(\.title), index: retentionIndex)
                    .frame(width: SettingsLayout.helpWidth)
                    .alignmentGuide(.firstTextBaseline) { _ in 38 }
            }

            SettingsRow(label: String(localized: "Show:"),
                        help: String(localized: "Maximum number of items shown in the shelf at once.")) {
                KleinSegmented(options: [10, 25, 50].map {
                    ($0, String(format: String(localized: "%d cards"), $0))
                }, selection: $settings.candidateLimit)
                    .frame(width: 300)
            }

            SettingsDivider()

            // ── 存储用量 ───────────────────────────────────────────────
            SettingsRow(label: String(localized: "Storage:")) {
                StorageUsageSection(store: store)
                    .frame(width: SettingsLayout.helpWidth)
            }
        }
    }

    private var retentionIndex: Binding<Int> {
        let order = RetentionPeriod.sliderOrder
        return Binding(
            get: { order.firstIndex(of: settings.retention) ?? order.count - 1 },
            set: { settings.retention = order[$0] })
    }

    private var retentionHelp: String {
        if settings.retention == .unlimited {
            return String(localized: "Nothing is removed by age. Favorites and pinboard items are always kept.")
        }
        return String(format: String(localized: "Items unused for %@ are removed. Favorites and pinboard items are always kept."),
                      settings.retention.title)
    }
}
