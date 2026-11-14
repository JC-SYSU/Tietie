import XCTest
@testable import TietieCore

/// Locks the normalized-substring semantics that replaced FTS5 unicode61 matching.
final class TextSearchTests: XCTestCase {
    func testChineseSubstringInsideLongerRunMatches() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("缺血性卒中机械取栓术后"))
        XCTAssertEqual(try store.search("机械取栓").map(\.plainText), ["缺血性卒中机械取栓术后"])
        XCTAssertEqual(try store.search("卒中").count, 1)
        XCTAssertEqual(try store.search("取栓术后").count, 1)
    }

    /// Fuzzy/subsequence hits are deliberately out: the query must appear contiguously.
    func testSearchIsNotFuzzy() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("机械取栓"))
        XCTAssertEqual(try store.search("机械栓").count, 0)
    }

    /// LIKE metacharacters in the query must stay literal through the SQL prefilter.
    func testLikeMetacharactersAreEscaped() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("50%_discount_code"))
        XCTAssertEqual(try store.search("50%_disc").count, 1)
        XCTAssertEqual(try store.search("discount").count, 1)
        XCTAssertEqual(try store.search("zz%").count, 0, "% must not act as a wildcard")
        XCTAssertEqual(try store.search("50_disc").count, 0, "_ must not act as a wildcard")
    }

    func testMatchingIgnoresCaseAndCollapsesWhitespace() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("Clinical  TRIAL\tprotocol"))
        XCTAssertEqual(try store.search("clinical trial").count, 1)
        XCTAssertEqual(try store.search("TRIAL").count, 1)
    }

    func testMultiWordQuerySpansSourceAppAndContent() throws {
        let store = try makeTempStore()
        let saved = try store.save(makeText("invoice #42", bundle: "com.test.safari", app: "Safari"))
        XCTAssertEqual(try store.search("safari invoice").map(\.id), [saved.id])
    }

    /// Word-level AND, order-free — the semantics FTS's matchingAllPrefixesIn had.
    func testMultiWordQueryIsOrderFree() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("机械取栓术后管理"))
        XCTAssertEqual(try store.search("管理 术后").count, 1)
        XCTAssertEqual(try store.search("术后 管理").count, 1)
        XCTAssertEqual(try store.search("管理 取栓检查").count, 0, "every word must land somewhere")
    }

    func testWhitespaceOnlyQueryMatchesNothing() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("anything"))
        XCTAssertEqual(try store.search("   \n\t").count, 0)
    }

    func testRecognizedChineseTextIsSearchable() throws {
        let store = try makeTempStore()
        let imageItem = CapturedItem(
            kind: .image, plainText: "Image", hashData: Data("img-zh".utf8),
            representations: [CapturedRepresentation(uti: "public.png", data: Data([0x89, 0x50]))],
            sourceBundleID: nil, sourceAppName: nil
        )
        let saved = try store.save(imageItem)
        try store.setRecognizedText(itemID: saved.id!, "报告结论：卒中取栓成功")
        XCTAssertEqual(try store.search("报告结论").map(\.id), [saved.id])
    }

    func testFacetedSearchMatchesChineseSubstring() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("缺血性卒中机械取栓术后"))
        _ = try store.save(makeText("unrelated english note"))
        let hits = try store.search(filter: SearchFilter(text: "机械取栓"))
        XCTAssertEqual(hits.map(\.plainText), ["缺血性卒中机械取栓术后"])
    }

    func testFavoritesFirstPutsMatchingFavoriteAheadOfRecentMatches() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("gadget one"), now: Date(timeIntervalSince1970: 3000))
        let older = try store.save(makeText("gadget two"), now: Date(timeIntervalSince1970: 2000))
        try store.setFavorite(itemID: older.id!, true)
        let hits = try store.search(filter: SearchFilter(text: "gadget"))
        XCTAssertEqual(hits.map(\.plainText), ["gadget two", "gadget one"])
    }
}
