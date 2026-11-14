import Foundation
import GRDB

public final class DatabaseManager {
    public let writer: any DatabaseWriter
    public let blobsDirectory: URL
    /// 图片文件目录 (见 `ImageFileStore`)。正式库在 `~/Library/Tietie/Images/`, 演示库和
    /// 测试库放在库目录下的 `images/`, 互不干扰。
    public let imagesDirectory: URL

    public static func makeDefault() throws -> DatabaseManager {
        AppStorageLocation.migrateIfNeeded()
        return try DatabaseManager(
            directory: AppStorageLocation.supportDirectory,
            imagesDirectory: AppStorageLocation.imagesDirectory
        )
    }

    public init(directory: URL, imagesDirectory: URL? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        blobsDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        self.imagesDirectory = imagesDirectory ?? directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.add(function: DatabaseFunction(
                ImageFileDetection.sqlFunctionName,
                argumentCount: 1,
                pure: true
            ) { values in
                guard let filenames = String.fromDatabaseValue(values[0]) else { return false }
                return ImageFileDetection.containsImageFile(in: filenames)
            })
            // item_search 的触发器在每条连接上调用它 (见 migration v4)。
            db.add(function: Self.searchTextFunction)
        }
        writer = try DatabasePool(
            path: directory.appendingPathComponent("copy.sqlite").path,
            configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("kind", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull().indexed()
                t.column("plainText", .text)
                t.column("linkTitle", .text)
                t.column("appBundleID", .text)
                t.column("appName", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("sizeBytes", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "representation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("item", onDelete: .cascade).notNull()
                t.column("uti", .text).notNull()
                t.column("inlineData", .blob)
                t.column("blobKey", .text)
            }
            try db.create(table: "pinboard") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("tint", .text).notNull()
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "pinboard_item") { t in
                t.belongsTo("pinboard", onDelete: .cascade).notNull()
                t.belongsTo("item", onDelete: .cascade).notNull()
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.primaryKey(["pinboardId", "itemId"])
            }
            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.tokenizer = .unicode61()
                t.column("plainText")
                t.column("appName")
                t.column("linkTitle")
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "item") { t in
                t.add(column: "title", .text)
                t.add(column: "recognizedText", .text)
            }

            // Rebuild item_fts to also index title and recognizedText. FTS5 external-content
            // tables can't gain columns via ALTER, so drop the synchronized table and its
            // sync triggers, then recreate: `synchronize(withTable:)` re-registers the
            // triggers and GRDB issues an FTS5 'rebuild', repopulating the index from the
            // existing item rows.
            try db.dropFTS5SynchronizationTriggers(forTable: "item_fts")
            try db.drop(table: "item_fts")
            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.tokenizer = .unicode61()
                t.column("plainText")
                t.column("appName")
                t.column("linkTitle")
                t.column("title")
                t.column("recognizedText")
            }
        }
        migrator.registerMigration("v3") { db in
            try db.alter(table: "pinboard") { t in
                t.add(column: "emoji", .text)
            }
        }
        // 归一化搜索文本 (见 SearchText), 放独立表 item_search 而不是 item 的一列:
        // 触发器若 UPDATE item, 会连带触发 GRDB 的 FTS5 同步触发器 (__item_fts_au), 在
        // INSERT 场景下先于 __item_fts_ai 执行时 FTS5 会报 "malformed"。写独立表则 item 上
        // 的触发器互不影响。ItemStore/ArchiveIO 里任何写 item 的路径都不用记得维护它。
        migrator.registerMigration("v4") { db in
            // 迁移也可能跑在不经 DatabaseManager 配置的连接上 (测试直接拿 DatabaseQueue
            // 迁移), 先确保函数已注册; 同名同参数个数重复注册会覆盖, 无副作用。
            db.add(function: Self.searchTextFunction)
            let args = SearchText.fields.map { "NEW.\($0)" }.joined(separator: ", ")
            let changed = SearchText.fields.map { "OLD.\($0) IS NOT NEW.\($0)" }.joined(separator: " OR ")
            let upsert = """
                INSERT INTO item_search(itemId, text) VALUES (NEW.id, \(SearchText.sqlFunctionName)(\(args)))
                ON CONFLICT(itemId) DO UPDATE SET text = excluded.text;
                """
            try db.execute(sql: """
                CREATE TABLE item_search(
                    itemId INTEGER PRIMARY KEY REFERENCES item(id) ON DELETE CASCADE,
                    text TEXT NOT NULL);
                CREATE TRIGGER item_search_ai AFTER INSERT ON item BEGIN \(upsert) END;
                CREATE TRIGGER item_search_au AFTER UPDATE OF \(SearchText.fields.joined(separator: ", ")) ON item
                WHEN \(changed) BEGIN \(upsert) END;
                CREATE TABLE search_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                """)
            try Self.upsertAllSearchText(db)
            try db.execute(sql: "INSERT INTO search_meta(key, value) VALUES ('stamp', ?)",
                           arguments: [SearchText.stamp])
        }
        // 性能 (实测见提交说明):
        // - (isFavorite, lastUsedAt): 搜索和历史浏览都分「收藏段 + 其余段」两条查询。没有它,
        //   收藏段即使一条收藏都没有也要按 lastUsedAt 扫完全表、逐行回表读 isFavorite。
        // - (appBundleID, appName): distinctApps 的 GROUP BY 只读索引, 不回表。
        // - 删掉 item_fts: 搜索早已改走 item_search, 没有代码读它; 但 GRDB 的同步触发器对
        //   item 的每次 UPDATE (touch、设收藏) 都把整段文本删掉重建, 长条目要几十毫秒。
        //   DROP TABLE 会连带删掉 FTS5 的影子表; 释放的页留在文件里供以后复用。
        migrator.registerMigration("v5") { db in
            try db.execute(sql: """
                CREATE INDEX item_on_isFavorite_lastUsedAt ON item(isFavorite, lastUsedAt);
                CREATE INDEX item_on_appBundleID_appName ON item(appBundleID, appName);
                """)
            try db.dropFTS5SynchronizationTriggers(forTable: "item_fts")
            try db.drop(table: "item_fts")
        }
        // v6: 图片存成真正的图片文件 (ImageFileStore), representation 记文件名。已有图片条目
        // 的数据搬迁要读写文件、可能转码, 不在 SQL 迁移里做, 由 ItemStore.migrateImagesToFiles()
        // 在 app 启动时完成 (幂等)。
        migrator.registerMigration("v6") { db in
            try db.alter(table: "representation") { t in
                t.add(column: "fileName", .text)
            }
        }
        // v7: 捕获规则的「限时保留」。部分索引只收有到期时间的行, 平时几乎是空的。
        migrator.registerMigration("v7") { db in
            try db.alter(table: "item") { t in
                t.add(column: "expiresAt", .datetime)
            }
            try db.execute(sql: "CREATE INDEX item_on_expiresAt ON item(expiresAt) WHERE expiresAt IS NOT NULL")
        }
        return migrator
    }

    /// `SearchText.sqlFunctionName`: 五个字段 → 归一化后的搜索文本。
    static let searchTextFunction = DatabaseFunction(
        SearchText.sqlFunctionName,
        argumentCount: SearchText.fields.count,
        pure: true
    ) { values in
        SearchText.joined(values.map { String.fromDatabaseValue($0) })
    }

    /// 按当前规则重算全部行的搜索文本: 缺的补上, 变了的改写, 没变的不动。返回写入行数。
    @discardableResult
    static func upsertAllSearchText(_ db: Database) throws -> Int {
        let call = "\(SearchText.sqlFunctionName)(\(SearchText.fields.joined(separator: ", ")))"
        // `WHERE true` 是 SQLite 对 INSERT…SELECT…ON CONFLICT 的语法要求 (消除 ON 的歧义)。
        try db.execute(sql: """
            INSERT INTO item_search(itemId, text) SELECT id, \(call) FROM item WHERE true
            ON CONFLICT(itemId) DO UPDATE SET text = excluded.text WHERE item_search.text IS NOT excluded.text
            """)
        return db.changesCount
    }

    /// 版本戳与当前不一致 (改了归一化规则, 或 macOS 升级可能改变 Unicode 数据) 时重算
    /// 搜索文本, 只改写结果真的变了的行。在 app 的持久化队列上调用, 与捕获写入串行;
    /// 一次事务, 中途退出就保持旧戳, 下次启动重来。返回改写的行数, 无需重算时为 0。
    @discardableResult
    public func refreshSearchTextIfNeeded() throws -> Int {
        try writer.write { db in
            let stored = try String.fetchOne(db, sql: "SELECT value FROM search_meta WHERE key = 'stamp'")
            guard stored != SearchText.stamp else { return 0 }
            let changed = try Self.upsertAllSearchText(db)
            try db.execute(sql: "INSERT OR REPLACE INTO search_meta(key, value) VALUES ('stamp', ?)",
                           arguments: [SearchText.stamp])
            return changed
        }
    }
}
