import CopyCore
import SwiftUI

/// 「历史」页: 保留多久、占用多少空间、清空。保留时长存在 `SettingsStore`, 存储统计和
/// 清空走 `store`。
struct HistorySettings: View {
    @Bindable var settings: SettingsStore
    let store: ItemStore

    var body: some View {
        SettingsPane {
            SettingsRow(label: String(localized: "Keep History:"), help: retentionHelp) {
                StepSlider(labels: RetentionPeriod.sliderOrder.map(\.title), index: retentionIndex)
                    .frame(width: SettingsLayout.helpWidth)
                    // 让左栏标签和滑轨 (StepSlider 内 y=34) 对齐, 默认会落到滑块底部。
                    .alignmentGuide(.firstTextBaseline) { _ in 38 }
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "Storage:")) {
                StorageUsageSection(store: store)
                    .frame(width: SettingsLayout.helpWidth)
            }
        }
    }

    /// Bridges the `StepSlider`'s `Int` position to the stored `RetentionPeriod`, using the
    /// shortest-to-longest `sliderOrder`. Falls back to the last stop (Unlimited) if the
    /// stored value somehow isn't in the order.
    private var retentionIndex: Binding<Int> {
        let order = RetentionPeriod.sliderOrder
        return Binding(
            get: { order.firstIndex(of: settings.retention) ?? order.count - 1 },
            set: { settings.retention = order[$0] }
        )
    }

    private var retentionHelp: String {
        if settings.retention == .unlimited {
            return String(localized: "Nothing is removed by age. Favorites and pinboard items are always kept.")
        }
        return String(format: String(localized: "Items unused for %@ are removed. Favorites and pinboard items are always kept."),
                      settings.retention.title)
    }
}
