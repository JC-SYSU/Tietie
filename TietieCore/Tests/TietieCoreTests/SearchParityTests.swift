import GRDB
import XCTest
@testable import TietieCore

/// 真实数据对账 (照 tbmail 的验收做法): 在真实库的快照上, 把搜索结果与逐条暴力匹配
/// 逐一比对, 漏的和多的都必须为 0。默认跳过; 用 Scripts/search-parity.sh 运行:
///
///   COPY_PARITY_STORE=live            对 ~/Library/Application Support/Tietie 做快照
///   COPY_PARITY_STORE=<目录或 .sqlite>  对指定库做快照
///   COPY_PARITY_QUERIES=<n>           随机查询条数 (默认 400)
///   COPY_PARITY_REPORT=<路径>          另存 JSON 报告
///
/// 只读打开源库并用 SQLite backup 复制到临时目录, 迁移和查询都在副本上跑, 源库不会被写。
/// 也顺带验证: 迁移 v4 在真实数据上的回填、item_search 每一行都等于按当前规则重算的结果。
final class SearchParityTests: XCTestCase {
    func testSearchMatchesBruteForceOnRealData() throws {
        let env = ProcessInfo.processInfo.environment
        guard let source = env["COPY_PARITY_STORE"], !source.isEmpty else {
            throw XCTSkip("set COPY_PARITY_STORE (see Scripts/search-parity.sh)")
        }
        let queryCount = Int(env["COPY_PARITY_QUERIES"] ?? "") ?? 400
        let dbm = try snapshot(of: sourceURL(source))
        let store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory))

        // 1. 存储的搜索文本 == 按当前规则重算 (触发器/回填没有漏行、没有过期)。
        let items = try dbm.writer.read { try ClipItem.order(Column("lastUsedAt").desc).fetchAll($0) }
        let stored = try dbm.writer.read { db in
            try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT itemId, text FROM item_search")
                .map { (row: Row) -> (Int64, String) in (row["itemId"], row["text"]) })
        }
        // 按 UTF-8 字节比较: 与 SQLite LIKE (以及 tbmail 的 Rust str::contains) 同为码点级。
        // Swift 的 String.contains 按字形簇比较, "1️⃣" 里的 "1" 会被它漏掉。
        var fields: [Int64: [[UInt8]]] = [:]
        var staleRows: [Int64] = []
        for item in items {
            let values = [item.plainText, item.title, item.linkTitle, item.appName, item.recognizedText]
            fields[item.id!] = values.compactMap { $0 }.filter { !$0.isEmpty }.map { Array(SearchText.normalize($0).utf8) }
            if stored[item.id!] != SearchText.joined(values) { staleRows.append(item.id!) }
        }

        // 1b. 命中摘要的折叠表: 每条记录前 scanLimit 个字符折叠后 == SearchText.normalize (按字节)。
        let table = SearchFoldTable.prepare()
        var foldMismatches: [Int64] = [], foldBailed = 0
        for item in items {
            let scope = (item.plainText ?? "").prefix(SearchSnippet.scanLimit)
            guard let folded = table.fold(scope) else { foldBailed += 1; continue }
            if folded.bytes != Array(SearchText.normalize(String(scope)).utf8) { foldMismatches.append(item.id!) }
        }

        // 2. 查询: 从真实文本里抽子串 + 固定探针, 种子固定, 每次运行同一批。
        var rng = SplitMix64(seed: 20_261_105)
        let texts = items.compactMap(\.plainText).filter { $0.count >= 8 }
        var queries = ["a", "的", "1", "/", "%", "_", "\\", "git status", "ｈｔｔｐ", "：", "（", "a–b", "strasse",
                       "zqxjkv", "量子猫咪披萨", "历史", "浙江", "the", "invoice"]
        while queries.count < queryCount, !texts.isEmpty {
            let chars = Array(texts[Int(rng.next() % UInt64(texts.count))])
            let length = 1 + Int(rng.next() % 8)
            let start = Int(rng.next() % UInt64(chars.count - length + 1))
            let piece = String(chars[start..<(start + length)])
            guard !piece.contains(where: \.isWhitespace) else { continue }
            queries.append(rng.next() % 6 == 0 && queries.count > 1 ? piece + " " + queries[queries.count - 1] : piece)
        }

        // 3. 每条查询: 全量结果集 == 暴力结果集; 面板参数 (前 25 + 收藏优先) 的排序与条数正确。
        var mismatches: [[String: Any]] = []
        var latencies: [Double] = []
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id!, $0) })
        var snippetCards = 0, snippetCompared = 0, snippetMismatches: [String] = [], snippetLatencies: [Double] = []
        for query in queries {
            let words = SearchText.words(query).map { Array($0.utf8) }
            let expected = Set(items.lazy.filter { item in
                let haystack = fields[item.id!] ?? []
                return !words.isEmpty && words.allSatisfy { word in haystack.contains { bytesContain($0, word) } }
            }.map { $0.id! })
            let full = Set(try store.search(filter: SearchFilter(text: query), limit: Int.max, favoritesFirst: true).compactMap(\.id))
            let start = DispatchTime.now().uptimeNanoseconds
            let top = try store.search(filter: SearchFilter(text: query), limit: 25, favoritesFirst: true)
            latencies.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)

            let favorites = top.prefix { $0.isFavorite }
            let rest = top.dropFirst(favorites.count)
            let expectedFavorites = expected.filter { byID[$0]!.isFavorite }.count
            let orderOK = rest.allSatisfy { !$0.isFavorite }
                && zip(rest, rest.dropFirst()).allSatisfy { $0.lastUsedAt >= $1.lastUsedAt }
                && favorites.count == expectedFavorites
                && rest.count == min(25, expected.count - expectedFavorites)
                && Set(top.compactMap(\.id)).isSubset(of: expected)
            // 3b. 面板前 25 张卡的命中摘要 == 逐字符归一化对照 (不经折叠表)。
            let snippetStart = DispatchTime.now().uptimeNanoseconds
            let snippets = top.map { SearchSnippet.make(text: $0.plainText ?? "", query: query, length: 300, lead: 40, table: table) }
            snippetLatencies.append(Double(DispatchTime.now().uptimeNanoseconds - snippetStart) / 1e6)
            for (item, snippet) in zip(top, snippets) {
                snippetCards += 1
                let text = item.plainText ?? ""
                // 退回旧做法的卡不在这里比 (旧做法已在改动前逐张核对过)。
                guard table.fold(text.prefix(SearchSnippet.scanLimit + 300)) != nil else { continue }
                snippetCompared += 1
                if snippet != Self.oracleSnippet(text: text, query: query), snippetMismatches.count < 20 {
                    snippetMismatches.append("\(query) #\(item.id!)")
                }
            }

            if full != expected || !orderOK {
                mismatches.append(["query": query, "expected": expected.count, "engine": full.count,
                                   "missing": expected.subtracting(full).count, "extra": full.subtracting(expected).count,
                                   "topOrderOK": orderOK])
            }
        }

        latencies.sort()
        snippetLatencies.sort()
        let report: [String: Any] = [
            "items": items.count, "queries": queries.count,
            "staleSearchRows": staleRows.count, "mismatchedQueries": mismatches.count,
            "foldMismatchItems": foldMismatches.count, "foldBailedItems": foldBailed,
            "snippetCards": snippetCards, "snippetCompared": snippetCompared, "snippetMismatches": snippetMismatches,
            "snippetMsPer25Cards": ["median": snippetLatencies[snippetLatencies.count / 2],
                                    "p90": snippetLatencies[snippetLatencies.count * 9 / 10], "max": snippetLatencies.last!],
            "mismatches": Array(mismatches.prefix(20)),
            "latencyMs": ["median": latencies[latencies.count / 2], "p90": latencies[latencies.count * 9 / 10],
                          "max": latencies.last!],
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print("SEARCH PARITY REPORT\n" + String(decoding: json, as: UTF8.self))
        if let path = env["COPY_PARITY_REPORT"], !path.isEmpty {
            try json.write(to: URL(fileURLWithPath: path))
        }
        XCTAssertEqual(staleRows.count, 0, "item_search 与按当前规则重算的结果不一致: \(staleRows.prefix(10))")
        XCTAssertEqual(mismatches.count, 0, "搜索与暴力结果不一致: \(mismatches.prefix(5))")
        XCTAssertEqual(foldMismatches, [], "折叠表结果与 SearchText.normalize 不一致的条目")
        XCTAssertEqual(snippetMismatches, [], "命中摘要与逐字符对照不一致")
    }

    /// 对照: 逐字符 (Character) 按 SearchText.normalize 归一化后找第一次出现, 取窗规则与
    /// SearchSnippet 相同。不经折叠表, 也没有 5000 字上限。
    static func oracleSnippet(text: String, query: String) -> SearchSnippet? {
        let words = SearchText.words(query).map { Array($0.unicodeScalars) }
        guard !words.isEmpty, !text.isEmpty else { return nil }
        let scope = text.prefix(SearchSnippet.scanLimit)
        let (scalars, owners) = normalizedScalars(scope)
        guard let anchor = words.compactMap({ find($0, in: scalars, from: 0).map { owners[$0] } }).min() else { return nil }
        var start = scope.index(anchor, offsetBy: -40, limitedBy: scope.startIndex) ?? scope.startIndex
        if let newline = scope[start..<anchor].lastIndex(where: \.isNewline) { start = scope.index(after: newline) }
        let end = text.index(start, offsetBy: 300, limitedBy: text.endIndex) ?? text.endIndex
        let window = text[start..<end]
        let (ws, wo) = normalizedScalars(window)
        var ranges: [Range<Int>] = []
        for word in words {
            var k = 0
            while ranges.count < SearchSnippet.maxHighlights, let hit = find(word, in: ws, from: k) {
                let lower = wo[hit], upper = window.index(after: wo[hit + word.count - 1])
                ranges.append(window.distance(from: window.startIndex, to: lower)..<window.distance(from: window.startIndex, to: upper))
                k = wo.firstIndex { $0 >= upper } ?? ws.count
            }
        }
        var merged: [Range<Int>] = []
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let l = merged.last, r.lowerBound <= l.upperBound { merged[merged.count - 1] = l.lowerBound..<max(l.upperBound, r.upperBound) } else { merged.append(r) }
        }
        return SearchSnippet(text: String(window), highlights: merged, truncatedStart: start > text.startIndex, truncatedEnd: end < text.endIndex)
    }

    private static func normalizedScalars(_ s: Substring) -> ([Unicode.Scalar], [String.Index]) {
        var scalars: [Unicode.Scalar] = [], owners: [String.Index] = []
        var i = s.startIndex
        while i < s.endIndex {
            for u in SearchText.normalize(String(s[i])).unicodeScalars { scalars.append(u); owners.append(i) }
            i = s.index(after: i)
        }
        return (scalars, owners)
    }

    private static func find(_ needle: [Unicode.Scalar], in hay: [Unicode.Scalar], from: Int) -> Int? {
        guard !needle.isEmpty, from + needle.count <= hay.count else { return nil }
        for i in from...(hay.count - needle.count) where hay[i] == needle[0] && hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
        return nil
    }

    private func sourceURL(_ value: String) -> URL {
        if value == "live" {
            return AppStorageLocation.supportDirectory.appendingPathComponent("copy.sqlite")
        }
        let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        return url.pathExtension == "sqlite" ? url : url.appendingPathComponent("copy.sqlite")
    }

    /// 只读打开源库, backup 到临时目录, 再用 DatabaseManager 打开副本 (跑迁移)。
    private func snapshot(of source: URL) throws -> DatabaseManager {
        var config = Configuration()
        config.readonly = true
        let reader = try DatabaseQueue(path: source.path, configuration: config)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyParity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = try DatabaseQueue(path: dir.appendingPathComponent("copy.sqlite").path)
        try reader.backup(to: copy)
        try reader.close()
        try copy.close()
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return try DatabaseManager(directory: dir)
    }
}

private func bytesContain(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard needle.count <= haystack.count else { return false }
    return haystack.withUnsafeBytes { h in
        needle.withUnsafeBytes { n in memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil }
    }
}

/// 固定种子的伪随机数, 让每次对账跑同一批查询。
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
