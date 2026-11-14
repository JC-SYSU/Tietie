import XCTest
@testable import TietieCore

final class AppStorageLocationTests: XCTestCase {
    private var parent: URL!

    override func setUpWithError() throws {
        parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStorageLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: parent)
    }

    private var target: URL {
        parent.appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
    }

    private var legacy: URL {
        parent.appendingPathComponent("Copy", isDirectory: true)
    }

    func testMigratesLegacyDirectoryAndKeepsIt() throws {
        let images = legacy.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: legacy.appendingPathComponent("copy.sqlite"))
        try Data("png".utf8).write(to: images.appendingPathComponent("Copy-1-a.png"))

        AppStorageLocation.migrate(within: parent)

        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent("copy.sqlite")),
            Data("history".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent("Images/Copy-1-a.png")),
            Data("png".utf8)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: legacy.path),
            "旧目录保留,新版本确认正常后由用户清理"
        )
    }

    func testSkipsWhenTargetAlreadyExists() throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy.appendingPathComponent("copy.sqlite"))

        AppStorageLocation.migrate(within: parent)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.appendingPathComponent("copy.sqlite").path),
            "目标目录已存在时整体跳过"
        )
    }

    func testSecondCallDoesNotOverwriteMigratedData() throws {
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: legacy.appendingPathComponent("copy.sqlite"))

        AppStorageLocation.migrate(within: parent)

        try Data("second".utf8).write(to: legacy.appendingPathComponent("copy.sqlite"))
        AppStorageLocation.migrate(within: parent)

        XCTAssertEqual(
            try Data(contentsOf: target.appendingPathComponent("copy.sqlite")),
            Data("first".utf8),
            "第二次调用跳过,已迁移的数据不被旧目录覆盖"
        )
    }
}
