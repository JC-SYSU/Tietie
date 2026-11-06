import Foundation
import GRDB

/// 用当前规则清理已有历史的计划: 先算出来给用户确认, 确认后再 `ItemStore.apply`。
public struct RuleCleanupPlan: Sendable {
    /// 要删的条目 (规则判定不保存, 或限时保留已经到期)。
    public var deleteIDs: [Int64] = []
    /// 要设到期时间的条目 (限时保留、还没到期)。
    public var expireAt: [Int64: Date] = [:]
    /// 每条规则 (决定结果的那条) 涉及多少条目。
    public var countsByRule: [RuleRef: Int] = [:]
    public var scanned = 0

    public var isEmpty: Bool { deleteIDs.isEmpty && expireAt.isEmpty }
}

extension ItemStore {
    /// 删除到期的「限时保留」条目, 返回删除条数和下一条的到期时间 (没有则 nil)。
    /// 收藏和收藏板里的条目不删 (正常情况下它们的到期时间已被清空, 这里再挡一次)。
    @discardableResult
    public func purgeExpired(now: Date = Date()) throws -> (deleted: Int, nextExpiry: Date?) {
        try writer.write { db in
            let keep = "isFavorite = 0 AND id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)"
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM item WHERE expiresAt IS NOT NULL AND expiresAt <= ? AND \(keep)",
                                         arguments: [now])
            if !ids.isEmpty {
                try deleteItems(ClipItem.filter(ids.contains(Column("id"))), in: db)
            }
            let next = try Date.fetchOne(db, sql: "SELECT MIN(expiresAt) FROM item WHERE expiresAt IS NOT NULL AND \(keep)")
            return (ids.count, next)
        }
    }

    /// 最近一条「限时保留」的到期时间。
    public func nextExpiry() throws -> Date? {
        try writer.read { db in
            try Date.fetchOne(db, sql: """
                SELECT MIN(expiresAt) FROM item WHERE expiresAt IS NOT NULL AND isFavorite = 0
                AND id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)
                """)
        }
    }

    /// 按当前规则检查历史 (收藏和收藏板里的条目不检查), 只读, 返回清理计划。
    /// 通用剪贴板一项查不了: 库里没记录条目是不是接力过来的。
    public func planRuleCleanup(_ rules: CaptureRules, now: Date = Date()) throws -> RuleCleanupPlan {
        let evaluator = CaptureEvaluator(rules: rules)
        let imagesDir = imagesDirectory
        let rows = try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT item.id, item.kind, item.plainText, item.appBundleID, item.sizeBytes, item.lastUsedAt,
                       (SELECT fileName FROM representation r WHERE r.itemId = item.id AND r.fileName IS NOT NULL LIMIT 1) AS fileName
                FROM item
                WHERE item.isFavorite = 0 AND item.id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)
                """)
        }
        var plan = RuleCleanupPlan()
        for row in rows {
            guard let kind = ItemKind(rawValue: row["kind"]) else { continue }
            plan.scanned += 1
            var subject = RuleSubject(kind: kind, text: kind == .image ? nil : row["plainText"],
                                      sourceBundleID: row["appBundleID"])
            if kind == .image {
                let fileName: String? = row["fileName"]
                subject.image = fileName.map { .file(imagesDir.appendingPathComponent($0)) }
                subject.imageBytes = row["sizeBytes"]
            }
            let verdict = evaluator.evaluate(subject, budget: 0.2)
            let id: Int64 = row["id"]
            switch verdict.outcome {
            case .keep: continue
            case .drop:
                plan.deleteIDs.append(id)
            case .expire(let minutes):
                let due = (row["lastUsedAt"] as Date).addingTimeInterval(TimeInterval(minutes * 60))
                if due <= now { plan.deleteIDs.append(id) } else { plan.expireAt[id] = due }
            }
            if let rule = verdict.decidedBy { plan.countsByRule[rule, default: 0] += 1 }
        }
        return plan
    }

    /// 执行清理计划。执行时再确认一次条目没被收藏、没进收藏板 (算计划之后用户可能改过)。
    /// 返回实际删除和设了到期时间的条数。
    @discardableResult
    public func apply(_ plan: RuleCleanupPlan) throws -> (deleted: Int, expiring: Int) {
        try writer.write { db in
            let keep = "isFavorite = 0 AND id NOT IN (SELECT DISTINCT itemId FROM pinboard_item)"
            var deleted = 0
            for chunk in stride(from: 0, to: plan.deleteIDs.count, by: Self.deleteChunkSize).map({
                Array(plan.deleteIDs[$0..<min($0 + Self.deleteChunkSize, plan.deleteIDs.count)])
            }) {
                let ids = try Int64.fetchAll(db, ClipItem.filter(chunk.contains(Column("id")))
                    .filter(sql: keep).select(Column("id")))
                try deleteItems(ClipItem.filter(ids.contains(Column("id"))), in: db)
                deleted += ids.count
            }
            var expiring = 0
            for (id, due) in plan.expireAt {
                try db.execute(sql: "UPDATE item SET expiresAt = ? WHERE id = ? AND \(keep)", arguments: [due, id])
                expiring += db.changesCount
            }
            return (deleted, expiring)
        }
    }
}
