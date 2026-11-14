import XCTest
@testable import TietieCore

/// 折叠表必须与 SearchText.normalize 逐字节一致。表是用系统的 Unicode 数据现算的, macOS 升级
/// 改变了归一化结果时表会跟着变; 这里检查的是「逐码点查表 == 整段归一化」这个前提本身没被打破
/// (例如新增了会和相邻字符合成的码点, 需要补进 isComposingRange)。
final class SearchFoldTests: XCTestCase {
    private static let table = SearchFoldTable.prepare()

    /// 不退回的码点 (BMP 全部 + 核对过的补充平面区)。
    private static let foldable: [Unicode.Scalar] = {
        let ranges: [ClosedRange<UInt32>] = [0x00...0xD7FF, 0xE000...0xFFFF] + SearchFoldTable.checkedSupplementary
        return ranges.flatMap { $0 }.compactMap { v in
            guard let s = Unicode.Scalar(v), table.entry(v) != .bail else { return nil }
            return s
        }
    }()

    private func assertFoldEqualsNormalize(_ text: String, _ label: @autoclosure () -> String, failures: inout [String]) {
        guard let folded = Self.table.fold(Substring(text)) else { failures.append("退回: " + label()); return }
        if folded.bytes != Array(SearchText.normalize(text).utf8) { failures.append("不一致: " + label()) }
    }

    /// 每个不退回的码点夹在各种基字符之间整段归一化, 与逐码点查表的结果比较; 同时覆盖
    /// 码点与基字符、码点与码点相邻的情况。
    func testFoldEqualsNormalizeForEveryFoldableScalarNextToCommonCharacters() {
        let bases = ["a", "E", "1", "-", " ", "\n", "中", "か", "カ", "가", "σ", "Σ", "ß", "（", "…"]
        var failures: [String] = []
        let all = Self.foldable
        for start in stride(from: 0, to: all.count, by: 64) {
            let chunk = all[start..<min(start + 64, all.count)]
            for base in bases {
                var text = base
                for s in chunk { text.unicodeScalars.append(s); text += base }
                assertFoldEqualsNormalize(text, String(format: "基字符 %@ 起于 U+%04X", base, chunk.first!.value), failures: &failures)
            }
            assertFoldEqualsNormalize(String(String.UnicodeScalarView(chunk)), String(format: "连续 起于 U+%04X", chunk.first!.value), failures: &failures)
            if failures.count > 10 { break }
        }
        XCTAssertEqual(failures, [])
    }

    func testHanExtensionRangesAreUnchangedByNormalize() {
        var failures: [String] = []
        for range in SearchFoldTable.identityHanSupplementary {
            for start in stride(from: range.lowerBound, through: range.upperBound, by: 512) {
                let end = min(start + 511, range.upperBound)
                let text = String(String.UnicodeScalarView((start...end).compactMap(Unicode.Scalar.init)))
                if !SearchText.normalize(text).utf8.elementsEqual(text.utf8) { failures.append(String(format: "U+%05X", start)) }
            }
        }
        XCTAssertEqual(failures, [])
        XCTAssertEqual(Self.table.entry(0x20000), .identity)
        XCTAssertEqual(Self.table.entry(0x2F800), .fold(Array(SearchText.normalize("\u{2F800}").utf8)), "兼容汉字补充不能当作不变, 要逐个查")
    }

    func testCharactersThatComposeWithNeighboursBail() {
        for text in ["e\u{301}", "\u{1100}\u{1161}", "가\u{11A8}", "ｶﾞ", "क\u{93F}", "\u{3131}"] {
            XCTAssertNil(Self.table.fold(Substring(text)), text.debugDescription)
        }
        // Foundation 把切罗基大写转成小写, Unicode 的 changesWhenNFKCCaseFolded 却说它不变: 表必须照 normalize 实算。
        XCTAssertFalse(Unicode.Scalar(0x13A0)!.properties.changesWhenNFKCCaseFolded)
        XCTAssertEqual(Self.table.entry(0x13A0), .fold(Array(SearchText.normalize("\u{13A0}").utf8)))
    }

    func testMappingBackToRawOffsets() throws {
        let text = "Aﬃ①b"   // A(1) ﬃ(3 字节→"ffi") ①(3 字节→"1") b(1)
        let f = try XCTUnwrap(Self.table.fold(Substring(text)))
        XCTAssertEqual(String(decoding: f.bytes, as: UTF8.self), "affi1b")
        XCTAssertEqual(f.rawStart(0), 0)
        XCTAssertEqual(f.rawStart(2), 1, "ffi 中间的字节映射到 ﬃ 的起点")
        XCTAssertEqual(f.rawEnd(lastByte: 3), 4, "ffi 最后一个字节所在原文字符结束于 ﬃ 之后")
        XCTAssertEqual(f.rawStart(4), 4)
        XCTAssertEqual(f.rawStart(5), 7)
        XCTAssertEqual(f.folded(forRaw: 4), 4)
        XCTAssertEqual(f.folded(forRaw: 7), 5)
    }

    func testPrepareReturnsTheSameSharedTable() {
        XCTAssertTrue(SearchFoldTable.prepare() === SearchFoldTable.prepare())
        XCTAssertTrue(SearchFoldTable.current === Self.table)
    }
}
