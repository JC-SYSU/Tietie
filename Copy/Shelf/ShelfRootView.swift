import SwiftUI
import CopyCore
import AppKit
import KeyboardShortcuts
import UniformTypeIdentifiers

struct ShelfRootView: View {
    @Bindable var viewModel: ShelfViewModel
    @State private var permissionBannerDismissed = false
    /// Where the shelf's press-and-drag stands: a press on a card or tab is refused as a
    /// drag-select for the rest of that drag, since it drags that card or tab instead.
    @State private var sweepGesture = SweepGesture.idle

    private enum SweepGesture { case idle, sweeping, refused }
    /// Persisted so the keyboard legend, once dismissed, stays gone. Read once here;
    /// `dismissLegend()` writes it back. Defaults to shown (false) for new users.
    @State private var legendDismissed = UserDefaults.standard.bool(forKey: Self.legendDismissedKey)

    private static let legendDismissedKey = "shelfKeyboardLegendDismissed"

    /// The legend teaches the keyboard path, so it earns its slim strip when there are
    /// cards to act on and the shelf is at full height (compact mode trades this away for
    /// density). Holding ⌥ re-summons it even after it's been dismissed.
    private var showsLegend: Bool {
        guard !viewModel.items.isEmpty, !viewModel.settings.compactShelf else { return false }
        return !legendDismissed || viewModel.optionHeld
    }

    /// Reads `viewModel.accessibilityTrusted` rather than checking `AXIsProcessTrusted()`
    /// itself, since the shelf panel + this view are created once and reused for the
    /// app's lifetime — a one-time `.onAppear` read here would only ever reflect
    /// whatever was true the very first time the shelf ever appeared. `AppCoordinator`
    /// refreshes that state on every shelf open (see `ShelfViewModel.refreshPermissionState()`),
    /// so once access is granted, the next open simply stops showing the banner.
    private var showsPermissionBanner: Bool {
        !viewModel.accessibilityTrusted && !permissionBannerDismissed
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPermissionBanner {
                PermissionBanner(onDismiss: { permissionBannerDismissed = true })
            }
            ShelfHeader(viewModel: viewModel)
                // Above the cards so the search suggestions dropdown floats over them.
                .zIndex(1)
            Divider()
            ShelfItemsRow(viewModel: viewModel)
            if showsLegend {
                KeyboardLegend(pageIndex: viewModel.pageIndex, pageCount: viewModel.pageCount)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Hit-test floor for the whole panel: the glass surface below isn't scroll-
        // routeable, so without this a scroll starting on any dead pixel (header gaps,
        // legend strip, padding) fell through to the window behind the shelf.
        .background(Color.black.opacity(0.001).ignoresSafeArea())
        .glassSurface(corners: GlassSurfaceCorners())
        // 外阴影: 面板在屏幕底部, 往上投影匹配光源从上而来的视觉逻辑。在容器视图
        // 层面施加(而不是在 glassSurface 内部对玻璃材质施加), 避免触发离屏层变黑。
        .shadow(color: Color.black.opacity(0.5), radius: 25, y: -8)
        // Drags onto the pinboard tabs (cards to file, tabs to reorder) are taken by the
        // hosting view in AppKit, not by a SwiftUI `.onDrop` (see `ShelfHostingView`). It
        // maps the pointer to a tab using each tab's frame, collected via
        // PinboardTabFramesKey below.
        .coordinateSpace(name: "shelfRoot")
        .onPreferenceChange(PinboardTabFramesKey.self) { viewModel.pinboardTabFrames = $0 }
        // Drag-select: press in the shelf's empty space — the card row or the header — and
        // sweep over cards. A press on a card or a pinboard tab never starts one
        // (`beginCardSweep` refuses it), so those keep their own click and drag. `.local`
        // here is the "shelfRoot" space.
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { value in
                    if sweepGesture == .idle {
                        viewModel.beginCardSweep(at: value.startLocation, modifiers: NSEvent.modifierFlags)
                        sweepGesture = viewModel.cardSweep.isActive ? .sweeping : .refused
                    }
                    if sweepGesture == .sweeping { viewModel.moveCardSweep(to: value.location) }
                }
                .onEnded { _ in
                    if sweepGesture == .sweeping { viewModel.endCardSweep() }
                    sweepGesture = .idle
                }
        )
        .overlay { CardSweepRectangle(sweep: viewModel.cardSweep) }
        // Pops out of the tab under a card drag to name the board it will land in.
        .overlay {
            PinboardDropCalloutLayer(callout: viewModel.dropCallout,
                                     pinboards: viewModel.pinboards,
                                     tabFrames: viewModel.pinboardTabFrames)
        }
        // Pro-dark: force the marketing electric-blue accent regardless of the system
        // accent color. The forced dark appearance itself is set on the panel window in
        // `ShelfPanelController`, which cascades to this hosted content.
        .tint(viewModel.settings.shelfTheme == .dark ? Tokens.electricBlue : nil)
        // Edit/Create/Adjust Color/Tips are shown as a centered child window over the
        // shelf (see `ShelfModalHostView`), not as attached sheets that overflow off the
        // bottom of the screen. This view is always on screen while the shelf is open, so
        // it reliably drives the host window's show/hide as the modal state changes.
        .onChange(of: hasActiveModal) { _, active in viewModel.onModalPresent?(active) }
    }

    private var hasActiveModal: Bool {
        viewModel.editingItem != nil || viewModel.creatingItem
            || viewModel.adjustingColorItem != nil || viewModel.showingTips
    }
}

/// Slim, quiet strip (no colored fill — just an SF Symbol and text on the shelf's
/// existing material) shown while Accessibility isn't granted, since without it
/// `AppCoordinator.pasteFromShelf` can only place the item on the clipboard rather
/// than actually paste it into the frontmost app.
private struct PermissionBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Copy needs Accessibility access to paste."))
                    .font(Tokens.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Open Settings")) { openAccessibilitySettings() }
                    .buttonStyle(.link)
                    .font(Tokens.caption)
                Spacer(minLength: 8)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Tokens.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, Tokens.shelfPadding)
            .padding(.vertical, 6)
            Divider()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ShelfHeader: View {
    @Bindable var viewModel: ShelfViewModel
    @FocusState private var searchFocused: Bool

    /// Quiet scope hint: on a pinboard tab, the search field's placeholder names the
    /// board so the user knows a query only searches its members, not all of history.
    /// Falls back to the global "Search" placeholder on History, and if the tab's
    /// pinboard can't be resolved (e.g. mid-delete).
    private var searchPlaceholder: String {
        if case .pinboard(let id) = viewModel.tab,
           let name = viewModel.pinboards.first(where: { $0.id == id })?.name {
            return String(format: String(localized: "Search %@"), name)
        }
        return String(localized: "Search or filter…")
    }

    var body: some View {
        // 三段式头部: 标签栏水平居中, 搜索框 + 按钮固定右侧。收藏板很多时标签栏
        // 会从中间向两侧生长, 挤到搜索框再加限宽滚动 (当前不过度设计)。
        ZStack {
            ShelfTabs(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            HStack(spacing: 10) {
                SearchTokenField(viewModel: viewModel, placeholder: searchPlaceholder, focused: $searchFocused)
                    .frame(maxWidth: 220)
                PasteStackButton(viewModel: viewModel)
                DrawerMenu(viewModel: viewModel)
            }
        }
        .padding(.horizontal, Tokens.shelfPadding)
        .padding(.vertical, 8)
        // Not auto-focused on open — the shelf opens in browse mode. Keep the view model in
        // sync with the field's focus, and honor a focus request from the key handler
        // (type-to-search).
        .onChange(of: searchFocused) { _, focused in viewModel.isSearchFieldFocused = focused }
        .onChange(of: viewModel.endSearchEditingRequested) { _, requested in
            if requested {
                searchFocused = false
                viewModel.endSearchEditingRequested = false
            }
        }
        .onChange(of: viewModel.focusSearchRequested) { _, requested in
            if requested {
                searchFocused = true
                viewModel.focusSearchRequested = false
                // Focusing select-alls the field, so the letter that started the search
                // would be replaced by the next keystroke. Move the caret to the end once
                // focus lands (type-to-search only — a manual click keeps its position).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                        editor.selectedRange = NSRange(location: editor.string.count, length: 0)
                    }
                }
            }
        }
    }
}

/// Header control that opens the Paste Stack palette (`onTogglePasteStack`), tinting to the
/// accent while the stack is active. While ⌥ is held it reveals the stack's rebindable
/// hotkey as a `KeyCap`, matching the shelf's other ⌥-hold hints (the tab number badges).
private struct PasteStackButton: View {
    @Bindable var viewModel: ShelfViewModel

    private var hotkey: String {
        KeyboardShortcuts.getShortcut(for: .togglePasteStack)?.description ?? "⇧⌘C"
    }

    var body: some View {
        HStack(spacing: 5) {
            IconButton(systemName: "square.stack.3d.up", fontSize: 15,
                       size: CGSize(width: 34, height: 30),
                       tint: viewModel.isPasteStackOn ? Color.accentColor : .secondary,
                       help: "Paste Stack (\(hotkey))") {
                viewModel.onTogglePasteStack?()
            }
            if viewModel.optionHeld {
                KeyCap(text: hotkey)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: viewModel.optionHeld)
    }
}

/// The shelf's own "more" control — a discreet ellipsis button mirroring every
/// status-menu action, so the app is fully usable with the menu bar icon hidden
/// (`SettingsStore.hideMenuBarIcon`). Deliberately quiet (borderless, no chevron,
/// secondary tint) rather than a toolbar, to match the shelf's existing icon-button
/// language (e.g. the "Add Pinboard" `+` in `ShelfTabs`).
private struct DrawerMenu: View {
    let viewModel: ShelfViewModel
    @State private var target = MenuActionTarget()

    var body: some View {
        // A plain Button that pops an NSMenu, rather than a SwiftUI `Menu`: the latter's
        // `.borderlessButton` style only made the glyph pixels clickable, so the ⋯ was
        // extremely hard to hit. `IconButton` gives a large, hover-highlighted,
        // fully-hittable target with a tooltip.
        IconButton(systemName: "ellipsis.circle", fontSize: 16,
                   size: CGSize(width: 34, height: 30), help: "More", action: showMenu)
    }

    private func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, checked: Bool = false, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.fire(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = MenuAction(run: action)
            item.state = checked ? .on : .off
            menu.addItem(item)
        }
        add("New Item…") { viewModel.onNewItem?() }
        add("Paste Stack", checked: viewModel.isPasteStackOn) { viewModel.onTogglePasteStack?() }
        add(viewModel.isPrivacyModeOn ? String(localized: "Resume Monitoring") : String(localized: "Pause Monitoring")) { viewModel.onTogglePrivacyMode?() }
        menu.addItem(.separator())
        add(String(localized: "Clear History…")) { viewModel.onClearHistory?() }
        add(String(localized: "Export…")) { viewModel.onExportHistory?() }
        add(String(localized: "Import…")) { viewModel.onImportHistory?() }
        menu.addItem(.separator())
        add(String(localized: "Keyboard & Tips…")) { viewModel.showingTips = true }
        add(String(localized: "Settings…")) { viewModel.onOpenSettings?() }
        menu.addItem(.separator())
        add(String(localized: "Quit Copy")) { viewModel.onQuit?() }

        guard let window = NSApp.keyWindow, let content = window.contentView else { return }
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = content.convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: content)
    }
}

/// Wraps a Swift closure so it can ride an `NSMenuItem`'s `representedObject` and be
/// invoked by `MenuActionTarget` — AppKit menu items are selector-based, not closure-based.
private final class MenuAction {
    let run: () -> Void
    init(run: @escaping () -> Void) { self.run = run }
}

private final class MenuActionTarget: NSObject {
    @objc func fire(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
    }
}

/// Left-hand pill row: History, then pinboards, then Add Pinboard.
private struct ShelfTabs: View {
    @Bindable var viewModel: ShelfViewModel
    @State private var createPresented = false
    @State private var renamingPinboard: Pinboard?

    var body: some View {
        HStack(spacing: 4) {
            TabPill(
                label: String(localized: "All"),
                symbol: "tray.full",
                isSelected: viewModel.tab == .history,
                shortcutHint: viewModel.optionHeld ? "1" : nil,
                action: { viewModel.selectTab(.history) }
            )
            ForEach(Array(viewModel.pinboards.enumerated()), id: \.element.id) { offset, pinboard in
                TabPill(
                    label: pinboard.name,
                    symbol: pinboard.symbol,
                    emoji: pinboard.emoji,
                    tint: pinboard.tint,
                    showsSymbol: false,
                    isSelected: pinboard.id.map { viewModel.tab == .pinboard($0) } ?? false,
                    isDropTargeted: pinboard.id != nil && viewModel.dropTargetedPinboardID == pinboard.id,
                    reorderIndicatorEdge: viewModel.reorderTargetedPinboardID == pinboard.id
                        ? (viewModel.reorderPlacesAfterTarget ? .trailing : .leading) : nil,
                    // ⌥1 is All, so pinboards start at ⌥2; only the first eight get a
                    // hint (⌥9 is the ceiling of the number-key routing).
                    shortcutHint: (viewModel.optionHeld && offset + 2 <= 9) ? "\(offset + 2)" : nil,
                    action: {
                        guard let id = pinboard.id else { return }
                        // Clicking the already-selected pinboard opens its editor; otherwise
                        // it just switches to it.
                        if viewModel.tab == .pinboard(id) {
                            renamingPinboard = pinboard
                        } else {
                            viewModel.selectTab(.pinboard(id))
                        }
                    }
                )
                .contextMenu {
                    // "Edit…" opens PinboardEditPopover, which edits name, symbol, emoji,
                    // and color (including a custom color picker) in one place.
                    Button("Edit…") { renamingPinboard = pinboard }
                    Button("Delete Pinboard", role: .destructive) { confirmDelete(pinboard) }
                }
                .popover(isPresented: Binding(
                    get: { pinboard.id != nil && renamingPinboard?.id == pinboard.id },
                    set: { if !$0 { renamingPinboard = nil } }
                )) {
                    PinboardEditPopover(mode: .rename(pinboard)) { name, symbol, emoji, tint in
                        if let id = pinboard.id {
                            viewModel.renamePinboard(id: id, to: name)
                            viewModel.setPinboardSymbol(id: id, symbol)
                            viewModel.setPinboardEmoji(id: id, emoji)
                            viewModel.setPinboardTint(id: id, tint)
                        }
                        renamingPinboard = nil
                    }
                }
                .onDrag {
                    guard let id = pinboard.id else { return NSItemProvider() }
                    viewModel.pinboardDragStarted(id: id)
                    let data = Data(String(id).utf8)
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(
                        forTypeIdentifier: UTType.copyPinboard.identifier,
                        // `.all` so the type is listed on the drag pasteboard: AppKit only offers a drag
                        // to `ShelfHostingView` when one of its registered types is there.
                        visibility: .all
                    ) { completion in
                        completion(data, nil)
                        return nil
                    }
                    return provider
                }
                // Publish this tab's frame (in the shelf's "shelfRoot" space) so
                // ShelfHostingView can map a drag location back to this pinboard. Drops are
                // handled for the whole shelf, not per-tab — see PinboardTabFramesKey for why.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: PinboardTabFramesKey.self,
                            value: pinboard.id.map { [$0: geo.frame(in: .named("shelfRoot"))] } ?? [:]
                        )
                    }
                )
            }
            IconButton(systemName: "plus", fontSize: 12,
                       size: CGSize(width: 34, height: 30), help: "New pinboard") {
                createPresented = true
            }
            .popover(isPresented: $createPresented) {
                // 新建弹层预填自动主题色 (多巴胺色板轮转), 用户仍可改。
                PinboardEditPopover(mode: .create, initialTint: viewModel.nextPinboardTint) { name, symbol, emoji, tint in
                    viewModel.createPinboard(name: name, symbol: symbol, emoji: emoji, tint: tint)
                }
            }
        }
        // A near-invisible but real backing across the whole tab strip so a card dropped
        // onto a pinboard tab routes to THIS panel instead of passing through the glass
        // surface to the window behind (which pasted the card's text into the app
        // underneath). The window server treats a pixel as pass-through only when its
        // composited alpha rounds to zero, so this needs alpha above 1/255 (0.001 rounds
        // to 0 and still passed drags through); 0.02 is ~2% and imperceptible over glass.
        .background(Color.black.opacity(0.02))
        .onChange(of: createPresented) { _, isPresented in
            viewModel.pinboardPopoverShown = isPresented || renamingPinboard != nil
        }
        .onChange(of: renamingPinboard) { _, newValue in
            viewModel.pinboardPopoverShown = createPresented || newValue != nil
        }
    }

    /// Matches the existing `NSAlert` confirm pattern (`AppDelegate.clearHistory`), with
    /// the alert's window bumped to the shelf panel's own `.statusBar` level — otherwise
    /// the alert would render behind the always-on-top, non-activating shelf panel.
    private func confirmDelete(_ pinboard: Pinboard) {
        guard let id = pinboard.id else { return }
        let alert = NSAlert()
        alert.messageText = "Delete pinboard \(pinboard.name)?"
        alert.informativeText = "Items stay in your history."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = .statusBar
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.deletePinboard(id: id)
        }
    }
}

private struct TabPill: View {
    let label: String
    let symbol: String
    /// A user-chosen emoji shown in place of the SF Symbol, when set. `nil`/untinted
    /// pinboards (and the All tab) render exactly as before this feature.
    var emoji: String? = nil
    /// A user-chosen hex color (e.g. "FF3B30"); empty means no color identity.
    var tint: String = ""
    /// Whether to draw the SF Symbol when no emoji is set. History uses it (a clock);
    /// pinboards don't — their identity is the tag color block and optional emoji.
    var showsSymbol: Bool = true
    let isSelected: Bool
    var isDropTargeted: Bool = false
    var reorderIndicatorEdge: Edge? = nil
    /// The ⌘-number that jumps to this tab (e.g. "1"), shown as a badge while ⌘ is held.
    var shortcutHint: String? = nil
    let action: () -> Void
    @State private var isHovering = false

    private var tintColor: Color? {
        tint.isEmpty ? nil : Tokens.color(fromHex: tint)
    }

    /// The board's own color when it has one, so the targeted tab matches its callout.
    private var dropColor: Color { tintColor ?? .accentColor }

    /// 实底 tag 上的可读前景: 按相对亮度选深字或白字 (柠檬黄配深字, 鸢尾紫配白字)。
    private var tintIsLight: Bool {
        guard let rgb = UInt64(tint, radix: 16) else { return false }
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }

    private var labelColor: Color {
        if isSelected, tintColor != nil {
            return tintIsLight ? Color.black.opacity(0.82) : Color.white
        }
        return isSelected ? Color.primary : Color.primary.opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let emoji, !emoji.isEmpty {
                Text(emoji)
            } else if showsSymbol {
                Image(systemName: symbol)
            }
            Text(label)
            if let shortcutHint {
                Text("⌘\(shortcutHint)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .accessibilityHidden(true)
            }
        }
        .font(Tokens.caption)
        // Unselected tabs sit a step below the selected one but stay well above
        // `.secondary`, which drops too far on glass (see `GlassSurfaceModifier`).
        .foregroundStyle(labelColor)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTargeted ? dropColor : .clear, lineWidth: 2)
        )
        .overlay(alignment: reorderIndicatorEdge == .trailing ? .trailing : .leading) {
            if reorderIndicatorEdge != nil {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 20)
                    .offset(x: reorderIndicatorEdge == .trailing ? 3 : -3)
            }
        }
        // A drop-targeted tab visibly pops so it's unmistakable which pinboard a dragged
        // card will land in, even when the cursor's drag chip sits near it; the drop
        // callout hangs from it (see `PinboardDropCalloutLayer`).
        .scaleEffect(isDropTargeted ? 1.08 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDropTargeted)
        // A plain tappable surface, NOT a Button: a SwiftUI `Button` on macOS fights the
        // drag session for the mouse-up, so dragging a card onto a pinboard landed only
        // intermittently; a tap gesture on a plain view coexists with the drag cleanly.
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
    }

    private var backgroundFill: Color {
        if isDropTargeted { return dropColor.opacity(0.35) }
        if isSelected {
            if let tintColor { return tintColor } // 选中 = tag 实底
            return Color.primary.opacity(0.08)
        }
        if let tintColor { return tintColor.opacity(isHovering ? 0.22 : 0.15) } // 未选中 = tag 软底
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}

private struct ShelfItemsRow: View {
    @Bindable var viewModel: ShelfViewModel

    private var currentPinboardID: Int64? {
        if case .pinboard(let id) = viewModel.tab { return id }
        return nil
    }

    /// Read straight from `SettingsStore` (both it and `ShelfViewModel` are
    /// `@Observable`), so toggling "Shelf Size" in Settings re-renders this row
    /// immediately — no separate change-hook plumbing needed on the SwiftUI side.
    private var compact: Bool { viewModel.settings.compactShelf }

    /// 按卡片行实测宽度算每页卡片数。每次布局都重新算, 不读缓存——切换显示器、
    /// 改分辨率、切紧凑档位都会自然得到新值 (旧的缓存方案要等一条四段回调链路
    /// 走通, 断一环就得重启, 用户报告过)。
    private func capacity(forWidth width: CGFloat) -> Int {
        let card = Tokens.cardWidth(compact: compact)
        let gap = Tokens.cardGap(compact: compact)
        let pad = Tokens.shelfPadding(compact: compact)
        // 收藏分隔线比普通卡片间隙多占一个 gap。
        let dividerReserve: CGFloat =
            (viewModel.favoritesCount > 0 && viewModel.favoritesCount < viewModel.items.count)
            ? (5.5 + gap) : 0
        return PageCapacity.count(viewportWidth: width, cardWidth: card, gap: gap,
                                  padding: pad, dividerReserve: dividerReserve)
    }

    /// 当前页的卡片切片 (携带全列表下标, 供收藏分隔线与 ⌘数字粘贴编号使用)。
    private func pageItems(capacity: Int) -> [(index: Int, item: ClipItem)] {
        let capacity = max(1, capacity)
        guard !viewModel.items.isEmpty else { return [] }
        let start = min(viewModel.pageIndex * capacity, viewModel.items.count - 1)
        let end = min(start + capacity, viewModel.items.count)
        return viewModel.items[start..<end].enumerated().map { (index: start + $0.offset, item: $0.element) }
    }

    /// 卡片所属的第一个收藏板主题色 (按标签顺序取第一个), 供顶部归属色条;
    /// 不属于任何收藏板时返回 nil。读取成员版本计数, 加入/移出时触发重算。
    private func firstPinboardTint(for item: ClipItem) -> String? {
        _ = viewModel.pinboardMembershipVersion
        guard let itemID = item.id else { return nil }
        guard let ids = try? viewModel.pinboardStore.pinboardIDs(forItemID: itemID), !ids.isEmpty else { return nil }
        return viewModel.pinboards.first { $0.id.map { ids.contains($0) } ?? false }?.tint
    }

    /// 翻页容器: 无滚动视图, 每页固定渲染 `capacity` 张卡, 翻页由状态机切片驱动。
    private func pageContent(capacity: Int) -> some View {
        HStack(spacing: Tokens.cardGap(compact: compact)) {
            ForEach(pageItems(capacity: capacity), id: \.item.uuid) { pair in
                // A divider between the leading favorites and the rest.
                if pair.index == viewModel.favoritesCount,
                   viewModel.favoritesCount > 0,
                   viewModel.favoritesCount < viewModel.items.count {
                    FavoritesDivider(compact: compact)
                }
                ItemCardView(
                    item: pair.item,
                    isSelected: viewModel.isSelected(pair.item),
                    isInlineRenaming: viewModel.inlineRenamingItemID == pair.item.id,
                    store: viewModel.store,
                    pinboards: viewModel.pinboards,
                    pinboardTint: firstPinboardTint(for: pair.item),
                    currentPinboardID: currentPinboardID,
                    favoritesEnabled: viewModel.settings.favoritesEnabled,
                    compact: compact,
                    searchQuery: viewModel.searchQuery.text,
                    isFlashing: viewModel.flashItemID == pair.item.uuid,
                    pasteNumber: (viewModel.commandHeld && pair.index < 9) ? pair.index + 1 : nil,
                    canShowInHistory: !viewModel.searchQuery.isEmpty || currentPinboardID != nil,
                    onClick: { modifiers in viewModel.handleCardClick(pair.item, modifiers: modifiers) },
                    onHoverChanged: { hovering in
                        if hovering {
                            viewModel.hoveredItemID = pair.item.uuid
                        } else if viewModel.hoveredItemID == pair.item.uuid {
                            viewModel.hoveredItemID = nil
                        }
                    },
                    onPaste: { viewModel.requestPaste(pair.item, plain: false) },
                    onPastePlain: { viewModel.requestPaste(pair.item, plain: true) },
                    onEdit: { viewModel.beginEdit(pair.item) },
                    onAdjustColor: { viewModel.beginAdjustColor(pair.item) },
                    onBeginInlineRename: { viewModel.beginInlineRename(pair.item) },
                    onCommitInlineRename: { viewModel.commitInlineRename(pair.item, to: $0) },
                    onCancelInlineRename: { viewModel.cancelInlineRename() },
                    onToggleFavorite: { viewModel.toggleFavorite(pair.item) },
                    onAddToPinboard: { id in viewModel.addItem(pair.item, toPinboard: id) },
                    onRemoveFromPinboard: {
                        if let currentPinboardID {
                            viewModel.removeItem(pair.item, fromPinboard: currentPinboardID)
                        }
                    },
                    onAddToPasteStack: { viewModel.addToPasteStack(pair.item) },
                    onCopyText: { viewModel.copyText(pair.item) },
                    onQuickLook: { viewModel.quickLook(pair.item) },
                    onOpen: { viewModel.open(pair.item) },
                    onShowInHistory: { viewModel.showInHistory(pair.item) },
                    onRotate: { viewModel.rotateImage(pair.item, clockwise: $0) },
                    onDelete: { viewModel.delete(pair.item) },
                    dragProvider: { viewModel.dragProvider(for: pair.item) },
                    dragBadgeCount: viewModel.isSelected(pair.item) ? viewModel.selection.selected.count : 1
                )
                .id(pair.item.uuid)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CardFramesKey.self,
                            value: [pair.item.uuid: geo.frame(in: .named(CardSweep.contentSpace))]
                        )
                    }
                )
                .onAppear {
                    viewModel.fetchLinkPreviewIfNeeded(for: pair.item)
                }
                .popover(isPresented: Binding(
                    get: { viewModel.isSelected(pair.item) && pair.item.uuid == viewModel.selection.primary && viewModel.previewShown },
                    set: { viewModel.previewShown = $0 }
                )) {
                    PreviewPane(item: pair.item, store: viewModel.store)
                }
            }
        }
        .padding(.horizontal, Tokens.shelfPadding(compact: compact))
        .padding(.vertical, compact ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // Dead-pixel hit-test floor: 让面板任意位置的滚轮/点击都被本层认领。
        .background(Color.black.opacity(0.001))
        .coordinateSpace(name: CardSweep.contentSpace)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("shelfRoot")) } action: {
            viewModel.cardSweep.viewportFrame = $0
        }
        .onPreferenceChange(CardFramesKey.self) { viewModel.cardSweep.cardFramesChanged($0) }
        // 整页替换的滑动过渡: 方向跟随最近一次翻页。
        .id(viewModel.pageIndex)
        .transition(.asymmetric(
            insertion: viewModel.lastFlipDirection >= 0
                ? .move(edge: .trailing).combined(with: .opacity)
                : .move(edge: .leading).combined(with: .opacity),
            removal: viewModel.lastFlipDirection >= 0
                ? .move(edge: .leading).combined(with: .opacity)
                : .move(edge: .trailing).combined(with: .opacity)
        ))
    }

    /// 渐隐带宽度: 该方向还有页面时, 卡片在面板边缘淡出 24pt, 提示可翻页。
    private static let edgeFadeWidth: CGFloat = 24

    var body: some View {
        if viewModel.items.isEmpty {
            ShelfEmptyState(viewModel: viewModel)
        } else {
            // 宽度是唯一真相: 每页卡片数在这里按当前实测宽度算出, 直接喂给渲染。
            // 布局一变 (切显示器/改分辨率/换紧凑档位) 这里就重跑, 没有缓存可失效。
            GeometryReader { geo in
                let capacity = capacity(forWidth: geo.size.width)
                // 遮罩与箭头包在 pageContent (含 .id 翻页过渡) 外层: 翻页时卡片在
                // 固定的渐隐带下滑动, 箭头保持原位不随页面移动。
                pageContent(capacity: capacity)
                    .mask {
                        HStack(spacing: 0) {
                            if viewModel.pageIndex > 0 {
                                LinearGradient(colors: [.black.opacity(0), .black],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: Self.edgeFadeWidth)
                            }
                            Rectangle().fill(.black)
                            if viewModel.pageIndex < PageCapacity.pageCount(itemCount: viewModel.items.count, capacity: capacity) - 1 {
                                LinearGradient(colors: [.black, .black.opacity(0)],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: Self.edgeFadeWidth)
                            }
                        }
                    }
                    .overlay(alignment: .leading) { pageEdgeControl(-1, capacity: capacity) }
                    .overlay(alignment: .trailing) { pageEdgeControl(1, capacity: capacity) }
                    // 事件路径 (滚动/键盘) 拿不到布局宽度, 靠这个回报值翻页;
                    // 只在容量真的变了时才写回, 避免每次布局都触发无效更新。
                    .onAppear { viewModel.layoutDidMeasure(capacity: capacity) }
                    .onChange(of: capacity) { _, new in viewModel.layoutDidMeasure(capacity: new) }
            }
        }
    }

    /// 该方向还有页面时渲染边缘箭头 (方向 -1 = 上一页, +1 = 下一页), 否则不占位。
    @ViewBuilder
    private func pageEdgeControl(_ direction: Int, capacity: Int) -> some View {
        let pageCount = PageCapacity.pageCount(itemCount: viewModel.items.count, capacity: capacity)
        let hasPage = direction < 0 ? viewModel.pageIndex > 0 : viewModel.pageIndex < pageCount - 1
        if hasPage {
            PageEdgeButton(direction: direction) {
                viewModel.flipPage(direction: direction, capacity: capacity)
            }
        }
    }
}

/// 翻页边缘引导: 渐隐带上的小箭头, hover 微亮, 点击翻一页。
/// 与滚轮翻页共用 `flipPage`, 滑动动画与触感反馈保持一致。
private struct PageEdgeButton: View {
    let direction: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(hovering ? 0.9 : 0.5))
                .frame(width: 24, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.primary.opacity(hovering ? 0.08 : 0.0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(direction < 0 ? Text("Previous page") : Text("Next page"))
        .padding(.horizontal, 2)
    }
}

/// The vertical rule between the leading favorited cards and the rest of the shelf,
/// topped with a small star so the grouping reads at a glance.
private struct FavoritesDivider: View {
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.8))
                .frame(width: 1.5)
        }
        .frame(height: Tokens.cardHeight(compact: compact))
        .padding(.horizontal, 2)
        .accessibilityLabel("Favorites divider")
    }
}

/// Empty state for the items row, tailored to the active tab and search state.
private struct ShelfEmptyState: View {
    let viewModel: ShelfViewModel

    private var symbolName: String {
        switch viewModel.tab {
        case .history:
            return "square.on.square"
        case .pinboard(let id):
            return viewModel.pinboards.first(where: { $0.id == id })?.symbol ?? "pin"
        }
    }

    private var headline: String {
        if !viewModel.searchQuery.isEmpty {
            let text = viewModel.searchQuery.text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? "No matches for these filters" : "No matches for \"\(text)\""
        }
        switch viewModel.tab {
        case .history: return "Copy something to get started"
        case .pinboard: return "Nothing pinned yet"
        }
    }

    private var caption: String? {
        guard viewModel.searchQuery.isEmpty, case .pinboard = viewModel.tab else { return nil }
        return "Drag a card here or use Add to Pinboard"
    }

    /// True only on the empty History tab with no active search: the genuine "nothing
    /// captured yet" moment, where a short first-run primer earns its space. Search and
    /// pinboard empties stay minimal.
    private var isFirstRun: Bool {
        guard viewModel.searchQuery.isEmpty else { return false }
        if case .history = viewModel.tab { return true }
        return false
    }

    var body: some View {
        VStack(spacing: isFirstRun ? 10 : 6) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(headline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if isFirstRun {
                Text("Text, images, links, files, and colors all land here automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    KeyHint(key: "⇧⌘V", label: "Open Copy")
                    KeyHint(key: "↩", label: "Paste")
                    KeyHint(key: "Space", label: "Preview")
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A slim, dismissible strip along the shelf's bottom that teaches the core keyboard
/// path. Sized to fit the standard shelf's spare vertical space below the cards; hidden
/// in compact mode and once dismissed (see `ShelfRootView.showsLegend`).
private struct KeyboardLegend: View {
    let pageIndex: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↩", label: String(localized: "Paste"))
            KeyHint(key: "Space", label: String(localized: "Preview"))
            KeyHint(key: "⇧↩", label: String(localized: "Plain text"))
            KeyHint(key: "⌘⌫", label: String(localized: "Delete"))
            Spacer(minLength: 8)
            pageIndicator
        }
        .padding(.horizontal, Tokens.shelfPadding)
        .padding(.top, 4)
        .padding(.bottom, 11)
    }

    /// 翻页指示器: 替代原先的图例关闭按钮, 显示当前位置。
    private var pageIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 10, weight: .medium))
            Text(String(format: String(localized: "Page %d / %d"), pageIndex + 1, pageCount))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }
}
