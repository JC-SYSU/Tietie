import Foundation
import os

/// 应用在磁盘上的位置标识。产品改名时只改 `directoryName` 一处。
///
/// 两个正式存储都从这里派生:
/// - `~/Library/<name>/Images/` —— 图片条目本体
/// - `~/Library/Application Support/<name>/copy.sqlite` —— 剪贴板历史
///
/// 目录名保持 ASCII 且不含空格:图片路径会以纯文本粘进终端。
public enum AppStorageLocation {
    /// 与产品名一致。改名只改这一行。
    public static let directoryName = "Tietie"

    /// 上一个产品名。首次启动时把它的目录整体复制到 `directoryName` 下。
    private static let legacyDirectoryNames = ["Copy"]

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Tietie",
        category: "storage"
    )

    /// `~/Library/Application Support/<name>/`
    public static var supportDirectory: URL {
        root(.applicationSupportDirectory)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// `~/Library/<name>/Images/`
    public static var imagesDirectory: URL {
        root(.libraryDirectory)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
    }

    /// 把旧名字的目录复制到新名字下。新目录已存在就跳过,所以每次启动都能调用。
    ///
    /// 数据库目录和图片目录分别判断。整份复制先写到目标同级的临时目录,成功后再改名
    /// 到目标位置:中途失败时目标目录保持不存在,下次启动重新尝试,旧数据原样留在
    /// 原处。旧目录保留不删,用户确认新版本正常后可以自行清理。
    public static func migrateIfNeeded() {
        migrate(within: root(.libraryDirectory))
        migrate(within: root(.applicationSupportDirectory))
    }

    private static func root(_ directory: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: directory, in: .userDomainMask)[0]
    }

    /// 在 `parent` 下完成一次迁移。正式入口是 `migrateIfNeeded()`;测试用 `@testable`
    /// 直接调用它,好在临时目录里验证复制、保留旧目录和幂等。
    static func migrate(within parent: URL) {
        let fm = FileManager.default
        let target = parent.appendingPathComponent(directoryName, isDirectory: true)
        guard !fm.fileExists(atPath: target.path) else { return }

        for legacyName in legacyDirectoryNames {
            let legacy = parent.appendingPathComponent(legacyName, isDirectory: true)
            guard fm.fileExists(atPath: legacy.path) else { continue }

            let staging = parent.appendingPathComponent(
                ".\(directoryName).migrating-\(UUID().uuidString)",
                isDirectory: true
            )
            do {
                try fm.copyItem(at: legacy, to: staging)
                try fm.moveItem(at: staging, to: target)
                log.notice("migrated \(legacyName, privacy: .public) storage into \(directoryName, privacy: .public)")
                return
            } catch {
                try? fm.removeItem(at: staging)
                log.error("storage migration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
