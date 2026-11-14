import AppKit
import TietieCore
import SwiftUI

/// 觅见风格的设置窗口：左侧固定边栏导航 + 右侧内容区。
///
/// 每个标签页建一个独立的 NSHostingController，切换时 show/hide，不换 rootView，
/// 避免 SwiftUI 异步重新 layout 导致 fittingSize 读取时机不准。
@MainActor
final class SettingsWindowController: NSWindowController {
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

            contentHost.leadingAnchor.constraint(equalTo: rule.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: Navigation

    func selectSection(_ section: SettingsSection, animated: Bool) {
        pageControllers[selectedSection]?.view.isHidden = true
        selectedSection = section
        window?.title = section.title

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
                // 只钉三边时 sizingOptions = [] 让 view 高度为 0, 整页空白。
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
        if window?.isVisible != true {
            window?.setContentSize(NSSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight))
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
                    .font(.system(size: 18, weight: .semibold))
                Text("Clipboard shelf")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider().padding(.horizontal, 8).padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                SidebarItem(section: section, isSelected: section == selectedSection,
                            onTap: { onSelect(section) })
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
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 18)
                    .padding(.leading, 8).padding(.trailing, 6)
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
                    .fill(isSelected ? Color.accentColor.opacity(0.10)
                          : (hovered ? Color.primary.opacity(0.05) : Color.clear))
                    .padding(.horizontal, 6)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .padding(.horizontal, 2)
    }
}
