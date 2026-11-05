import XCTest
@testable import CopyCore

final class SearchSnippetTests: XCTestCase {
    private func highlighted(_ s: SearchSnippet) -> [String] {
        let chars = Array(s.text)
        return s.highlights.map { String(chars[$0]) }
    }

    func testMatchNearStartKeepsWindowAtStart() throws {
        let s = try XCTUnwrap(SearchSnippet.make(text: "hello world, more text", query: "world"))
        XCTAssertFalse(s.truncatedStart)
        XCTAssertTrue(s.text.hasPrefix("hello"))
        XCTAssertEqual(highlighted(s), ["world"])
    }

    func testDeepMatchMovesWindowToTheMatch() throws {
        let text = String(repeating: "填充文字。", count: 200) + "关键结论在这里" + String(repeating: "后文", count: 300)
        let s = try XCTUnwrap(SearchSnippet.make(text: text, query: "关键结论"))
        XCTAssertTrue(s.truncatedStart)
        XCTAssertTrue(s.truncatedEnd)
        XCTAssertEqual(s.text.count, 300)
        XCTAssertEqual(highlighted(s), ["关键结论"])
        // 锚点前保留 40 个字符的上下文。
        XCTAssertEqual(s.highlights.first?.lowerBound, 40)
    }

    func testWindowStartsAtLineStartWhenNewlineIsNear() throws {
        let text = String(repeating: "x", count: 500) + "\nline with TARGET inside"
        let s = try XCTUnwrap(SearchSnippet.make(text: text, query: "target"))
        XCTAssertTrue(s.text.hasPrefix("line with"))
        XCTAssertTrue(s.truncatedStart)
    }

    func testHighlightsEveryWordAndEveryOccurrenceInWindow() throws {
        let s = try XCTUnwrap(SearchSnippet.make(text: "Git status; git push; then status", query: "git status"))
        XCTAssertEqual(highlighted(s), ["Git", "status", "git", "status"])
    }

    func testMatchesSameVariantsAsSearch() throws {
        let cases: [(String, String, String)] = [
            ("访问 ｈｔｔｐｓ：／／example", "https://", "ｈｔｔｐｓ：／／"),
            ("in Straße here", "strasse", "Straße"),
            ("range 2020–2024 end", "2020-2024", "2020–2024"),
            ("编号①号", "1", "①"),
            ("颗粒，平面", "颗粒,平面", "颗粒，平面"),
        ]
        for (text, query, expected) in cases {
            let s = try XCTUnwrap(SearchSnippet.make(text: text, query: query), query)
            XCTAssertEqual(highlighted(s), [expected], query)
        }
    }

    func testOverlappingHitsMerge() throws {
        let s = try XCTUnwrap(SearchSnippet.make(text: "abcdef", query: "abc cde"))
        XCTAssertEqual(s.highlights, [0..<5])
    }

    func testNoMatchInTextReturnsNil() {
        // 命中在标题/来源 app 等其他字段时, 正文里找不到 → nil, 卡片照常显示开头。
        XCTAssertNil(SearchSnippet.make(text: "body only", query: "safari"))
        XCTAssertNil(SearchSnippet.make(text: "body", query: "  "))
    }

    func testMatchBeyondScanLimitReturnsNil() {
        let text = String(repeating: "a", count: SearchSnippet.scanLimit + 10) + "needle"
        XCTAssertNil(SearchSnippet.make(text: text, query: "needle"))
    }
}
