import Foundation

/// 从上游 bundle id 的偏好域一次性搬来设置。
///
/// 改名后 `UserDefaults.standard` 指向新 bundle id,旧域不会自动跟随。快捷键
/// (KeyboardShortcuts)、捕获规则、外观设置都存在旧域里,首次启动搬一次。
enum LegacyDefaultsMigration {
    private static let legacyDomain = "com.tarikbc.Copy"
    private static let marker = "didMigrateLegacyDefaults"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: marker) == nil else { return }

        let values = legacyValues()
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: marker)
    }

    private static func legacyValues() -> [String: Any] {
        if let suite = UserDefaults(suiteName: legacyDomain),
           let values = suite.persistentDomain(forName: legacyDomain) {
            return values
        }
        // cfprefsd 还没把旧 app 的写入刷到磁盘时,直接读 plist 兜底。
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(legacyDomain).plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any] else { return [:] }
        return values
    }
}
