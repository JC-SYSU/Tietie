import KeyboardShortcuts
import SwiftUI

/// 「快捷键」页：打开面板、粘贴栈、下一个钉板、快速粘贴与面板内按键说明。
struct ShortcutsSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsPane {
            SettingsRow(label: String(localized: "Open Tietie:")) {
                KleinShortcutRecorder(name: .toggleShelf) {
                    settings.onShelfHotkeyChange?()
                }
            }
            SettingsRow(label: String(localized: "Paste Stack:")) {
                KleinShortcutRecorder(name: .togglePasteStack)
            }
            SettingsRow(label: String(localized: "Next Pinboard:")) {
                KleinShortcutRecorder(name: .nextPinboard)
            }
            SettingsRow(label: String(localized: "Quick Paste Latest:"),
                        help: String(localized: "Pastes your most recent item into the current app without opening Tietie.")) {
                KleinShortcutRecorder(name: .quickPasteLatest)
            }
            SettingsRow(label: String(localized: "Paste Latest as Plain Text:"),
                        help: String(localized: "Same, without any formatting.")) {
                KleinShortcutRecorder(name: .pasteLatestPlainText)
            }

            SettingsDivider()

            SettingsRow(label: String(localized: "In the Shelf:")) {
                VStack(alignment: .leading, spacing: 6) {
                    ShortcutHintLine(keys: "⌥1–9", text: String(localized: "Switch to a tab"))
                    ShortcutHintLine(keys: "⌘1–9", text: String(localized: "Paste that card"))
                    ShortcutHintLine(keys: "⌘F",   text: String(localized: "Search"))
                    ShortcutHintLine(keys: "⇧↩",   text: String(localized: "Paste as plain text"))
                }
            }
        }
    }
}

// ── 面板内快捷键说明行 ─────────────────────────────────────────────────────
private struct ShortcutHintLine: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            KeyCap(text: keys).frame(minWidth: 52, alignment: .leading)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
