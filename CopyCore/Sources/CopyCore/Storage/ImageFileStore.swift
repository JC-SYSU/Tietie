import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// 图片条目的本体: 每张图片存成一个真正的图片文件 (默认 `~/Library/Copy/Images/`),
/// 拖拽、粘贴时直接把这个文件交出去, 不需要临时导出。
///
/// - 路径里不能有空格: 路径会以纯文本粘进终端。`Application Support` 有空格, 所以单独放。
/// - 文件名 `Copy-<复制时间>-<内容哈希前 6 位>.<扩展名>`, 时间按条目的 `createdAt`,
///   同一条目重复复制 (去重命中) 得到同一个文件名, 已交出去的路径一直有效。
/// - 写入后设为只读 (0444): 在「预览」里打开后直接保存会提示另存, 不会悄悄改掉历史里的
///   原图。删除只要目录可写, 不受影响。
/// - 只存一份: 截图、浏览器复制图片时会同时给 PNG 和 TIFF, 只留 PNG; 只有 TIFF 时转成
///   PNG (很多上传接口不收 TIFF), 转不了才原样存成 .tiff。
public struct ImageFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Copy/Images/`
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Copy", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
    }

    public func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    public func data(for fileName: String) -> Data? {
        try? Data(contentsOf: url(for: fileName))
    }

    public func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    /// 写入 (同名文件已在就直接复用), 返回文件名。先写临时文件再改名, 改名前设只读。
    public func save(_ data: Data, ext: String, capturedAt: Date) throws -> String {
        let name = Self.fileName(for: data, ext: ext, capturedAt: capturedAt)
        let target = url(for: name)
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) { return name }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: temp)
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: temp.path)
        do {
            try fm.moveItem(at: temp, to: target)
        } catch {
            try? fm.removeItem(at: temp)
            // 另一个写入者抢先放好了同名文件 (内容必然相同): 用它即可。
            if fm.fileExists(atPath: target.path) { return name }
            throw error
        }
        return name
    }

    public func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// 目录里所有本 store 写出的文件名 (不含临时文件)。
    public func allFileNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("Copy-") }
    }

    // MARK: 命名与格式

    static func fileName(for data: Data, ext: String, capturedAt: Date) -> String {
        let hash = SHA256.hash(data: data).prefix(3).map { String(format: "%02x", $0) }.joined()
        return "Copy-\(timestampFormatter.string(from: capturedAt))-\(hash).\(ext)"
    }

    /// 固定 UTC: 改了系统时区, 已有条目的文件名也不变。
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// 从一组位图表示里挑出要存的那一份: 有 PNG 用 PNG; 只有 TIFF 时转 PNG, 转不了
    /// 原样留 TIFF; 其他图片格式 (JPEG、GIF…) 原样保留。没有位图返回 nil。
    static func primaryImage(from reps: [CapturedRepresentation]) -> (data: Data, uti: String, ext: String)? {
        if let png = reps.first(where: { $0.uti == UTType.png.identifier }) {
            return (png.data, png.uti, "png")
        }
        if let tiff = reps.first(where: { $0.uti == UTType.tiff.identifier }) {
            if let png = convertToPNG(tiff.data) { return (png, UTType.png.identifier, "png") }
            return (tiff.data, tiff.uti, "tiff")
        }
        for rep in reps {
            guard let type = UTType(rep.uti), type.conforms(to: .image) else { continue }
            return (rep.data, rep.uti, type.preferredFilenameExtension ?? "img")
        }
        return nil
    }

    static func isBitmap(_ uti: String) -> Bool {
        UTType(uti)?.conforms(to: .image) ?? false
    }

    static func convertToPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
