import AppKit
import CopyCore
import SwiftUI

/// 觅见风格的设置窗口: 左侧固定边栏导航 + 右侧内容区。
///
/// 左栏 160pt，竖排导航项，选中时左边有蓝色色条 + 淡蓝底色。
/// 右栏 660pt，每页顶部一行大标题，内容由 SwiftUI 渲染。
/// 窗口高度跟着当前页面内容自适应，以左上角为锚点。
@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let store: ItemStore
    private var selectedSection: SettingsSection = .general

    // 右侧内容区：用一个容器 NSView 托管 NSHostingController 的 view。
    private let contentHost = NSView()
    private var pageController: NSHostingController<SettingsView>?

    init(settings: SettingsStore, store: ItemStore) {
        self.settings = settings
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.windowWidth, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = SettingsSection.general.title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildLayout()
        selectSection(.general, animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildLayout() {
        guard let window, let contentView = window.contentView else { return }
        window.appearance = settings.shelfTheme.appearance

        // ── 左侧边栏 ──────────────────────────────────────────────────
        let sidebar = NSHostingView(rootView: SidebarView(
            selectedSection: selectedSection,
            onSelect: { [weak self] section in
                self?.selectSection(section, animated: true)
            }
        ))
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebar)

        // ── 分隔线 ────────────────────────────────────────────────────
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rule)

        // ── 右侧内容区容器 ────────────────────────────────────────────
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

            contentHost.leadingAnchor.constraint(equalTo: rule.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    // MARK: Navigation

    func selectSection(_ section: SettingsSection, animated: Bool) {
        selectedSection = section
        window?.title = section.title

        // 重建 SwiftUI 页
        let newView = SettingsView(section: section, settings: settings, store: store)
        if let old = pageController {
            NotificationCenter.default.removeObserver(self,
                name: NSView.frameDidChangeNotification, object: old.view)
            old.view.removeFromSuperview()
        }
        let hc = NSHostingController(rootView: newView)
        hc.sizingOptions = .preferredContentSize
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
        ])
        pageController = hc
        fitWindow(animated: animated)
        // 页面内容高度变化时（如排除 app 列表增减）自动调整窗口高度。
        hc.view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: hc.view, queue: .main) { [weak self] _ in
            self?.fitWindow(animated: true)
        }

        // 刷新边栏高亮
        if let sidebar = window?.contentView?.subviews.first(where: { $0 is NSHostingView<SidebarView> }) as? NSHostingView<SidebarView> {
            sidebar.rootView = SidebarView(selectedSection: section, onSelect: { [weak self] s in
                self?.selectSection(s, animated: true)
            })
        }
    }

    func fitWindow(animated: Bool) {
        guard let window, let hc = pageController else { return }
        var contentHeight = hc.preferredContentSize.height
        if contentHeight < 40 { contentHeight = hc.view.fittingSize.height }
        guard contentHeight > 40 else { return }
        let frameSize = window.frameRect(forContentRect: NSRect(
            x: 0, y: 0,
            width: SettingsLayout.windowWidth,
            height: max(contentHeight, 200)))
        var frame = window.frame
        frame.origin.y += frame.height - frameSize.height
        frame.size = frameSize.size
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }



    func setTheme(_ theme: ShelfTheme) {
        window?.appearance = theme.appearance
    }

    func show() {
        if window?.isVisible != true {
            fitWindow(animated: false)
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 左侧边栏 SwiftUI

private struct SidebarView: View {
    var selectedSection: SettingsSection
    let onSelect: (SettingsSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App 品牌区
            VStack(alignment: .leading, spacing: 2) {
                Text("Copy")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Clipboard shelf")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider().padding(.horizontal, 8).padding(.bottom, 8)

            // 导航列表
            ForEach(SettingsSection.allCases) { section in
                SidebarItem(
                    section: section,
                    isSelected: section == selectedSection,
                    onTap: { onSelect(section) }
                )
            }
            Spacer(minLength: 0)
        }
        .frame(width: SettingsLayout.sidebarWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // 选中色条
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 18)
                    .padding(.leading, 8)
                    .padding(.trailing, 6)

                Image(systemName: section.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.primary : Color(nsColor: .labelColor))
                    .padding(.leading, 8)

                Spacer(minLength: 0)
            }
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.10)
                          : (hovered ? Color.primary.opacity(0.05) : Color.clear))
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .padding(.horizontal, 2)
    }
}
