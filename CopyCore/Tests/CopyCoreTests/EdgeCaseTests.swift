import XCTest
@testable import CopyCore

final class EdgeCaseTests: XCTestCase {
    func testSearchWithFTSSpecialCharactersDoesNotThrow() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("quoted \"phrase\" here"))
        XCTAssertNoThrow(try store.search("\"quoted"))
        XCTAssertNoThrow(try store.search("*star*"))
        XCTAssertNoThrow(try store.search("a AND b OR c"))
        XCTAssertEqual(try store.search("quoted").count, 1)
    }

    func testSnapshotSkipsFilesFallsThroughToImageColorText() {
        let pasteboard = FakePasteboard()
        pasteboard.changeCount += 1
        pasteboard.typeIDs = ["public.png", CopyPasteboard.colorType, "public.utf8-plain-text"]
        pasteboard.dataByUTI = ["public.png": Data([0x01])]
        pasteboard.colorHexValue = "#112233"
        pasteboard.stringValue = "text"
        let source: (bundleID: String?, name: String?) = (nil, nil)

        XCTAssertEqual(ClipboardMonitor.snapshot(from: pasteboard, source: source)?.kind, .image)

        pasteboard.dataByUTI = [:]
        XCTAssertEqual(ClipboardMonitor.snapshot(from: pasteboard, source: source)?.kind, .color)

        pasteboard.typeIDs = ["public.utf8-plain-text"]
        pasteboard.colorHexValue = nil
        XCTAssertEqual(ClipboardMonitor.snapshot(from: pasteboard, source: source)?.kind, .text)
    }

    func testSnapshotReturnsNilWhenOnlyFiles() {
        let pasteboard = FakePasteboard()
        pasteboard.changeCount += 1
        pasteboard.typeIDs = ["public.file-url"]
        pasteboard.urls = [URL(fileURLWithPath: "/tmp/a.txt")]
        let source: (bundleID: String?, name: String?) = (nil, nil)
        XCTAssertNil(ClipboardMonitor.snapshot(from: pasteboard, source: source))
    }
}
