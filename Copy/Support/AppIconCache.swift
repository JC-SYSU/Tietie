import AppKit

@MainActor
enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static var misses = Set<String>()

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        if misses.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            misses.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}

/// 卡头色带用的 app 主色: 从图标里取出现最多的彩色色相, 按 bundle id 缓存。
/// 只取不透明、有一定饱和度和亮度的像素按色相分 12 桶, 用像素数×饱和度加权选最重的桶,
/// 取桶内平均色; 彩色像素太少 (灰、黑、白为主的图标) 时用全部不透明像素平均。
/// 结果再压一下饱和度和亮度, 免得色带比卡片内容还抢眼。
@MainActor
enum AppTintCache {
    private static var cache: [String: NSColor] = [:]
    private static var misses = Set<String>()

    static func tint(forBundleID bundleID: String?) -> NSColor? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        if misses.contains(bundleID) { return nil }
        guard let icon = AppIconCache.icon(forBundleID: bundleID),
              let color = dominantColor(of: icon) else {
            misses.insert(bundleID)
            return nil
        }
        cache[bundleID] = color
        return color
    }

    static func dominantColor(of image: NSImage) -> NSColor? {
        let side = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }

        var buckets = [(w: Double, r: Double, g: Double, b: Double, n: Double)](repeating: (0, 0, 0, 0, 0), count: 12)
        var all = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
        for i in 0..<(side * side) {
            let a = Double(data[i * 4 + 3]) / 255
            guard a > 0.8 else { continue }
            // 位图是预乘 alpha 的, 还原后再算。
            let r = Double(data[i * 4]) / 255 / a
            let g = Double(data[i * 4 + 1]) / 255 / a
            let b = Double(data[i * 4 + 2]) / 255 / a
            all.r += r; all.g += g; all.b += b; all.n += 1
            let c = NSColor(deviceRed: r, green: g, blue: b, alpha: 1)
            let s = c.saturationComponent, v = c.brightnessComponent
            guard s > 0.25, v > 0.2 else { continue }
            let k = min(11, Int(c.hueComponent * 12))
            buckets[k].w += Double(s)
            buckets[k].r += r; buckets[k].g += g; buckets[k].b += b; buckets[k].n += 1
        }
        guard all.n > 0 else { return nil }
        let base: NSColor
        if let best = buckets.max(by: { $0.w < $1.w }), best.n >= all.n * 0.08 {
            base = NSColor(deviceRed: best.r / best.n, green: best.g / best.n, blue: best.b / best.n, alpha: 1)
        } else {
            base = NSColor(deviceRed: all.r / all.n, green: all.g / all.n, blue: all.b / all.n, alpha: 1)
        }
        return NSColor(deviceHue: base.hueComponent,
                       saturation: min(base.saturationComponent, 0.75),
                       brightness: min(max(base.brightnessComponent, 0.25), 0.88),
                       alpha: 1)
    }

    /// 色带上的文字用白还是深色: 按 WCAG 相对亮度比较两者对比度, 取高的那个。
    static func prefersDarkText(on color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        let whiteContrast = 1.05 / (l + 0.05)
        let darkContrast = (l + 0.05) / 0.05
        return darkContrast > whiteContrast
    }
}
