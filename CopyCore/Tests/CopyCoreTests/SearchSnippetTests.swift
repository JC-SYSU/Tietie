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

    // MARK: - 字节查找 (第 1 级)

    func testByteSearchFindsHanAndFoldedASCIIDeepInLongText() throws {
        let filler = String(repeating: "填充🙂é文字", count: 1_500)   // 多字节字符 + emoji, 约 1 万字
        let text = filler + "结论：PyThon代码 在这里"
        for (query, expected) in [("python代码", "PyThon代码"), ("PYTHON", "PyThon"), ("代码", "代码"), ("结论", "结论")] {
            let s = try XCTUnwrap(SearchSnippet.make(text: text, query: query), query)
            XCTAssertEqual(highlighted(s).first, expected, query)
            XCTAssertTrue(s.truncatedStart, query)
        }
    }

    func testByteSearchEligibility() {
        func ok(_ raw: String) -> Bool { SearchSnippet.isByteSearchable(raw: Substring(raw), word: SearchText.normalize(raw)) }
        XCTAssertTrue(ok("Python代码"))
        XCTAssertTrue(ok("2024"))
        XCTAssertTrue(ok("浙江"))
        XCTAssertFalse(ok("（"), "全角标点")
        XCTAssertFalse(ok("("), "半角标点: 原文里常是全角, 交给 Foundation")
        XCTAssertFalse(ok("ＡＢ"), "全角字母")
        XCTAssertFalse(ok("カタカナ"), "假名可能以半角出现")
        XCTAssertFalse(ok("git-status"))
        XCTAssertFalse(ok("école"))
    }

    func testPunctuationQueryStillAnchorsOnEarlierFullwidthForm() throws {
        let text = "开头（全角括号）" + String(repeating: "x", count: 2_000) + "(half)"
        let s = try XCTUnwrap(SearchSnippet.make(text: text, query: "("))
        XCTAssertFalse(s.truncatedStart)
        XCTAssertEqual(highlighted(s).first, "（")
    }

    func testVariantOnlyMatchBeyondVariantLimitShowsNothing() {
        // 取舍: 字节查找适用的词, 变体形式只在第 5000 字之后出现时不再定位 (卡片显示开头)。
        let deep = String(repeating: "y", count: SearchSnippet.variantScanLimit + 100) + " Straße"
        XCTAssertNil(SearchSnippet.make(text: deep, query: "strasse"))
        let near = "Straße " + String(repeating: "y", count: 100)
        XCTAssertEqual(SearchSnippet.make(text: near, query: "strasse").map(highlighted), ["Straße"])
    }

    /// `isVariantFree` 的每个字符都按 SearchText.normalize 实测: 归一化后不会冒出原本没有的
    /// ASCII 字母数字或汉字。依赖的是系统 Unicode 数据, macOS 升级后这个测试会把变化抓出来。
    func testVariantFreeScalarsNeverNormalizeIntoSearchableCharacters() {
        func isTarget(_ s: Unicode.Scalar) -> Bool {
            (s.isASCII && (s.properties.numericType != nil || ("a"..."z").contains(Character(s))))
                || (0x3400...0x9FFF).contains(s.value) || (0x20000...0x3134F).contains(s.value)
        }
        var bad: [String] = []
        for value in UInt32(0)...0x3134F {
            guard let scalar = Unicode.Scalar(value), SearchSnippet.isVariantFree(scalar),
                  scalar.properties.generalCategory != .unassigned else { continue }
            let original = String(Character(scalar))
            let lowered = original.lowercased()
            let normalized = SearchText.normalize(original)
            guard normalized != lowered else { continue }
            let before = Set(lowered.unicodeScalars.filter(isTarget))
            if normalized.unicodeScalars.contains(where: { isTarget($0) && !before.contains($0) }) {
                bad.append(String(format: "U+%04X", value))
            }
        }
        XCTAssertEqual(bad, [], "这些字符会归一化出字母数字或汉字, 不能算 variant-free")
    }

    func testMatchBeyondScanLimitReturnsNil() {
        let text = String(repeating: "a", count: SearchSnippet.scanLimit + 10) + "needle"
        XCTAssertNil(SearchSnippet.make(text: text, query: "needle"))
    }
}
