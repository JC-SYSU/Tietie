# Tietie

**Tietie is a free, open-source clipboard manager for macOS.** Press <kbd>⇧⌘V</kbd> and a shelf of cards rises from the bottom of the screen showing everything you have copied, ready to search, pin, edit, and paste back. Everything stays on your Mac: no account, no cloud sync, no telemetry.

Tietie is a fork of [Copy](https://github.com/tarikbc/Copy). The code is GPL-3.0; the name, icon and branding have been replaced, and this project is not affiliated with or supported by the original author.

<p align="center">
  <b><a href="https://github.com/JC-SYSU/Tietie/releases/latest">Download</a> &nbsp;·&nbsp; <a href="#install">Install</a> &nbsp;·&nbsp; <a href="#keyboard-shortcuts">Shortcuts</a></b>
</p>

## Coming from Copy

On first launch, Tietie copies `~/Library/Application Support/Copy/` and `~/Library/Copy/Images/` into `~/Library/Application Support/Tietie/` and `~/Library/Tietie/Images/`, and migrates the old preferences. The original directories are left in place so you can clean them up yourself once the new version is working.

Tietie uses a different bundle identifier and storage directory from upstream Copy, so both apps can be installed at the same time without writing into each other's database.

## Features

**The shelf**
- Summon with <kbd>⇧⌘V</kbd> from any app; every copy becomes a card, instantly searchable
- Unlimited history with full-text search and scope chips (All / Text / Images / Links / Files)
- On-device OCR makes text inside images searchable, with the match highlighted in results
- Space bar previews a card before you commit, Quick Look for files
- Drag any card out of the shelf, or select several and drag them out together
- Liquid Glass on macOS 26, with a solid, legible fallback (and Reduce Transparency support)
- Follow the system appearance, or keep the shelf light or dark; attach it to the screen edge or let it float
- Haptic feedback on the trackpad when you switch tabs, file a card, paste, and more (optional)

**Organizing**
- Pinboards with colors and any emoji; drag a card onto a tab to keep it, switch with <kbd>⌘1</kbd>–<kbd>⌘9</kbd>
- A callout names the board a dragged card will land in; reorder pinboards by dragging their tabs
- Favorites keep starred cards at the front of the shelf, and can be switched off entirely
- Search scoped to the active pinboard, or your whole history
- Click a card's title to rename it in place; multi-select for bulk actions
- Drawer-first: reach Settings and every action from inside the shelf, and optionally hide the menu bar icon entirely

**Editing and power tools**
- A real rich text editor: bold, italic, underline, strikethrough, with a live character / word / line count
- Copied source code is detected and syntax-highlighted right on the card, like Xcode
- Copy a hex color like `#4C9DFF` and the card shows the actual color
- Rotate copied images; adjust and re-copy colors
- Apple Writing Tools in the editor

**Pasting**
- <kbd>⏎</kbd> pastes the selected card; <kbd>⌥⏎</kbd> strips formatting and pastes plain text
- Two-click-to-paste by default (single click selects, double click pastes), or switch to single-click
- Paste stack: queue several cards and walk through them on successive <kbd>⌘V</kbd> presses, shown as a numbered queue with the next item marked
- <kbd>⌘O</kbd> opens the selected link or file without pasting; <kbd>⌘Z</kbd> undoes a delete
- App Intents so Shortcuts can paste your latest item, search, or paste from a pinboard

**Private by design**
- Everything stays on your Mac. No account, no cloud sync, no telemetry
- Respects the system concealed-type marker, so password managers are never recorded
- Per-app exclusions, plus hide the shelf from screen recordings and shares
- Configurable history retention; export and import your history as a single archive

## Install

Download the latest DMG from [Releases](https://github.com/JC-SYSU/Tietie/releases/latest), open it, and drag Tietie to Applications. Requires **macOS 26 or later**.

This build is ad-hoc signed and not notarized by Apple, so Gatekeeper warns on first launch. Right-click the app and choose **Open**, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Tietie.app
```

On first launch, Tietie asks for Accessibility access (to paste for you) and, on macOS 26, pasteboard access. Summon it any time with <kbd>⇧⌘V</kbd>.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| <kbd>⇧⌘V</kbd> | Open the shelf |
| <kbd>←</kbd> / <kbd>→</kbd> | Move selection |
| <kbd>⌘C</kbd> | Copy the selection to the clipboard |
| <kbd>⌘V</kbd> | Paste the selection |
| <kbd>⏎</kbd> | Paste selected card |
| <kbd>⌥⏎</kbd> | Paste as plain text |
| <kbd>Space</kbd> | Preview selected card |
| <kbd>1</kbd>–<kbd>9</kbd> | Quick-paste the Nth card |
| <kbd>⌘1</kbd>–<kbd>⌘9</kbd> | Switch to history / pinboard tab |
| <kbd>⌘E</kbd> | Edit selected card |
| <kbd>⌘R</kbd> | Rename selected card |
| <kbd>⌘O</kbd> | Open selected link or file |
| <kbd>⌘Z</kbd> | Undo the last delete |
| <kbd>⌫</kbd> | Delete selected card (when the search box is empty) |
| <kbd>⌘⌫</kbd> | Clear the search, or delete the selected card |
| <kbd>⌘N</kbd> | New item |
| <kbd>⇧⌘C</kbd> | Toggle the paste stack |

## Build from source

Requirements: macOS 26+, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Tietie.xcodeproj -scheme Tietie -configuration Debug build
```

Core engine tests:

```sh
swift test --package-path TietieCore
```

The app is a thin SwiftUI + AppKit shell over **TietieCore**, a local Swift package (GRDB / SQLite + FTS5) that holds the clipboard engine, storage, and all the logic covered by the test suite. UI lives in the app target; behavior lives in TietieCore.

### Release builds

```sh
./Scripts/package-release.sh
```

This builds a Release `Tietie.app` with ad-hoc signing and writes `build/release/Tietie-<version>.dmg`.

Tietie does not ship Sparkle updates. The upstream appcast and EdDSA key have been removed, so the app never checks for updates.

## Privacy

Tietie is local-only, with one exception: link previews fetch the page title and favicon for copied links directly from the web. This is on by default and can be turned off in Settings under History. Aside from that, Tietie makes no network calls, has no analytics or crash reporting, and your clipboard history never leaves your Mac. Any app that marks its pasteboard content as concealed, such as a password manager, is skipped entirely, and you can add per-app exclusions for anything else you would rather Tietie ignore.

## Contributing

Tietie is a fork of Copy. The design and most of the code come from [Tarik Caramanico](https://github.com/tarikbc). Tietie's own changes, issues and releases live in this repository:

- 🐛 [Open an issue](https://github.com/JC-SYSU/Tietie/issues) for a bug or a feature idea
- 🔧 Send a pull request. The core engine lives in `TietieCore` and has its own test suite (`swift test --package-path TietieCore`); please add or update tests for any engine change

The upstream commit sign-off rule still applies: commits need a `Signed-off-by` trailer, which `git commit -s` adds for you.

## License

[GPL-3.0](LICENSE). © 2026 Tarik Caramanico; fork changes © 2026 JC-SYSU.

This is a modified version of Copy. The original copyright notice, [NOTICE](NOTICE) and the GPL-3.0 grant are preserved. [TRADEMARK.md](TRADEMARK.md) records the upstream trademark policy: the code is free to fork, the upstream name and artwork are not. Tietie ships under its own name, icon, bundle identifier and storage location.
