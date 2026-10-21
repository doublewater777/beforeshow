import Foundation

// MARK: - Live Activity & Notification Handover Policy (Issue #362)
// 规则：
// 1. 每个事件默认由本地通知主动提醒。
// 2. 只有活动可远程更新、服务端已接受该计划版本、对应本地待发请求已撤除且交接完成的未来事件，才能转由实时活动负责。
// 3. App 前台带提醒更新与服务端 APNs alert 共享同一个生产使用的事件消费入口，以并发安全方式限制同一事件只有一次主动提醒发起。
// 4. 首次安排已错过触发点或事件已开演时不补响。

enum ReminderDeliveryChannel: String, Codable, Equatable, Sendable {
    case localNotification
    case liveActivity
}

enum HandoverStatus: String, Codable, Equatable, Sendable {
    case pending
    case handedOver
    case consumed
    case revoked
}

struct PerformanceReminderEventKey: Hashable, Codable, Sendable {
    let showID: String
    let performanceID: String
    let milestone: String
    let scheduledStartsAt: Date

    init(showID: String, performanceID: String, milestone: String = "interestedPerformance", scheduledStartsAt: Date) {
        self.showID = showID
        self.performanceID = performanceID
        self.milestone = milestone
        self.scheduledStartsAt = scheduledStartsAt
    }

    var stableIdentifier: String {
        "\(showID).\(milestone).\(performanceID).\(Int(scheduledStartsAt.timeIntervalSince1970))"
    }

    var notificationIdentifier: String {
        "\(showID).\(milestone).\(performanceID)"
    }
}

struct PerformanceReminderRecord: Codable, Equatable, Sendable {
    let eventKey: PerformanceReminderEventKey
    var channel: ReminderDeliveryChannel
    var status: HandoverStatus
    var planVersion: Int?
    var consumedAt: Date?

    init(
        eventKey: PerformanceReminderEventKey,
        channel: ReminderDeliveryChannel = .localNotification,
        status: HandoverStatus = .pending,
        planVersion: Int? = nil,
        consumedAt: Date? = nil
    ) {
        self.eventKey = eventKey
        self.channel = channel
        self.status = status
        self.planVersion = planVersion
        self.consumedAt = consumedAt
    }
}

/// 并发安全的主动提醒消费仲裁器
actor LiveActivityReminderLedger {
    static let shared = LiveActivityReminderLedger()

    private var records: [String: PerformanceReminderRecord] = [:]

    init(initialRecords: [PerformanceReminderRecord] = []) {
        for record in initialRecords {
            records[record.eventKey.stableIdentifier] = record
        }
    }

    /// 查询或初始化记录（默认走 localNotification）
    func record(for eventKey: PerformanceReminderEventKey) -> PerformanceReminderRecord {
        if let existing = records[eventKey.stableIdentifier] {
            return existing
        }
        let fresh = PerformanceReminderRecord(eventKey: eventKey, channel: .localNotification, status: .pending)
        records[eventKey.stableIdentifier] = fresh
        return fresh
    }

    /// 执行交接：必须在未来触发点之前，且服务端已接受对应计划版本
    func completeHandover(
        eventKey: PerformanceReminderEventKey,
        planVersion: Int,
        now: Date
    ) -> Bool {
        let reminderTime = eventKey.scheduledStartsAt.addingTimeInterval(-15 * 60)
        // 只有仍未到触发点的未来事件才允许交接；若已到期或已开演，则拒绝交接
        guard now < reminderTime else {
            return false
        }
        var current = record(for: eventKey)
        guard current.status == .pending else {
            return false
        }
        current.channel = .liveActivity
        current.status = .handedOver
        current.planVersion = planVersion
        records[eventKey.stableIdentifier] = current
        return true
    }

    /// 尝试消费主动提醒（唯一消费入口，限制并发且仅触发一次）
    func tryConsume(
        eventKey: PerformanceReminderEventKey,
        by channel: ReminderDeliveryChannel,
        now: Date
    ) -> Bool {
        var current = record(for: eventKey)
        // 必须通道匹配，且状态尚未被消费
        guard current.channel == channel else { return false }
        guard current.status != .consumed && current.status != .revoked else { return false }

        let reminderStart = eventKey.scheduledStartsAt.addingTimeInterval(-15 * 60)
        // 有效窗口为开演前 15 分钟至开演时刻
        guard now >= reminderStart && now < eventKey.scheduledStartsAt else {
            return false
        }

        current.status = .consumed
        current.consumedAt = now
        records[eventKey.stableIdentifier] = current
        return true
    }

    /// 撤销交接（例如活动失效时交回本地）
    func revokeToLocal(
        eventKey: PerformanceReminderEventKey,
        now: Date
    ) -> Bool {
        let reminderStart = eventKey.scheduledStartsAt.addingTimeInterval(-15 * 60)
        guard now < reminderStart else { return false } // 到期后不补发或撤销
        var current = record(for: eventKey)
        guard current.status == .handedOver else { return false }
        current.channel = .localNotification
        current.status = .pending
        records[eventKey.stableIdentifier] = current
        return true
    }

    /// 取消想看或修改时间时废弃
    func revoke(eventKey: PerformanceReminderEventKey) {
        var current = record(for: eventKey)
        current.status = .revoked
        records[eventKey.stableIdentifier] = current
    }

    /// 检查指定通知标识符是否已交接给实时活动或已被消费
    func isHandedOverOrConsumed(notificationIdentifier: String) -> Bool {
        records.values.contains { record in
            record.eventKey.notificationIdentifier == notificationIdentifier
                && (record.status == .handedOver || record.status == .consumed)
        }
    }

    func allRecords() -> [PerformanceReminderRecord] {
        Array(records.values)
    }
}
