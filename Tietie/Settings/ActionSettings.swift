import SwiftUI

/// 「操作」页: 复制（音效/触感）/ 粘贴（末尾换行/⇧⌘V 来源）/ 卡片（编号/收藏/预览/OCR）。
struct ActionSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsPane {
            // ── 复制 ──────────────────────────────────────────────────
            SettingsRow(label: String(localized: "Copy Sound:"),
                        help: String(localized: "Plays after Tietie captures a new clipboard item.")) {
                KleinPopUp(options: CopySound.allCases.map { ($0, $0.title) },
                           selection: $settings.copySound)
                    .frame(width: 300)
                    .onChange(of: settings.copySound) { _, sound in CopySoundPlayer.shared.play(sound) }
            }

            SettingsRow(label: String(localized: "Haptics:"),
                        help: String(localized: "A light tap on the trackpad when you switch tabs, file a card on a pinboard, or paste.")) {
                Toggle(String(localized: "Haptic Feedback"), isOn: $settings.hapticFeedback)
            }

            SettingsDivider()

            // ── 粘贴 ──────────────────────────────────────────────────
            SettingsRow(label: String(localized: "Trailing Line Breaks:"),
                        help: String(localized: "Always removed from Tietie's history and from what Tietie pastes. \"Also System Clipboard\" cleans the clipboard right after you copy, so a plain ⌘V is clean too; the source app may then paste its own content with less formatting.")) {
                KleinPopUp(options: TrailingNewlineScope.allCases.map { ($0, $0.title) },
                           selection: $settings.trailingNewlineScope)
                    .frame(width: 300)
            }

            SettingsRow(label: String(localized: "⇧⌘V Source:"),
                        help: String(localized: "Off: ⇧⌘V always pastes the latest item from your full history. On: when a pinboard tab is active, ⇧⌘V pastes the latest item from that pinboard instead.")) {
                Toggle(String(localized: "Paste from the active pinboard"), isOn: $settings.pasteFromCurrentTab)
            }

            SettingsDivider()

            // ── 卡片 ──────────────────────────────────────────────────
            SettingsRow(label: String(localized: "⌘ Numbers:"),
                        help: String(localized: "How card numbers appear while you hold ⌘. Press ⌘ and a number to paste that card.")) {
                KleinSegmented(options: NumberHintStyle.allCases.map { ($0, $0.title) },
                               selection: $settings.numberHintStyle)
                    .frame(width: 320)
            }

            SettingsRow(label: String(localized: "Favorites:"),
                        help: String(localized: "Favorites stay at the front and are never cleaned up automatically. Turning this off keeps the ones you saved.")) {
                Toggle(String(localized: "Enable Favorites"), isOn: $settings.favoritesEnabled)
            }

            SettingsRow(label: String(localized: "Links:"),
                        help: String(localized: "Tietie loads titles and icons for copied links from the web.")) {
                Toggle(String(localized: "Fetch Link Previews"), isOn: $settings.fetchLinkPreviews)
            }

            SettingsRow(label: String(localized: "Images:"),
                        help: String(localized: "Makes text in copied images searchable. Runs entirely on your Mac.")) {
                Toggle(String(localized: "Recognize Text in Images"), isOn: $settings.recognizeImageText)
            }
        }
    }
}
