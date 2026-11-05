import GRDB
import XCTest
@testable import CopyCore

/// 归一化契约 (SearchText, 照 tbmail textnorm) + item_search 的维护: 触发器、迁移回填、
/// 版本戳刷新。
final class SearchTextTests: XCTestCase {
    // MARK: - normalize: 期望值取自 tbmail norm.rs 单测与 Python NFKC+casefold

    func testNormalizeMatchesTbmailRules() {
        let cases: [(String, String)] = [
            ("Hello WORLD", "hello world"),
            ("Straße", "strasse"),
            ("ẞ", "ss"),
            ("ＡＢＣ１２３", "abc123"),
            ("ｈｔｔｐｓ：／／", "https://"),
            ("中文，测试：（甲）", "中文,测试:(甲)"),
            ("a\u{2212}b", "a-b"),          // 减号
            ("a\u{2013}b", "a-b"),          // en dash
            ("a\u{2014}b", "a-b"),          // em dash
            ("ﬁle ﬃ", "file ffi"),          // 连字
            ("①㎏", "1kg"),
            ("ｶﾀｶﾅ", "カタカナ"),             // 半角片假名
            ("ΣΑΣ", "σασ"),
            ("ᾈ", "ἀι"),
            ("机械取栓", "机械取栓"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(SearchText.normalize(input), expected, input)
        }
    }

    func testAccentsAreNotFolded() {
        // 与 tbmail 一致: 不去重音, café 与 cafe 是不同的词。
        XCTAssertEqual(SearchText.normalize("Café"), "café")
    }

    func testWordsSplitOnWhitespaceThenNormalize() {
        XCTAssertEqual(SearchText.words("  Ｇｉｔ\u{3000}STATUS\t中文 "), ["git", "status", "中文"])
        XCTAssertEqual(SearchText.words(" \n "), [])
    }

    // MARK: - 搜索: 半角/全角、破折号、大小写折叠都能互相命中

    func testFullwidthAndHalfwidthMatchEachOther() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("访问 ｈｔｔｐｓ：／／example.com 获取"))
        _ = try store.save(makeText("颗粒，平面"))
        XCTAssertEqual(try store.search("https://example").count, 1)
        XCTAssertEqual(try store.search("ＨＴＴＰＳ").count, 1)
        XCTAssertEqual(try store.search("颗粒,平面").count, 1, "半角逗号搜全角逗号原文")
        XCTAssertEqual(try store.search("颗粒，平面").count, 1)
    }

    func testDashVariantsAndCaseFoldingMatch() throws {
        let store = try makeTempStore()
        _ = try store.save(makeText("range 2020–2024 in Straße"))
        _ = try store.save(makeText("ÉCOLE normale"))
        XCTAssertEqual(try store.search("2020-2024").count, 1)
        XCTAssertEqual(try store.search("strasse").count, 1)
        XCTAssertEqual(try store.search("école").count, 1)
        XCTAssertEqual(try store.search("ecole").count, 0, "不去重音")
    }

    // MARK: - item_search 由触发器维护

    private func makeManager() throws -> (DatabaseManager, ItemStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        return (dbm, ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory)))
    }

    private func searchText(_ dbm: DatabaseManager, _ id: Int64) throws -> String? {
        try dbm.writer.read { try String.fetchOne($0, sql: "SELECT text FROM item_search WHERE itemId = ?", arguments: [id]) }
    }

    func testEveryWritePathKeepsSearchTextCurrent() throws {
        let (dbm, store) = try makeManager()
        let item = try store.save(makeText("Ｆｉｒｓｔ", bundle: "com.test.safari", app: "Safari"))
        let id = try XCTUnwrap(item.id)
        XCTAssertEqual(try searchText(dbm, id), "first\nsafari")

        try store.setTitle(itemID: id, "标题：一")
        XCTAssertEqual(try searchText(dbm, id), "first\n标题:一\nsafari")

        try store.setLinkTitle(itemID: id, "Link")
        try store.setRecognizedText(itemID: id, "ＯＣＲ")
        XCTAssertEqual(try searchText(dbm, id), "first\n标题:一\nlink\nsafari\nocr")

        _ = try store.replaceContent(itemID: id, with: "Second")
        XCTAssertEqual(try store.search("second").map(\.id), [id])
        XCTAssertEqual(try store.search("first").count, 0)

        let created = try store.createTextItem("新建 ＡＢ", title: nil)
        XCTAssertEqual(try store.search("新建 ab").map(\.id), [created.id])
    }

    func testTouchAndFavoriteLeaveSearchTextAlone() throws {
        let (dbm, store) = try makeManager()
        let id = try XCTUnwrap(try store.save(makeText("stay")).id)
        let before = try searchText(dbm, id)
        try store.touch(itemID: id)
        try store.setFavorite(itemID: id, true)
        XCTAssertEqual(try searchText(dbm, id), before)
    }

    func testDeleteAndClearRemoveSearchRows() throws {
        let (dbm, store) = try makeManager()
        let a = try XCTUnwrap(try store.save(makeText("one")).id)
        _ = try store.save(makeText("two"))
        try store.delete(itemID: a)
        XCTAssertNil(try searchText(dbm, a))
        try store.clearHistory(keepFavorites: false)
        XCTAssertEqual(try dbm.writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM item_search") }, 0)
    }

    func testImportedArchiveIsSearchable() throws {
        let store = try makeTempStore()
        let id = try XCTUnwrap(try store.save(makeText("归档：ＡＢＣ")).id)
        let snapshot = try store.archivedSnapshot(itemID: id)
        try store.delete(itemID: id)
        XCTAssertTrue(try store.importArchived(snapshot))
        XCTAssertEqual(try store.search("归档:abc").count, 1)
    }

    // MARK: - 迁移回填与版本戳

    func testV4MigrationBackfillsExistingRows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let writer = try DatabasePool(path: dir.appendingPathComponent("copy.sqlite").path)
        try DatabaseManager.migrator.migrate(writer, upTo: "v3")
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO item (uuid, kind, createdAt, lastUsedAt, plainText, appName, contentHash, sizeBytes, isFavorite)
                VALUES ('u1', 'text', ?, ?, 'Ｏｌｄ　Ｒｏｗ', 'Notes', 'h1', 1, 0)
                """, arguments: [Date(), Date()])
        }
        try DatabaseManager.migrator.migrate(writer)
        try writer.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT text FROM item_search"), "old row\nnotes")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT value FROM search_meta WHERE key = 'stamp'"), SearchText.stamp)
        }
    }

    func testRefreshRecomputesOnlyWhenStampChanges() throws {
        let (dbm, store) = try makeManager()
        let id = try XCTUnwrap(try store.save(makeText("Ｒｅｆｒｅｓｈ")).id)
        XCTAssertEqual(try dbm.refreshSearchTextIfNeeded(), 0, "迁移刚写过戳, 无需重算")

        // 模拟旧规则留下的结果 + 旧戳 (如 macOS 升级前写入)。
        try dbm.writer.write { db in
            try db.execute(sql: "UPDATE item_search SET text = 'stale' WHERE itemId = ?", arguments: [id])
            try db.execute(sql: "UPDATE search_meta SET value = 'rules=0;os=old' WHERE key = 'stamp'")
        }
        XCTAssertEqual(try store.search("refresh").count, 0)
        XCTAssertEqual(try dbm.refreshSearchTextIfNeeded(), 1, "只改写结果变了的那一行")
        XCTAssertEqual(try store.search("refresh").count, 1)
        XCTAssertEqual(try dbm.refreshSearchTextIfNeeded(), 0, "戳已更新, 再次调用不做事")
    }

    func testRefreshRestoresMissingRows() throws {
        let (dbm, store) = try makeManager()
        let id = try XCTUnwrap(try store.save(makeText("heal me")).id)
        try dbm.writer.write { db in
            try db.execute(sql: "DELETE FROM item_search WHERE itemId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM search_meta")
        }
        XCTAssertEqual(try dbm.refreshSearchTextIfNeeded(), 1)
        XCTAssertEqual(try store.search("heal").count, 1)
    }
}

final class SearchTextStampTests: XCTestCase {
    func testStampIsLocaleIndependent() {
        // 形如 rules=1;os=26.7.0(25G229): 只含数字版本和 build 号, 不含本地化文字。
        let stamp = SearchText.stamp
        XCTAssertTrue(stamp.hasPrefix("rules=\(SearchText.rulesVersion);os="), stamp)
        XCTAssertNil(stamp.range(of: "[^A-Za-z0-9=;.()]", options: .regularExpression), stamp)
        XCTAssertFalse(stamp.contains("(?)"), stamp)
    }
}

/// 迁移 v5: 两个性能索引 + 删除不再使用的 item_fts。
final class SearchIndexMigrationTests: XCTestCase {
    private func manager() throws -> (DatabaseManager, ItemStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        return (dbm, ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory)))
    }

    func testItemFTSAndItsTriggersAreGone() throws {
        let (dbm, _) = try manager()
        try dbm.writer.read { db in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE name LIKE '%item_fts%'")
            XCTAssertEqual(names, [])
        }
    }

    /// 计划断言: 防止索引被误删或 SQLite 规划器改走全表扫描时性能悄悄退回去。
    func testFavoriteSplitQueriesUseTheCompositeIndex() throws {
        let (dbm, _) = try manager()
        try dbm.writer.read { db in
            for sql in [
                "SELECT item.* FROM item JOIN item_search ON item_search.itemId = item.id WHERE item_search.text LIKE '%a%' AND item.isFavorite = 1 ORDER BY item.lastUsedAt DESC",
                "SELECT * FROM item WHERE isFavorite = 0 ORDER BY lastUsedAt DESC LIMIT 25",
            ] {
                let plan = try String.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql, adapter: SuffixRowAdapter(fromIndex: 3)).joined(separator: " | ")
                XCTAssertTrue(plan.contains("item_on_isFavorite_lastUsedAt"), plan)
            }
            let apps = try String.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN SELECT appBundleID, appName, COUNT(*), max(id) FROM item
                WHERE appBundleID IS NOT NULL AND appBundleID <> '' GROUP BY appBundleID
                """, adapter: SuffixRowAdapter(fromIndex: 3)).joined(separator: " | ")
            XCTAssertTrue(apps.contains("COVERING INDEX item_on_appBundleID_appName"), apps)
        }
    }

    func testTouchAndFavoriteStillWorkWithoutFTS() throws {
        let (_, store) = try manager()
        let id = try XCTUnwrap(try store.save(makeText("still searchable")).id)
        try store.touch(itemID: id)
        try store.setFavorite(itemID: id, true)
        XCTAssertEqual(try store.search("searchable").map(\.isFavorite), [true])
        try store.delete(itemID: id)
        XCTAssertEqual(try store.search("searchable").count, 0)
    }

    func testDistinctAppsUsesTheMostRecentNameForABundle() throws {
        let (_, store) = try manager()
        _ = try store.save(makeText("one", bundle: "com.openai.codex", app: "Codex"))
        _ = try store.save(makeText("two", bundle: "com.openai.codex", app: "ChatGPT"))
        _ = try store.save(makeText("three", bundle: "com.openai.codex", app: "ChatGPT"))
        let apps = try store.distinctApps()
        XCTAssertEqual(apps.map(\.name), ["ChatGPT"])
        XCTAssertEqual(apps.map(\.count), [3])
    }
}
