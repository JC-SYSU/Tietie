import AppKit
import CopyCore
import SwiftUI

/// Hosts the Settings window in a standard titled window that `AppCoordinator` owns and
/// shows directly, rather than through SwiftUI's `Settings` scene.
///
/// Hands-on testing showed the `Settings` scene doesn't work for Copy's configuration:
/// Copy has no `WindowGroup` (it's a menu-bar-only, `LSUIElement` app), and in that
/// shape `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`
/// reports `handled == true` but never actually creates a window. Managing the window
/// ourselves sidesteps that mechanism entirely.
///
/// 布局是经典 macOS 偏好设置: `NSTabViewController` 的 `.toolbar` 样式在窗口顶部放一排
/// 图标标签, 每个标签是一个 SwiftUI 页面。页面宽度固定 (`SettingsLayout.paneWidth`),
/// 高度由内容决定; 切换标签时窗口以左上角为锚点动画改变高度。
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(settings: SettingsStore, store: ItemStore) {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for section in SettingsSection.allCases {
            let page = NSHostingController(rootView: SettingsView(section: section, settings: settings, store: store))
            // 页面的理想尺寸写进 preferredContentSize, 内容变高 (如排除列表变化) 时
            // 会触发 preferredContentSizeDidChange, 窗口跟着调整。
            page.sizingOptions = .preferredContentSize
            page.title = section.title
            let item = NSTabViewItem(viewController: page)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.systemImage, accessibilityDescription: section.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.appearance = settings.shelfTheme.appearance
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
        tabs.fitWindow(animated: false)
    }

    func setTheme(_ theme: ShelfTheme) {
        window?.appearance = theme.appearance
    }

    func show() {
        // Only center on first appearance — recentering on every reopen would undo a
        // user-moved window position.
        if window?.isVisible != true {
            (contentViewController as? SettingsTabViewController)?.fitWindow(animated: false)
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 切换标签或页面内容尺寸变化时, 把窗口内容区调成当前页面的理想尺寸。
@MainActor
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? ""
        fitWindow(animated: true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        if viewController === tabViewItems[selectedTabViewItemIndex].viewController {
            fitWindow(animated: true)
        }
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window ?? viewIfLoaded?.window,
              tabViewItems.indices.contains(selectedTabViewItemIndex),
              let page = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        var size = page.preferredContentSize
        if size.width < 1 || size.height < 1 { size = page.view.fittingSize }
        guard size.width >= 1, size.height >= 1 else { return }
        window.title = tabViewItems[selectedTabViewItemIndex].label
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        // 以左上角为锚点: macOS 坐标系 y 向上, 保持 maxY 不变。
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}
