import SwiftUI
import AppKit

/// Single switch point for adopting Liquid Glass across the app: every M7 surface
/// (shelf, cards, popovers, HUD, paste stack, settings) should route its background
/// through `glassSurface` rather than reaching for `NSVisualEffectView` directly, so
/// the macOS-version gate and the Reduce Transparency fallback only need to be right
/// in one place.
///
/// - macOS 26+ with Reduce Transparency OFF: renders `View.glassEffect(_:in:)`
///   (Liquid Glass), verified against the installed macOS 26.5 SDK's
///   `SwiftUICore.swiftinterface` — `nonisolated public func glassEffect(_ glass:
///   Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`, gated
///   `@available(iOS 26.0, macOS 26.0, ...)`. Apple's docs (fetched from the live
///   `developer.apple.com` JSON API for this page) describe it as anchoring the glass
///   material to the view's full frame, same footprint as a `.background(...)` — so it
///   drops into this app's existing `.background(ShelfBackground())` call sites as a
///   direct replacement.
/// - macOS < 26, or Reduce Transparency ON (checked live, including on macOS 26 — see
///   `ReduceTransparencyObserver` below): falls back to the app's existing `.hudWindow`
///   `NSVisualEffectView` material, corner-masked the same way the surface would have
///   been under glass.
///
/// `GlassEffectContainer` (for morphing multiple glass shapes into one another) isn't
/// used here — this helper renders one glass shape per surface. A later task that
/// places several glass surfaces close together (e.g. multiple shelf controls) and
/// wants them to blend/morph should wrap that group in `GlassEffectContainer`
/// independently; it composes fine with `glassSurface` underneath.
extension View {
    /// All four corners rounded by the same radius — the common case for cards,
    /// popovers, the HUD, and the paste stack.
    func glassSurface(cornerRadius: CGFloat) -> some View {
        modifier(GlassSurfaceModifier(corners: .all(cornerRadius)))
    }

    /// Independent per-corner radii, e.g. the shelf panel's top-corners-only
    /// treatment (it anchors to the bottom of the screen, so only its floating top
    /// edge is rounded).
    func glassSurface(corners: GlassSurfaceCorners) -> some View {
        modifier(GlassSurfaceModifier(corners: corners))
    }

    /// 面板专用: 材质和着色由设置决定 (设置 → 面板)。其他表面 (弹层、编辑窗) 不走这里,
    /// 保持 Liquid Glass regular。
    func glassSurface(corners: GlassSurfaceCorners, material: PanelMaterial, tint: Color?) -> some View {
        modifier(GlassSurfaceModifier(corners: corners, material: material, tint: tint))
    }
}

/// Per-corner radii, mirroring `UnevenRoundedRectangle`'s leading/trailing-based
/// parameters (RTL-safe) so the same value drives both the macOS 26 glass shape and
/// the pre-26 `NSVisualEffectView` fallback's `CACornerMask`.
struct GlassSurfaceCorners: Equatable {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var bottomTrailing: CGFloat = 0

    static func all(_ radius: CGFloat) -> Self {
        .init(topLeading: radius, topTrailing: radius, bottomLeading: radius, bottomTrailing: radius)
    }

    /// Only the top corners rounded — see `ShelfRootView`.
    static func top(_ radius: CGFloat) -> Self {
        .init(topLeading: radius, topTrailing: radius)
    }

    /// `CALayer.maskedCorners` has no per-corner radius, only a shared `cornerRadius`
    /// plus a mask of which corners it applies to. Every call site in this app rounds
    /// its corners uniformly, so the largest requested radius is the one shared
    /// radius the fallback path needs.
    fileprivate var fallbackRadius: CGFloat {
        max(topLeading, topTrailing, bottomLeading, bottomTrailing)
    }

    fileprivate var maskedCorners: CACornerMask {
        var mask: CACornerMask = []
        if topLeading > 0 { mask.insert(.layerMinXMaxYCorner) }
        if topTrailing > 0 { mask.insert(.layerMaxXMaxYCorner) }
        if bottomLeading > 0 { mask.insert(.layerMinXMinYCorner) }
        if bottomTrailing > 0 { mask.insert(.layerMaxXMinYCorner) }
        return mask
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let corners: GlassSurfaceCorners
    var material: PanelMaterial = .glassRegular
    /// 只对 Liquid Glass regular / clear 生效; nil 表示不着色。
    var tint: Color? = nil
    @StateObject private var reduceTransparency = ReduceTransparencyObserver()

    /// 内阴影: 沿形状内缘压一圈, 让面板从底下的内容里"陷"出来。
    private static let innerShadow = Color.black.opacity(0.15)

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency.isReduced {
                content.background { VisualEffectMaterial(corners: corners, material: .hudWindow, tint: overlayTint) }
            } else if #available(macOS 26, *), let glass = liquidGlass {
                content.glassEffect(glass, in: glassShape)
            } else {
                content.background { VisualEffectMaterial(corners: corners, material: fallbackMaterial, tint: overlayTint) }
            }
        }
        // 内阴影: 描边模糊后裁回形状内缘, 得到柔和的向内暗边; 不参与命中测试。
        // 这里既不能用 .shadow(), 也不能用 .fill(.shadow(...))——两者都会把玻璃/材质
        // 压成不透明离屏层, 整个面板会渲染成一块黑。
        .overlay {
            glassShape
                .strokeBorder(Self.innerShadow, lineWidth: 5)
                .blur(radius: 10)
                .clipShape(glassShape)
                .allowsHitTesting(false)
        }
    }

    /// 所选材质对应的 Liquid Glass; 选的是 NSVisualEffectView 材质时为 nil。
    @available(macOS 26, *)
    private var liquidGlass: Glass? {
        switch material {
        case .glassRegular: return Glass.regular.tint(tint)
        case .glassClear: return Glass.clear.tint(tint)
        case .glassIdentity: return .identity
        case .hudWindow, .sidebar, .windowBackground: return nil
        }
    }

    /// NSVisualEffectView 材质没有着色接口, 着色以一层同色半透明叠在材质上面 (在材质视图
    /// 内部的子图层, 随材质一起裁圆角)。无材质 (identity) 不着色。
    private var overlayTint: NSColor? {
        guard material != .glassIdentity, let tint else { return nil }
        return NSColor(tint)
    }

    /// NSVisualEffectView 材质: 选了这三种之一, 或系统低于 macOS 26 (此时 Liquid Glass
    /// 选项退回 `.hudWindow`)。
    private var fallbackMaterial: NSVisualEffectView.Material {
        switch material {
        case .sidebar: return .sidebar
        case .windowBackground: return .windowBackground
        default: return .hudWindow
        }
    }

    /// `UnevenRoundedRectangle`/`.rect(topLeadingRadius:...)` has shipped since
    /// macOS 13 (confirmed in the SDK interface), well below this app's 14.0 floor —
    /// only `glassEffect` itself is macOS-26-exclusive, so this shape needs no
    /// availability gate of its own.
    private var glassShape: UnevenRoundedRectangle {
        .rect(
            topLeadingRadius: corners.topLeading,
            bottomLeadingRadius: corners.bottomLeading,
            bottomTrailingRadius: corners.bottomTrailing,
            topTrailingRadius: corners.topTrailing
        )
    }
}

/// Watches `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` so
/// `glassSurface` flips to/from its solid fallback the instant Reduce Transparency is
/// toggled in System Settings, with no relaunch required.
@MainActor
private final class ReduceTransparencyObserver: ObservableObject {
    @Published private(set) var isReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` guarantees this runs on the main thread, but the observer
            // block's type is `@Sendable`, so the compiler can't statically see that as
            // main-actor isolation — `assumeIsolated` asserts what's already true here.
            MainActor.assumeIsolated {
                self?.isReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

/// The pre-26 (and Reduce-Transparency-on) fallback: the app's existing `.hudWindow`
/// material, corner-masked exactly like the bespoke `ShelfBackground` this replaces.
private struct VisualEffectMaterial: NSViewRepresentable {
    let corners: GlassSurfaceCorners
    var material: NSVisualEffectView.Material = .hudWindow
    /// 叠在材质上的颜色 (已含透明度); nil 不叠。
    var tint: NSColor? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        let overlay = CALayer()
        overlay.name = Self.tintLayerName
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        overlay.backgroundColor = tint?.cgColor
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = corners.fallbackRadius
        view.layer?.maskedCorners = corners.maskedCorners
        view.layer?.masksToBounds = true
        view.layer?.addSublayer(overlay)
        return view
    }

    private static let tintLayerName = "copy.tintOverlay"

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        if let overlay = nsView.layer?.sublayers?.first(where: { $0.name == Self.tintLayerName }) {
            overlay.frame = nsView.bounds
            overlay.backgroundColor = tint?.cgColor
        }
        nsView.layer?.cornerRadius = corners.fallbackRadius
        nsView.layer?.maskedCorners = corners.maskedCorners
    }
}
