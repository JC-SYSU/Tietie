import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Hotkey recorders and the Launch at Login toggle. Launch at Login isn't part of
/// `SettingsStore` (it's not a UserDefaults value, it's the `SMAppService` login-item
/// registration), so this view owns its own local state and re-reads the service's
/// actual status after every attempted change rather than trusting the toggle's intent.
struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginNeedsApproval = false
    @State private var launchAtLoginError: String?
    /// Mirrors whether `.toggleShelf` currently has a shortcut, for this view's own
    /// disabled/footer state. Tracked in `@State` (updated by the recorder's `onChange`
    /// below and refreshed `onAppear`) rather than read fresh on every body evaluation,
    /// since nothing else in this view is `@Observable`-tracked to that shortcut —
    /// without this, clearing the hotkey wouldn't visibly re-enable/disable anything
    /// here until some unrelated state change happened to force a redraw.
    @State private var shelfHotkeySet = true

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Language"), selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.title).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(String(localized: "Restart Copy for language changes to take effect."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "Candidate Limit"), selection: $settings.candidateLimit) {
                    Text("10").tag(10)
                    Text("25").tag(25)
                    Text("50").tag(50)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(String(localized: "Maximum number of items shown in the shelf at once."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "Remove Trailing Line Breaks"), selection: $settings.trailingNewlineScope) {
                    ForEach(TrailingNewlineScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(String(localized: "Line breaks at the end of copied text are always removed from Copy's history and from anything pasted from Copy. \"Also System Clipboard\" rewrites the clipboard right after you copy, so a plain ⌘V is clean too; the source app may then paste its own content with less formatting."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Enable Favorites"), isOn: $settings.favoritesEnabled)
            } footer: {
                Text("Show favorite actions and keep favorites at the front of history. Turning this off preserves saved favorites and their protection from automatic cleanup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "Appearance"), selection: $settings.shelfTheme) {
                    ForEach(ShelfTheme.allCases) { theme in Text(theme.title).tag(theme) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applies to the shelf, Paste Stack and Settings. Follow System uses your macOS appearance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Copy Sound")
                    Spacer()
                    Picker(String(localized: "Copy Sound"), selection: $settings.copySound) {
                        ForEach(CopySound.allCases) { sound in
                            Text(sound.title).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .onChange(of: settings.copySound) { _, sound in
                    CopySoundPlayer.shared.play(sound)
                }
            } footer: {
                Text("Plays after Copy captures a new clipboard item.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Haptic Feedback"), isOn: $settings.hapticFeedback)
            } footer: {
                Text("A light tap on the trackpad when you switch tabs, file a card on a pinboard, or paste.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Launch at Login"), isOn: launchAtLoginBinding)
            } footer: {
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if launchAtLoginNeedsApproval {
                    Text("Waiting for approval in System Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                // Only blocks turning the toggle ON without a hotkey — never blocks
                // turning it OFF, so a user who's already stranded (hotkey cleared
                // while this was on) can always self-rescue by flipping it back off.
                // AppDelegate's guard is still the authoritative check either way.
                Toggle(String(localized: "Hide the Menu Bar Icon"), isOn: $settings.hideMenuBarIcon)
                    .disabled(!shelfHotkeySet && !settings.hideMenuBarIcon)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !shelfHotkeySet {
                        Text("Set the Open Copy shortcut above before hiding the menu bar icon.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Copy stays available with the Option Command V shortcut. You can reach Settings and everything else from the shelf.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshLaunchAtLoginStatus()
            shelfHotkeySet = KeyboardShortcuts.getShortcut(for: .toggleShelf) != nil
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    /// A toggle that reads back purely from `.status == .enabled` leaves the user with
    /// no explanation when macOS accepts `register()` but parks the login item pending
    /// approval in System Settings: the switch would just look off again with no clue
    /// why. `.requiresApproval` counts as "on" here (registration did succeed) with a
    /// footnote distinguishing that state from a plain, unregistered off.
    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Couldn't update Launch at Login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }
}
