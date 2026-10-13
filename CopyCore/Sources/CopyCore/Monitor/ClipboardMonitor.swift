import Foundation

public final class ClipboardMonitor {
    public var rules: RulesEngine
    public var isPaused = false

    /// Representations larger than this are never captured (memory protection).
    public static let maxRepresentationBytes = 100_000_000

    private let pasteboard: PasteboardReading
    private let pollInterval: TimeInterval
    private let frontmostApp: () -> (bundleID: String?, name: String?)
    private let onCapture: (CapturedItem) -> Void
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    public init(pasteboard: PasteboardReading,
                pollInterval: TimeInterval = 0.25,
                rules: RulesEngine,
                frontmostApp: @escaping () -> (bundleID: String?, name: String?),
                onCapture: @escaping (CapturedItem) -> Void) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.rules = rules
        self.frontmostApp = frontmostApp
        self.onCapture = onCapture
        // Don't ingest whatever was on the clipboard before launch.
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.checkNow() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func checkNow() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !isPaused else { return }

        let source = frontmostApp()
        guard rules.shouldCapture(types: pasteboard.typeIdentifiers(),
                                  sourceBundleID: source.bundleID) else { return }
        guard let item = Self.snapshot(from: pasteboard, source: source) else { return }
        onCapture(item)
    }

    public static func snapshot(from pasteboard: PasteboardReading,
                                source: (bundleID: String?, name: String?)) -> CapturedItem? {
        let urls = pasteboard.fileURLs()
        if !urls.isEmpty {
            return nil // 历史记录不存 files (用户决定)。
        }

        var imageReps: [CapturedRepresentation] = []
        for imageUTI in ["public.png", "public.tiff"] {
            if let data = pasteboard.data(forUTI: imageUTI) {
                imageReps.append(CapturedRepresentation(uti: imageUTI, data: data))
            }
        }
        // Office 套件 (PowerPoint/Word/Excel) 复制文本时会把选区位图作为 fallback 一起
        // 放上剪贴板 (RTF/HTML/纯文本俱全)。此时文本才是用户复制的本体, 位图只是给
        // 不认富文本的应用兜底——按文本路径收录并丢弃位图, 否则从 Office 复制的文本
        // 会被存成图片、粘贴出来也是图 (用户报告)。没有富文本格式的裸位图仍按图片收
        // (浏览器"复制图片"不带 RTF/HTML, 不受影响)。
        let hasRichText = pasteboard.typeIdentifiers().contains("public.rtf")
            || pasteboard.typeIdentifiers().contains("public.html")
        if !imageReps.isEmpty, !hasRichText {
            return capped(CapturedItem(
                kind: .image, plainText: "Image", hashData: imageReps[0].data,
                representations: imageReps,
                sourceBundleID: source.bundleID, sourceAppName: source.name))
        }

        if pasteboard.typeIdentifiers().contains(CopyPasteboard.colorType),
           let hex = pasteboard.colorHex() {
            return capped(CapturedItem(
                kind: .color, plainText: hex, hashData: Data(hex.utf8),
                representations: [CapturedRepresentation(uti: CopyPasteboard.colorType, data: Data(hex.utf8))],
                sourceBundleID: source.bundleID, sourceAppName: source.name))
        }

        guard let text = pasteboard.string(), !text.isEmpty else { return nil }
        var kind = ItemKind.forText(text)
        // A standalone hex color copied as text ("#4C9DFF" or bare "4C9DFF") is a color, so
        // it swatches and matches the Color filter — see `HexColor.isColorText`.
        if HexColor.isColorText(text) { kind = .color }
        var representations: [CapturedRepresentation] = []
        if let rtf = pasteboard.data(forUTI: "public.rtf") {
            representations.append(CapturedRepresentation(uti: "public.rtf", data: rtf))
            if kind == .text { kind = .richText }
        }
        if let html = pasteboard.data(forUTI: "public.html") {
            representations.append(CapturedRepresentation(uti: "public.html", data: html))
            if kind == .text { kind = .richText }
        }
        representations.append(CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(text.utf8)))
        return capped(CapturedItem(
            kind: kind, plainText: text, hashData: Data(text.utf8),
            representations: representations,
            sourceBundleID: source.bundleID, sourceAppName: source.name))
    }

    static func capped(_ item: CapturedItem?) -> CapturedItem? {
        guard let item else { return nil }
        for rep in item.representations where rep.data.count > maxRepresentationBytes {
            return nil
        }
        return item
    }
}
