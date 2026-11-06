import Foundation

public final class ClipboardMonitor {
    public var rules: RulesEngine
    public var isPaused = false
    /// true = 捕获到末尾带换行的文本时, 把系统剪贴板也改写成去掉换行的版本 (直接 ⌘V
    /// 也生效)。false = 只有 Copy 的历史和从 Copy 粘贴出去的内容去换行。
    public var rewritesSystemClipboard = false

    /// Representations larger than this are never captured (memory protection).
    public static let maxRepresentationBytes = 100_000_000

    private let pasteboard: PasteboardReading
    private let rewriter: PasteboardRewriting?
    private let pollInterval: TimeInterval
    private let frontmostApp: () -> (bundleID: String?, name: String?)
    private let onCapture: (CapturedItem) -> Void
    /// 用户规则对每次复制的判定 (保留的不报)。在主队列上调用, app 用它记命中计数。
    public var onVerdict: ((CaptureVerdict) -> Void)?
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    public init(pasteboard: PasteboardReading,
                rewriter: PasteboardRewriting? = nil,
                pollInterval: TimeInterval = 0.25,
                rules: RulesEngine,
                frontmostApp: @escaping () -> (bundleID: String?, name: String?),
                onCapture: @escaping (CapturedItem) -> Void) {
        self.pasteboard = pasteboard
        self.rewriter = rewriter
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

        let types = pasteboard.typeIdentifiers()
        guard !RulesEngine.hasSkipMarker(types) else { return }
        let source = frontmostApp()
        let isRemote = types.contains(RulesEngine.remoteClipboardType)
        // 来源 app、通用剪贴板这两项不用读内容就能定; 定了「不保存」就不读剪贴板。
        if case .decided(let verdict) = rules.evaluator.preflight(sourceBundleID: source.bundleID, isRemote: isRemote),
           verdict.outcome == .drop {
            onVerdict?(verdict)
            return
        }
        guard var item = Self.snapshot(from: pasteboard, source: source) else { return }
        let verdict = rules.evaluator.evaluate(RuleSubject(captured: item, isRemote: isRemote))
        if verdict.outcome != .keep || !verdict.timedOutKeywords.isEmpty || !verdict.timedOutPresets.isEmpty {
            onVerdict?(verdict)
        }
        switch verdict.outcome {
        case .drop:
            // 不保存的内容也不改写系统剪贴板, 与原来「排除的 app」一致: 剪贴板原样不动。
            return
        case .expire(let minutes):
            item.expiresAfter = TimeInterval(minutes * 60)
        case .keep:
            break
        }
        if rewritesSystemClipboard, item.kind != .image {
            rewriteSystemClipboard()
        }
        onCapture(item)
    }

    /// 把剪贴板换成去掉末尾换行的版本。除纯文本/RTF 外的类型原样写回 (含 app 私有类型),
    /// 但剪贴板所有者会变成 Copy, 源 app 自己粘贴时可能只认通用格式。任何一步不满足就
    /// 保持原剪贴板不动。
    private func rewriteSystemClipboard() {
        guard let rewriter,
              let text = pasteboard.string(), TrailingNewlines.endsWithNewline(text),
              let original = rewriter.singleItemRepresentations(
                optionalTypes: TrailingNewlines.plainTextUTIs,
                maxTotalBytes: Self.maxRepresentationBytes),
              let rewritten = TrailingNewlines.pasteboardRewrite(original, text: text),
              // 读取期间源 app 又写了剪贴板: 放弃, 下一轮按新内容处理。
              pasteboard.changeCount == lastChangeCount
        else { return }
        // 记下自己这次写入的 changeCount, 下一轮轮询就不会把它当成新复制再捕获一次。
        lastChangeCount = rewriter.replaceContents(with: rewritten)
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
        // 文本本体: 去掉末尾换行 (见 TrailingNewlines); 空串或全是换行视同没有。
        let rawText = pasteboard.string()
        let hadTrailingNewline = rawText.map(TrailingNewlines.endsWithNewline) ?? false
        let text = rawText.map(TrailingNewlines.trimmed).flatMap { $0.isEmpty ? nil : $0 }
        let hasRichText = pasteboard.typeIdentifiers().contains("public.rtf")
            || pasteboard.typeIdentifiers().contains("public.html")
        // Office 套件复制文本时附带选区位图作 fallback (位图+RTF/HTML/纯文本俱全):
        // 富文本与可用文本同时在场, 文本才是复制的本体 → 按文本路径收录并丢弃位图,
        // 否则从 Office 复制的文本会被存成图片、粘贴出来也是图 (用户报告)。
        // 仅「有富文本格式」不构成走文本路径的理由——macOS 截图、浏览器/相册复制
        // 照片是「位图+HTML 壳、没有任何纯文本」(实测 screencapture 即如此), 那个
        // HTML 只是 <img> 包装, 照片才是本体, 必须按图片收 (5156db6 按「有 HTML 即
        // 文本」判定, 把这类照片整条漏收, 用户报告)。
        if !imageReps.isEmpty, text == nil || !hasRichText {
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

        guard let text else { return nil }
        var kind = ItemKind.forText(text)
        // A standalone hex color copied as text ("#4C9DFF" or bare "4C9DFF") is a color, so
        // it swatches and matches the Color filter — see `HexColor.isColorText`.
        if HexColor.isColorText(text) { kind = .color }
        var representations: [CapturedRepresentation] = []
        if let rtf = pasteboard.data(forUTI: "public.rtf") {
            // 纯文本末尾有换行时, RTF 末尾通常也有段落标记, 一并去掉 (去不掉就原样保留)。
            let stripped = hadTrailingNewline ? TrailingNewlines.strippedRichText(rtf, type: .rtf) : nil
            representations.append(CapturedRepresentation(uti: "public.rtf", data: stripped ?? rtf))
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
