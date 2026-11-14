import XCTest
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import TietieCore

/// 图片条目存成真正的图片文件 (ImageFileStore): 写入、去重、删除、旋转、旧数据搬迁、
/// 孤儿清理, 以及粘贴时带上文件 URL 和路径。
final class ImageFileStoreTests: XCTestCase {
    private var dir: URL!
    private var dbm: DatabaseManager!
    private var store: ItemStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyTests-\(UUID().uuidString)")
        dbm = try DatabaseManager(directory: dir)
        store = ItemStore(writer: dbm.writer, blobs: BlobStore(directory: dbm.blobsDirectory),
                          images: ImageFileStore(directory: dbm.imagesDirectory))
    }

    override func tearDownWithError() throws {
        // 只读文件也能删 (删除看的是目录权限)。
        try? FileManager.default.removeItem(at: dir)
    }

    /// 一张真正能解码的小图片 (纯色), 编码成给定格式。
    private func imageData(_ type: UTType, red: CGFloat = 1) -> Data {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func capture(_ reps: [CapturedRepresentation], hash: Data? = nil) -> CapturedItem {
        CapturedItem(kind: .image, plainText: "Image", hashData: hash ?? reps[0].data,
                     representations: reps, sourceBundleID: "com.test", sourceAppName: "Test")
    }

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dbm.imagesDirectory.path)) ?? [])
            .filter { $0.hasPrefix("Copy-") }.sorted()
    }

    private func blobCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: dbm.blobsDirectory.path).count) ?? 0
    }

    func testPNGAndTIFFCaptureStoresOneReadOnlyPNGFile() throws {
        let png = imageData(.png), tiff = imageData(.tiff)
        let item = try store.save(capture([CapturedRepresentation(uti: "public.png", data: png),
                                           CapturedRepresentation(uti: "public.tiff", data: tiff)]))
        let names = files()
        XCTAssertEqual(names.count, 1)
        let name = try XCTUnwrap(names.first)
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertFalse(dbm.imagesDirectory.path.contains(" "), "粘进终端的路径不能有空格")
        XCTAssertEqual(blobCount(), 0, "TIFF 不再另存")
        let attrs = try FileManager.default.attributesOfItem(atPath: dbm.imagesDirectory.appendingPathComponent(name).path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o444)
        XCTAssertEqual(try store.representations(forItemID: item.id!),
                       [CapturedRepresentation(uti: "public.png", data: png)])
        XCTAssertEqual(item.sizeBytes, png.count)
        XCTAssertEqual(try store.imageFileURL(forItemID: item.id!)?.lastPathComponent, name)
    }

    func testTIFFOnlyCaptureIsConvertedToPNG() throws {
        let tiff = imageData(.tiff)
        let item = try store.save(capture([CapturedRepresentation(uti: "public.tiff", data: tiff)]))
        XCTAssertTrue(try XCTUnwrap(files().first).hasSuffix(".png"))
        let reps = try store.representations(forItemID: item.id!)
        XCTAssertEqual(reps.map(\.uti), ["public.png"])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(reps[0].data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
    }

    func testRecopyReusesTheSameFile() throws {
        let png = imageData(.png)
        let first = try store.save(capture([CapturedRepresentation(uti: "public.png", data: png)]),
                                   now: Date(timeIntervalSince1970: 1_000_000))
        let before = files()
        let again = try store.save(capture([CapturedRepresentation(uti: "public.png", data: png)]),
                                   now: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(files(), before, "去重命中时文件名按 createdAt 取, 已交出去的路径不变")
    }

    func testDeleteAndClearHistoryRemoveFiles() throws {
        let a = try store.save(capture([CapturedRepresentation(uti: "public.png", data: imageData(.png, red: 1))]))
        _ = try store.save(capture([CapturedRepresentation(uti: "public.png", data: imageData(.png, red: 0.5))]))
        XCTAssertEqual(files().count, 2)
        try store.delete(itemID: a.id!)
        XCTAssertEqual(files().count, 1)
        try store.clearHistory(keepFavorites: true)
        XCTAssertEqual(files().count, 0)
    }

    func testRotateReplacesTheFile() throws {
        let item = try store.save(capture([CapturedRepresentation(uti: "public.png", data: imageData(.png, red: 1))]))
        let before = files()
        _ = try store.replaceImageRepresentation(itemID: item.id!, data: imageData(.png, red: 0.2), uti: "public.png")
        let after = files()
        XCTAssertEqual(after.count, 1)
        XCTAssertNotEqual(after, before, "内容变了换新文件, 旧文件删掉")
    }

    func testLegacyBlobImagesMigrateToFiles() throws {
        let png = imageData(.png), tiff = imageData(.tiff)
        let blobs = BlobStore(directory: dbm.blobsDirectory)
        // v6 之前的存法: PNG、TIFF 各一个 blob, 没有 fileName。
        let id: Int64 = try dbm.writer.write { db in
            var item = ClipItem(id: nil, uuid: UUID().uuidString, kind: .image,
                                createdAt: Date(timeIntervalSince1970: 1_700_000_000), lastUsedAt: Date(),
                                plainText: "Image", linkTitle: nil, appBundleID: nil, appName: nil,
                                contentHash: BlobStore.key(for: png), sizeBytes: png.count + tiff.count,
                                isFavorite: false)
            try item.insert(db)
            for (uti, data) in [("public.png", png), ("public.tiff", tiff)] {
                var rep = Representation(id: nil, itemId: item.id!, uti: uti, inlineData: nil,
                                         blobKey: try blobs.store(data))
                try rep.insert(db)
            }
            return item.id!
        }
        XCTAssertEqual(blobCount(), 2)
        XCTAssertEqual(try store.migrateImagesToFiles(), 1)
        XCTAssertEqual(try store.migrateImagesToFiles(), 0, "幂等")
        XCTAssertEqual(blobCount(), 0, "旧 blob 清掉")
        XCTAssertEqual(files().count, 1)
        XCTAssertTrue(try XCTUnwrap(files().first).hasPrefix("Copy-20231114-"), "文件名按条目原本的复制时间")
        XCTAssertEqual(try store.representations(forItemID: id), [CapturedRepresentation(uti: "public.png", data: png)])
        let migrated = try XCTUnwrap(try dbm.writer.read { db in try ClipItem.fetchOne(db, key: id) })
        XCTAssertEqual(migrated.sizeBytes, png.count)
        XCTAssertEqual(migrated.contentHash, BlobStore.key(for: png), "去重键不变")
    }

    func testSweepRemovesUnreferencedFiles() throws {
        _ = try store.save(capture([CapturedRepresentation(uti: "public.png", data: imageData(.png))]))
        let stray = dbm.imagesDirectory.appendingPathComponent("Copy-20200101-000000-abcdef.png")
        try Data([1, 2, 3]).write(to: stray)
        XCTAssertEqual(files().count, 2)
        XCTAssertEqual(try store.sweepOrphanImageFiles(), 1)
        XCTAssertEqual(files().count, 1)
    }

    func testPasteboardRepresentationsCarryFileAndPath() throws {
        let png = imageData(.png)
        let item = try store.save(capture([CapturedRepresentation(uti: "public.png", data: png)]))
        let url = try XCTUnwrap(try store.imageFileURL(forItemID: item.id!))
        let reps = try store.pasteboardRepresentations(forItemID: item.id!)
        XCTAssertEqual(reps.map(\.uti), ["public.png", "public.file-url", "public.utf8-plain-text"], "图片排最前")
        XCTAssertEqual(URL(dataRepresentation: reps[1].data, relativeTo: nil), url)
        XCTAssertEqual(String(data: reps[2].data, encoding: .utf8), url.path)

        // 纯文本粘贴 (⇧↩) 取到的就是完整路径。
        final class Board: PasteboardWriting {
            var written: [CapturedRepresentation] = []
            func write(_ representations: [CapturedRepresentation], marker: String) { written = representations }
        }
        final class Keys: KeyEventPosting { func postCommandV() {} }
        let board = Board()
        PasteService(pasteboard: board, keyPoster: Keys()).place(reps, plainTextOnly: true)
        XCTAssertEqual(board.written.map(\.uti), ["public.utf8-plain-text"])
        XCTAssertEqual(String(data: board.written[0].data, encoding: .utf8), url.path)
    }

    /// 写进真实的 NSPasteboard (用独立命名的剪贴板, 不碰系统剪贴板): 图片、文件 URL、
    /// 路径三种格式都在同一个 item 上, 不会因为带了文件 URL 就只剩文件。
    func testRealPasteboardKeepsImageFileAndPathTogether() throws {
        let png = imageData(.png)
        let item = try store.save(capture([CapturedRepresentation(uti: "public.png", data: png)]))
        let board = NSPasteboard(name: NSPasteboard.Name("CopyTests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.write(try store.pasteboardRepresentations(forItemID: item.id!), marker: CopyPasteboard.selfMarkerType)
        let types = Set((board.pasteboardItems?.first?.types ?? []).map(\.rawValue))
        XCTAssertTrue(types.isSuperset(of: ["public.png", "public.file-url", "public.utf8-plain-text"]), "\(types)")
        XCTAssertEqual(board.data(forType: .png), png)
        let url = try XCTUnwrap(try store.imageFileURL(forItemID: item.id!))
        XCTAssertEqual(board.string(forType: .string), url.path)
        XCTAssertEqual(board.readObjects(forClasses: [NSURL.self]) as? [URL], [url])
    }

    func testNonImageItemsHaveNoFileExtras() throws {
        let text = try store.save(makeText("hello"))
        XCTAssertNil(try store.imageFileURL(forItemID: text.id!))
        XCTAssertEqual(try store.pasteboardRepresentations(forItemID: text.id!),
                       try store.representations(forItemID: text.id!))
        XCTAssertEqual(files().count, 0)
    }
}
