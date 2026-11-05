import XCTest
@testable import CopyCore

/// 命中摘要。行为测试都在两条路径上各跑一遍: 折叠表 (常规) 与旧做法 (表未建好或文本含
/// 退回字符时)。两者只在少数情况下不同, 单独列在后面。
final class SearchSnippetTests: XCTestCase {
    private static let table = SearchFoldTable.prepare()

    private func make(_ text: String, _ query: String, table: SearchFoldTable?) -> SearchSnippet? {
        SearchSnippet.make(text: text, query: query, length: 300, lead: 40, table: table)
    }

    /// 两条路径各跑一遍 `check`。
    private func both(_ check: (_ make: (String, String) -> SearchSnippet?, _ path: String) throws -> Void) rethrows {
        try check({ self.make($0, $1, table: Self.table) }, "折叠表")
        try check({ self.make($0, $1, table: nil) }, "旧做法")
    }

    private func highlighted(_ s: SearchSnippet) -> [String] {
        let chars = Array(s.text)
        return s.highlights.map { String(chars[$0]) }
    }

    func testPublicMakeUsesTheSharedTable() {
        _ = Self.table
        XCTAssertNotNil(SearchFoldTable.current)
        XCTAssertEqual(SearchSnippet.make(text: "a\u{2013}b", query: "a-b"), make("a\u{2013}b", "a-b", table: Self.table))
    }

    func testMatchNearStartKeepsWindowAtStart() throws {
        try both { make, path in
            let s = try XCTUnwrap(make("hello world, more text", "world"), path)
            XCTAssertFalse(s.truncatedStart, path)
            XCTAssertTrue(s.text.hasPrefix("hello"), path)
            XCTAssertEqual(highlighted(s), ["world"], path)
        }
    }

    func testDeepMatchMovesWindowToTheMatch() throws {
        let text = String(repeating: "填充文字。", count: 200) + "关键结论在这里" + String(repeating: "后文", count: 300)
        try both { make, path in
            let s = try XCTUnwrap(make(text, "关键结论"), path)
            XCTAssertTrue(s.truncatedStart && s.truncatedEnd, path)
            XCTAssertEqual(s.text.count, 300, path)
            XCTAssertEqual(highlighted(s), ["关键结论"], path)
            XCTAssertEqual(s.highlights.first?.lowerBound, 40, "锚点前保留 40 个字符 (\(path))")
        }
    }

    func testWindowStartsAtLineStartWhenNewlineIsNear() throws {
        let text = String(repeating: "x", count: 500) + "\nline with TARGET inside"
        try both { make, path in
            let s = try XCTUnwrap(make(text, "target"), path)
            XCTAssertTrue(s.text.hasPrefix("line with"), path)
            XCTAssertTrue(s.truncatedStart, path)
        }
    }

    func testHighlightsEveryWordAndEveryOccurrenceInWindow() throws {
        try both { make, path in
            let s = try XCTUnwrap(make("Git status; git push; then status", "git status"), path)
            XCTAssertEqual(highlighted(s), ["Git", "status", "git", "status"], path)
        }
    }

    func testMatchesSameVariantsAsSearch() throws {
        let cases: [(String, String, String)] = [
            ("访问 ｈｔｔｐｓ：／／example", "https://", "ｈｔｔｐｓ：／／"),
            ("in Straße here", "strasse", "Straße"),
            ("range 2020–2024 end", "2020-2024", "2020–2024"),
            ("编号①号", "1", "①"),
            ("颗粒，平面", "颗粒,平面", "颗粒，平面"),
            ("PyThon代码", "python代码", "PyThon代码"),
        ]
        try both { make, path in
            for (text, query, expected) in cases {
                let s = try XCTUnwrap(make(text, query), "\(query) \(path)")
                XCTAssertEqual(highlighted(s), [expected], "\(query) \(path)")
            }
        }
    }

    func testDeepHitsInLongMultibyteText() throws {
        let text = String(repeating: "填充🙂é文字", count: 1_500) + "结论：PyThon代码 在这里"
        try both { make, path in
            for (query, expected) in [("python代码", "PyThon代码"), ("PYTHON", "PyThon"), ("结论", "结论")] {
                let s = try XCTUnwrap(make(text, query), "\(query) \(path)")
                XCTAssertEqual(highlighted(s).first, expected, "\(query) \(path)")
                XCTAssertTrue(s.truncatedStart, "\(query) \(path)")
            }
        }
    }

    func testPunctuationQueryAnchorsOnEarlierFullwidthForm() throws {
        let text = "开头（全角括号）" + String(repeating: "x", count: 2_000) + "(half)"
        try both { make, path in
            let s = try XCTUnwrap(make(text, "("), path)
            XCTAssertFalse(s.truncatedStart, path)
            XCTAssertEqual(highlighted(s).first, "（", path)
        }
    }

    func testOverlappingHitsMerge() throws {
        try both { make, path in XCTAssertEqual(try XCTUnwrap(make("abcdef", "abc cde"), path).highlights, [0..<5], path) }
    }

    func testNoMatchInTextReturnsNil() {
        // 命中在标题/来源 app 等其他字段时, 正文里找不到 → nil, 卡片照常显示开头。
        both { make, path in
            XCTAssertNil(make("body only", "safari"), path)
            XCTAssertNil(make("body", "  "), path)
            XCTAssertNil(make(String(repeating: "a", count: SearchSnippet.scanLimit + 10) + "needle", "needle"), path)
        }
    }

    // MARK: - 只有折叠表能做到的

    func testVariantDeepInTextIsFoundOnlyWithTheTable() throws {
        // 破折号变体 Foundation 不认, 旧做法只逐字符归一化前 5000 字。
        let text = String(repeating: "y", count: SearchSnippet.slowScanLimit + 100) + " 2020–2024"
        XCTAssertEqual(make(text, "2020-2024", table: Self.table).map(highlighted), ["2020–2024"])
        XCTAssertNil(make(text, "2020-2024", table: nil))
    }

    func testHitInsideAnExpandedCharacterHighlightsTheWholeCharacter() throws {
        for (text, query, expected) in [("an ﬃx here", "fix", "ﬃx"), ("第①②号", "12", "①②"), ("a…b", "..", "…"), ("1️⃣ PP", "1", "1️⃣")] {
            let s = try XCTUnwrap(make(text, query, table: Self.table), query)
            XCTAssertEqual(highlighted(s), [expected], query)
        }
    }

    func testTextWithCombiningMarksFallsBackAndStillMatches() throws {
        let text = "cafe\u{301} and more Ｃａｆｅ"
        XCTAssertNil(Self.table.fold(Substring(text)), "组合尖音: 逐字符查表不可靠, 必须退回")
        XCTAssertEqual(make(text, "ｃａｆｅ", table: Self.table), make(text, "ｃａｆｅ", table: nil))
    }
}
