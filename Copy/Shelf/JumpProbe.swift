import Foundation

/// 诊断探针: 直写 /tmp 文件, 绕开统一日志的捕获不确定性 (调查滚动跳变临时用, 定位后移除)。
enum JumpProbe {
    private static let path = "/tmp/copyjump-probe.log"

    static func log(_ message: String) {
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, message)
        if let fh = FileHandle(forWritingAtPath: path) {
            defer { try? fh.close() }
            try? fh.seekToEnd()
            if let data = line.data(using: .utf8) { fh.write(data) }
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
        }
    }
}
