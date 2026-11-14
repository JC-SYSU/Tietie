import XCTest
import GRDB
@testable import TietieCore

final class CaptureRulesStoreTests: XCTestCase {
    private func expiring(_ s: String, after seconds: TimeInterval?) -> CapturedItem {
        var item = makeText(s)
        item.expiresAfter = seconds
        return item
    }

    func testSaveSetsAndRecopyResetsExpiry() throws {
        let store = try makeTempStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = try store.save(expiring("code 123456", after: 300), now: t0)
        XCTAssertEqual(a.expiresAt, t0.addingTimeInterval(300))
        // 规则改了、再复制同一内容时不再命中: 取消限时。
        let b = try store.save(expiring("code 123456", after: nil), now: t0.addingTimeInterval(10))
        XCTAssertEqual(b.id, a.id)
        XCTAssertNil(b.expiresAt)
        XCTAssertNil(try store.nextExpiry())
    }

    func testPurgeDeletesOnlyDueUnprotectedItems() throws {
        let (store, pinboards) = try makeTempStores()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let due = try store.save(expiring("due", after: 60), now: t0)
        let later = try store.save(expiring("later", after: 600), now: t0)
        let fav = try store.save(expiring("fav", after: 60), now: t0)
        let pinned = try store.save(expiring("pinned", after: 60), now: t0)
        let plain = try store.save(makeText("plain"), now: t0)
        try store.setFavorite(itemID: fav.id!, true)
        let board = try pinboards.create(name: "B", symbol: "star", tint: "blue")
        try pinboards.add(itemID: pinned.id!, to: board.id!)
        XCTAssertNil(try store.item(uuid: fav.uuid)?.expiresAt, "收藏时清空到期时间")
        XCTAssertNil(try store.item(uuid: pinned.uuid)?.expiresAt, "放进收藏板时清空到期时间")

        let result = try store.purgeExpired(now: t0.addingTimeInterval(120))
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(result.nextExpiry, t0.addingTimeInterval(600))
        XCTAssertNil(try store.item(uuid: due.uuid))
        for kept in [later, fav, pinned, plain] { XCTAssertNotNil(try store.item(uuid: kept.uuid)) }
    }

    func testRuleCleanupPlanAndApply() throws {
        let (store, pinboards) = try makeTempStores()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let secret = try store.save(makeText("key sk-proj-abcdefghijklmnopqrstuvwxyz0123"), now: now)
        let oldCode = try store.save(makeText("验证码 482913"), now: now.addingTimeInterval(-3600))
        let freshCode = try store.save(makeText("验证码 777111"), now: now.addingTimeInterval(-60))
        let favSecret = try store.save(makeText("sk-ant-api03-zzzzzzzzzzzzzzzzzzzzzzzz"), now: now)
        let pinnedSecret = try store.save(makeText("sk-ant-api03-yyyyyyyyyyyyyyyyyyyyyyyy"), now: now)
        let normal = try store.save(makeText("hello"), now: now)
        try store.setFavorite(itemID: favSecret.id!, true)
        let board = try pinboards.create(name: "B", symbol: "star", tint: "blue")
        try pinboards.add(itemID: pinnedSecret.id!, to: board.id!)

        let plan = try store.planRuleCleanup(.factoryDefault, now: now)
        XCTAssertEqual(plan.scanned, 4, "收藏和收藏板里的不检查")
        XCTAssertEqual(Set(plan.deleteIDs), [secret.id!, oldCode.id!], "过期的验证码直接删")
        XCTAssertEqual(plan.expireAt, [freshCode.id!: now.addingTimeInterval(-60 + 300)])
        XCTAssertEqual(plan.countsByRule[.preset(.secrets)], 1)
        XCTAssertEqual(plan.countsByRule[.preset(.verificationCode)], 2)

        // 算完计划后用户收藏了其中一条: 执行时跳过它。
        try store.setFavorite(itemID: secret.id!, true)
        let result = try store.apply(plan)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(result.expiring, 1)
        XCTAssertNotNil(try store.item(uuid: secret.uuid))
        XCTAssertNil(try store.item(uuid: oldCode.uuid))
        XCTAssertEqual(try store.item(uuid: freshCode.uuid)?.expiresAt, now.addingTimeInterval(240))
        XCTAssertNotNil(try store.item(uuid: normal.uuid))
    }

    func testMigrationAddsExpiresAtIndex() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CopyTests-\(UUID().uuidString)")
        let dbm = try DatabaseManager(directory: dir)
        let columns = try dbm.writer.read { db in try db.columns(in: "item").map(\.name) }
        XCTAssertTrue(columns.contains("expiresAt"))
        let plan = try dbm.writer.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT MIN(expiresAt) FROM item WHERE expiresAt IS NOT NULL")
                .map { $0["detail"] as String }.joined(separator: " ")
        }
        XCTAssertTrue(plan.contains("item_on_expiresAt"), plan)
    }
}

/// 规则接进 `ClipboardMonitor` 后的行为。
final class CaptureRulesMonitorTests: XCTestCase {
    var pasteboard: FakePasteboard!
    var captured: [CapturedItem]!
    var verdicts: [CaptureVerdict]!
    var monitor: ClipboardMonitor!

    private func makeMonitor(_ rules: CaptureRules, app: String = "com.apple.Safari") {
        pasteboard = FakePasteboard()
        captured = []
        verdicts = []
        monitor = ClipboardMonitor(pasteboard: pasteboard, rules: RulesEngine(rules: rules),
                                   frontmostApp: { (app, "App") },
                                   onCapture: { [weak self] in self?.captured.append($0) })
        monitor.onVerdict = { [weak self] in self?.verdicts.append($0) }
    }

    func testDroppedContentIsNotCapturedButReported() {
        var rules = CaptureRules()
        let kw = KeywordRule(pattern: "secret")
        rules.blacklist.keywords = [kw]
        makeMonitor(rules)
        pasteboard.putText("my secret")
        monitor.checkNow()
        pasteboard.putText("hello")
        monitor.checkNow()
        XCTAssertEqual(captured.map(\.plainText), ["hello"])
        XCTAssertEqual(verdicts.map(\.decidedBy), [.blacklistKeyword(kw.id)], "保留的不报")
    }

    func testExpireActionTagsTheCapturedItem() {
        var rules = CaptureRules()
        rules.blacklist.keywords = [KeywordRule(pattern: "otp", action: .expire(minutes: 10))]
        makeMonitor(rules)
        pasteboard.putText("OTP 1234")
        monitor.checkNow()
        XCTAssertEqual(captured.first?.expiresAfter, 600)
    }

    func testUniversalClipboardSkippedOnlyWhenEnabled() {
        var rules = CaptureRules()
        makeMonitor(rules)
        pasteboard.putText("from iPhone", extraTypes: [RulesEngine.remoteClipboardType])
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)

        rules.blacklist.skipUniversalClipboard = true
        monitor.rules = RulesEngine(rules: rules)
        pasteboard.putText("from iPhone again", extraTypes: [RulesEngine.remoteClipboardType])
        monitor.checkNow()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(verdicts.last?.decidedBy, .universalClipboard)
    }

    func testWhitelistAppGatesBeforeReadingContent() {
        var rules = CaptureRules()
        rules.whitelist.enabled = true
        rules.whitelist.apps = ["com.apple.Terminal"]
        makeMonitor(rules, app: "com.apple.Safari")
        pasteboard.putText("x")
        monitor.checkNow()
        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(verdicts.last?.decidedBy, .whitelistApp)
    }

    func testProprietaryConcealedMarkersAreSkipped() {
        makeMonitor(CaptureRules())
        pasteboard.putText("pw", extraTypes: ["com.agilebits.onepassword"])
        monitor.checkNow()
        XCTAssertTrue(captured.isEmpty)
        XCTAssertTrue(verdicts.isEmpty, "固定标记不算用户规则, 不计数")
    }
}
