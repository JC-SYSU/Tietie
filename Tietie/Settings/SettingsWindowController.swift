import AppKit
import TietieCore
import SwiftUI

/// 觅见风格的设置窗口：左侧固定边栏导航 + 右侧内容区。
///
/// 每个标签页建一个独立的 NSHostingController，切换时 show/hide，不换 rootView，
/// 避免 SwiftUI 异步重新 layout 导致 fittingSize 读取时机不准。
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let store: ItemStore
    private var selectedSection: SettingsSection = .general

    private let contentHost = NSView()
    private var sidebarHost: NSHostingView<SidebarView>?
    /// 每个标签页一个 HC，第一次访问时懒建。
    private var pageControllers: [SettingsSection: NSHostingController<SettingsView>] = [:]

    init(settings: SettingsStore, store: ItemStore) {
        self.settings = settings
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = String(localized: "Tietie Settings")
        window.isReleasedWhenClosed = false
        window.level = .normal
        super.init(window: window)
        window.delegate = self
        buildLayout()
        selectSection(.general, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildLayout() {
        guard let window, let contentView = window.contentView else { return }
        window.appearance = settings.shelfTheme.appearance

        // 画布：浅色用暖白，深色跟随系统窗口背景。
        let canvas = NSHostingView(rootView: SettingsCanvasView())
        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: contentView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let sidebar = NSHostingView(rootView: SidebarView(
            selectedSection: selectedSection,
            onSelect: { [weak self] section in self?.selectSection(section, animated: true) }
        ))
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebar)
        sidebarHost = sidebar

        let rule = NSBox(); rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rule)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentHost)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsLayout.sidebarWidth),

            rule.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            rule.topAnchor.constraint(equalTo: contentView.topAnchor),
            rule.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rule.widthAnchor.constraint(equalToConstant: 1),

            contentHost.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: SettingsLayout.contentLeading),
            contentHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentHost.widthAnchor.constraint(equalToConstant: SettingsLayout.contentWidth),
            contentHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: Navigation

    func selectSection(_ section: SettingsSection, animated: Bool) {
        pageControllers[selectedSection]?.view.isHidden = true
        selectedSection = section
        window?.title = String(localized: "Tietie Settings")

        let hc: NSHostingController<SettingsView>
        if let existing = pageControllers[section] {
            hc = existing
        } else {
            let view = SettingsView(section: section, settings: settings, store: store)
            hc = NSHostingController(rootView: view)
            hc.sizingOptions = []
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(hc.view)
            NSLayoutConstraint.activate([
                hc.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                hc.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
                // 四边都钉住: 窗口高度固定, 页面占满内容区, 内容超出时由 ScrollView 滚动。
                hc.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            ])
            pageControllers[section] = hc
        }
        hc.view.isHidden = false

        sidebarHost?.rootView = SidebarView(selectedSection: section,
            onSelect: { [weak self] s in self?.selectSection(s, animated: true) })
    }

    func setTheme(_ theme: ShelfTheme) { window?.appearance = theme.appearance }

    func show() {
        // 打开设置时切到普通应用模式，Dock 里出现贴贴图标；关闭时恢复菜单栏模式。
        NSApp.setActivationPolicy(.regular)
        if window?.isVisible != true {
            window?.setContentSize(NSSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight))
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - 画布

private struct SettingsCanvasView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        (scheme == .dark ? SettingsTheme.canvasDark : SettingsTheme.canvasLight)
            .ignoresSafeArea()
    }
}

// MARK: - 左侧边栏

private struct SidebarView: View {
    var selectedSection: SettingsSection
    let onSelect: (SettingsSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tietie")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Settings"))
                    .font(.system(size: 20, weight: .bold))
            }
            .padding(.leading, 20)
            .padding(.top, 26)
            .padding(.bottom, 42)

            ForEach(SettingsSection.allCases) { section in
                SidebarItem(section: section, isSelected: section == selectedSection,
                            onTap: { onSelect(section) })
                    .padding(.horizontal, 16)
                    .padding(.bottom, SettingsTheme.sidebarItemSpacing)
            }
            Spacer(minLength: 0)
        }
        .frame(width: SettingsLayout.sidebarWidth, alignment: .leading)
        .background(Color.clear)
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = scheme == .dark ? SettingsTheme.kleinDark : SettingsTheme.klein
        let selectedFill = scheme == .dark ? SettingsTheme.klein.opacity(0.30) : SettingsTheme.klein.opacity(0.10)

        Button(action: onTap) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isSelected ? accent : Color.clear)
                    .frame(width: 3, height: 16)
                    .padding(.leading, 8)
                    .padding(.trailing, 13)
                Image(systemName: section.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? accent : Color.secondary)
                    .frame(width: 18)
                    .padding(.trailing, 8)
                Text(section.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected
                                     ? (scheme == .dark ? Color(nsColor: .labelColor) : SettingsTheme.bodyLight)
                                     : Color.primary)
                Spacer(minLength: 0)
            }
            .frame(width: SettingsTheme.sidebarItemWidth, height: SettingsTheme.sidebarItemHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? selectedFill
                          : (hovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
