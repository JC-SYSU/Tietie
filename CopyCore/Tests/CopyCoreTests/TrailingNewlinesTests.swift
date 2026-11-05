import AppKit
import XCTest
@testable import CopyCore

final class TrailingNewlinesTests: XCTestCase {
    // MARK: - trimmed

    func testEveryLineBreakKindIsRemoved() {
        let breaks = ["\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]
        for lineBreak in breaks {
            XCTAssertEqual(TrailingNewlines.trimmed("ls" + lineBreak), "ls",
                           "U+\(String(lineBreak.unicodeScalars.first!.value, radix: 16))")
        }
    }

    func testWholeTrailingRunIsRemoved() {
        XCTAssertEqual(TrailingNewlines.trimmed("ls\n\n\r\n\u{2028}"), "ls")
    }

    func testInteriorBreaksAndTrailingSpacesKept() {
        XCTAssertEqual(TrailingNewlines.trimmed("a\nb\n"), "a\nb")
        XCTAssertEqual(TrailingNewlines.trimmed("ls -la \n"), "ls -la ")
        XCTAssertEqual(TrailingNewlines.trimmed("a\t"), "a\t")
        // 换行与空格交替: 只删最后那段连续换行。
        XCTAssertEqual(TrailingNewlines.trimmed("a\n \n\n"), "a\n ")
    }

    func testLeadingBreaksKept() {
        XCTAssertEqual(TrailingNewlines.trimmed("\n\nls\n"), "\n\nls")
    }

    func testNoTrailingBreakReturnsSameText() {
        XCTAssertEqual(TrailingNewlines.trimmed("中文内容"), "中文内容")
        XCTAssertEqual(TrailingNewlines.trimmed(""), "")
    }

    func testAllBreaksBecomesEmpty() {
        XCTAssertEqual(TrailingNewlines.trimmed("\n\r\n"), "")
    }

    func testCJKAndEmojiBeforeBreak() {
        XCTAssertEqual(TrailingNewlines.trimmed("浙江👍🏽\r\n"), "浙江👍🏽")
    }

    // MARK: - RTF

    private func rtf(_ string: String, color: NSColor = .red) -> Data {
        let attributed = NSAttributedString(string: string, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: color,
        ])
        return try! attributed.data(from: NSRange(location: 0, length: attributed.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private func parseRTF(_ data: Data) -> NSAttributedString {
        try! NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                documentAttributes: nil)
    }

    func testRichTextLosesTrailingBreakKeepsAttributes() throws {
        let stripped = try XCTUnwrap(TrailingNewlines.strippedRichText(rtf("Bold 中文\n\n"), type: .rtf))
        let parsed = parseRTF(stripped)
        XCTAssertEqual(parsed.string, "Bold 中文")
        let font = try XCTUnwrap(parsed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 20)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        let color = try XCTUnwrap(parsed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(color.usingColorSpace(.sRGB)!.redComponent, 1, accuracy: 0.01)
    }

    func testRichTextWithoutTrailingBreakUntouched() {
        XCTAssertNil(TrailingNewlines.strippedRichText(rtf("no break"), type: .rtf))
    }

    func testInvalidRichTextReturnsNil() {
        XCTAssertNil(TrailingNewlines.strippedRichText(Data("not rtf".utf8), type: .rtf))
    }

    // MARK: - strip (paste path)

    func testStripRemovesBreakFromPlainAndRTFLeavesHTML() throws {
        let html = Data("<p>hi</p>\n".utf8)
        let reps = [
            CapturedRepresentation(uti: "public.rtf", data: rtf("hi\n")),
            CapturedRepresentation(uti: "public.html", data: html),
            CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("hi\n".utf8)),
        ]
        let out = try XCTUnwrap(TrailingNewlines.strip(reps))
        XCTAssertEqual(out.map(\.uti), reps.map(\.uti))
        XCTAssertEqual(parseRTF(out[0].data).string, "hi")
        XCTAssertEqual(out[1].data, html)
        XCTAssertEqual(String(data: out[2].data, encoding: .utf8), "hi")
    }

    func testStripReturnsNilWhenPlainHasNoBreak() {
        let reps = [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("hi".utf8))]
        XCTAssertNil(TrailingNewlines.strip(reps))
    }

    func testStripKeepsAllBreakContentAsIs() {
        let reps = [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("\n\n".utf8))]
        XCTAssertNil(TrailingNewlines.strip(reps))
    }

    func testStripKeepsUnparseableRTF() throws {
        let bogus = Data("rtf".utf8)
        let reps = [
            CapturedRepresentation(uti: "public.rtf", data: bogus),
            CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("x\r\n".utf8)),
        ]
        let out = try XCTUnwrap(TrailingNewlines.strip(reps))
        XCTAssertEqual(out[0].data, bogus)
        XCTAssertEqual(String(data: out[1].data, encoding: .utf8), "x")
    }

    func testStripLeavesImagesAlone() {
        let reps = [CapturedRepresentation(uti: "public.png", data: Data([1, 2, 3]))]
        XCTAssertNil(TrailingNewlines.strip(reps))
    }

    // MARK: - pasteboardRewrite (system clipboard path)

    func testRewriteMergesPlainTextTypesAndKeepsPrivateTypes() throws {
        let privateData = Data("excel-private\n".utf8)
        let original = [
            CapturedRepresentation(uti: "public.utf16-external-plain-text", data: Data("a\n".utf16BytesWithBOM)),
            CapturedRepresentation(uti: "com.microsoft.Biff12", data: privateData),
            CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("a\n".utf8)),
        ]
        let out = try XCTUnwrap(TrailingNewlines.pasteboardRewrite(original, text: "a\n"))
        XCTAssertEqual(out.map(\.uti), ["public.utf8-plain-text", "com.microsoft.Biff12"])
        XCTAssertEqual(String(data: out[0].data, encoding: .utf8), "a")
        XCTAssertEqual(out[1].data, privateData)
    }

    func testRewriteAddsUTF8WhenOnlyLegacyTextReadable() throws {
        let out = try XCTUnwrap(TrailingNewlines.pasteboardRewrite(
            [CapturedRepresentation(uti: "public.html", data: Data("<b>a</b>".utf8))], text: "a\n"))
        XCTAssertEqual(out.map(\.uti), ["public.html", "public.utf8-plain-text"])
        XCTAssertEqual(String(data: out[1].data, encoding: .utf8), "a")
    }

    func testRewriteNilWhenNoBreak() {
        XCTAssertNil(TrailingNewlines.pasteboardRewrite(
            [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("a".utf8))], text: "a"))
    }
}

private extension String {
    var utf16BytesWithBOM: [UInt8] {
        [0xFF, 0xFE] + utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }
}

/// 改写系统剪贴板的替身: 写入时同步推进 FakePasteboard 的 changeCount, 与真剪贴板一致。
final class FakeRewriter: PasteboardRewriting {
    let pasteboard: FakePasteboard
    var itemReps: [CapturedRepresentation]?
    var replaced: [[CapturedRepresentation]] = []
    /// 模拟读取期间源 app 又写了一次剪贴板。
    var bumpChangeCountOnRead = false

    init(pasteboard: FakePasteboard) { self.pasteboard = pasteboard }

    func singleItemRepresentations(optionalTypes: Set<String>, maxTotalBytes: Int) -> [CapturedRepresentation]? {
        if bumpChangeCountOnRead { pasteboard.changeCount += 1 }
        return itemReps
    }

    func replaceContents(with representations: [CapturedRepresentation]) -> Int {
        replaced.append(representations)
        pasteboard.changeCount += 1
        pasteboard.stringValue = representations
            .first { $0.uti == "public.utf8-plain-text" }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        return pasteboard.changeCount
    }
}

final class TrailingNewlineMonitorTests: XCTestCase {
    var pasteboard: FakePasteboard!
    var rewriter: FakeRewriter!
    var captured: [CapturedItem]!
    var monitor: ClipboardMonitor!

    override func setUp() {
        super.setUp()
        pasteboard = FakePasteboard()
        rewriter = FakeRewriter(pasteboard: pasteboard)
        captured = []
        monitor = ClipboardMonitor(
            pasteboard: pasteboard, rewriter: rewriter,
            rules: RulesEngine(excludedBundleIDs: ["com.excluded.app"]),
            frontmostApp: { ("com.apple.Terminal", "Terminal") },
            onCapture: { [weak self] item in self?.captured.append(item) })
    }

    private func putTextItem(_ text: String) {
        pasteboard.putText(text)
        rewriter.itemReps = [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data(text.utf8))]
    }

    func testCaptureStoresTextWithoutTrailingBreak() {
        putTextItem("git status\r\n")
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].plainText, "git status")
        XCTAssertEqual(captured[0].hashData, Data("git status".utf8))
        XCTAssertEqual(captured[0].representations.map(\.data), [Data("git status".utf8)])
    }

    func testTrailingBreakNoLongerBlocksColorDetection() {
        putTextItem("#4C9DFF\n")
        monitor.checkNow()
        XCTAssertEqual(captured.first?.kind, .color)
        XCTAssertEqual(captured.first?.plainText, "#4C9DFF")
    }

    func testOnlyLineBreaksIsNotCaptured() {
        putTextItem("\n\n")
        monitor.checkNow()
        XCTAssertTrue(captured.isEmpty)
    }

    func testCapturedRTFLosesTrailingParagraph() throws {
        let attributed = NSAttributedString(string: "styled\n")
        let rtf = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.putText("styled\n", extraTypes: ["public.rtf"])
        pasteboard.dataByUTI["public.rtf"] = rtf
        monitor.checkNow()
        let rep = try XCTUnwrap(captured.first?.representations.first { $0.uti == "public.rtf" })
        let parsed = try NSAttributedString(data: rep.data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                            documentAttributes: nil)
        XCTAssertEqual(parsed.string, "styled")
    }

    func testHistoryOnlyModeLeavesSystemClipboardAlone() {
        putTextItem("ls\n")
        monitor.checkNow()
        XCTAssertTrue(rewriter.replaced.isEmpty)
        XCTAssertEqual(pasteboard.stringValue, "ls\n")
    }

    func testSystemClipboardModeRewritesOnceAndDoesNotRecapture() {
        monitor.rewritesSystemClipboard = true
        putTextItem("ls\n")
        monitor.checkNow()
        XCTAssertEqual(rewriter.replaced.count, 1)
        XCTAssertEqual(pasteboard.stringValue, "ls")
        XCTAssertEqual(captured.count, 1)
        // 自己写入造成的 changeCount 变化不能被当成一次新复制。
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(rewriter.replaced.count, 1)
    }

    func testSystemClipboardModeSkipsTextWithoutBreak() {
        monitor.rewritesSystemClipboard = true
        putTextItem("ls")
        monitor.checkNow()
        XCTAssertTrue(rewriter.replaced.isEmpty)
        XCTAssertEqual(captured.count, 1)
    }

    func testSystemClipboardModeSkipsExcludedAppsAndConcealed() {
        monitor.rewritesSystemClipboard = true
        pasteboard.putText("secret\n", extraTypes: ["org.nspasteboard.ConcealedType"])
        rewriter.itemReps = [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("secret\n".utf8))]
        monitor.checkNow()
        XCTAssertTrue(rewriter.replaced.isEmpty)
        XCTAssertEqual(pasteboard.stringValue, "secret\n")
    }

    func testSystemClipboardModeSkipsWhenItemUnreadable() {
        monitor.rewritesSystemClipboard = true
        pasteboard.putText("ls\n")
        rewriter.itemReps = nil // 多项、含文件或类型读不出
        monitor.checkNow()
        XCTAssertTrue(rewriter.replaced.isEmpty)
        XCTAssertEqual(captured.first?.plainText, "ls")
    }

    func testSystemClipboardModeBacksOffWhenSourceWritesAgain() {
        monitor.rewritesSystemClipboard = true
        putTextItem("ls\n")
        rewriter.bumpChangeCountOnRead = true
        monitor.checkNow()
        XCTAssertTrue(rewriter.replaced.isEmpty)
    }
}

final class TrailingNewlinePasteTests: XCTestCase {
    func testPasteStripsLegacyItemsWithTrailingBreak() {
        let pasteboard = SpyPasteboard()
        let service = PasteService(pasteboard: pasteboard, keyPoster: SpyKeyPoster())
        service.place([CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("rm -rf build\n".utf8))],
                      plainTextOnly: false)
        XCTAssertEqual(pasteboard.written[0].representations.map(\.data), [Data("rm -rf build".utf8)])
    }

    func testPlainTextOnlyPasteIsStrippedToo() {
        let pasteboard = SpyPasteboard()
        let service = PasteService(pasteboard: pasteboard, keyPoster: SpyKeyPoster())
        service.place([
            CapturedRepresentation(uti: "public.html", data: Data("<p>x</p>".utf8)),
            CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("x\u{2029}".utf8)),
        ], plainTextOnly: true)
        XCTAssertEqual(pasteboard.written[0].representations,
                       [CapturedRepresentation(uti: "public.utf8-plain-text", data: Data("x".utf8))])
    }
}

/// 真 NSPasteboard (私有命名, 不碰系统剪贴板) 上跑一遍改写流程。
final class NSPasteboardRewriteTests: XCTestCase {
    var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: .init("copy.trailing-newline-test.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testRewriteRoundTripKeepsPrivateTypeAndStripsTextAndRTF() throws {
        let attributed = NSAttributedString(string: "echo hi\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        let rtf = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let item = NSPasteboardItem()
        item.setData(Data("echo hi\n".utf8), forType: .string)
        item.setData(rtf, forType: .rtf)
        item.setData(Data("private\n".utf8), forType: .init("com.example.private"))
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let original = try XCTUnwrap(pasteboard.singleItemRepresentations(
            optionalTypes: TrailingNewlines.plainTextUTIs, maxTotalBytes: 1_000_000))
        let text = try XCTUnwrap(pasteboard.string())
        let rewritten = try XCTUnwrap(TrailingNewlines.pasteboardRewrite(original, text: text))
        let before = pasteboard.changeCount
        XCTAssertGreaterThan(pasteboard.replaceContents(with: rewritten), before)

        XCTAssertEqual(pasteboard.string(forType: .string), "echo hi")
        XCTAssertEqual(pasteboard.data(forType: .init("com.example.private")), Data("private\n".utf8))
        let rtfOut = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let parsed = try NSAttributedString(data: rtfOut, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                            documentAttributes: nil)
        XCTAssertEqual(parsed.string, "echo hi")
        // 系统派生的 UTF-16 文本也跟着变成新内容, 没有残留旧换行。
        if let utf16 = pasteboard.data(forType: .init("public.utf16-external-plain-text")) {
            XCTAssertFalse(String(data: utf16, encoding: .utf16)?.hasSuffix("\n") ?? true)
        }
    }

    func testMultipleItemsAreLeftAlone() {
        pasteboard.clearContents()
        pasteboard.writeObjects(["a\n" as NSString, "b\n" as NSString])
        XCTAssertNil(pasteboard.singleItemRepresentations(optionalTypes: [], maxTotalBytes: 1_000_000))
    }

    func testFileURLsAreLeftAlone() {
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp") as NSURL])
        XCTAssertNil(pasteboard.singleItemRepresentations(optionalTypes: [], maxTotalBytes: 1_000_000))
    }

    func testOversizedItemIsLeftAlone() {
        pasteboard.clearContents()
        pasteboard.setString(String(repeating: "x", count: 2_000) + "\n", forType: .string)
        XCTAssertNil(pasteboard.singleItemRepresentations(optionalTypes: [], maxTotalBytes: 1_000))
    }
}
