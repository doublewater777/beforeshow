import Foundation

// MARK: - ActivityKit APNs Transition Plan Contract (Issue #360)
// 契约：
// - App 挂起时，通过 APNs 静默更新按时推进普通现场与音乐节换场状态
// - 计划包含安装凭据、活动 token、环境、单调版本与截止时间
// - 单次 payload 符合 4 KB 平台约束，不包含全量时刻表

struct LiveActivityReminderEvent: Codable, Hashable, Sendable {
    var performanceID: String
    var startsAt: Date
    var artistName: String?
    var stageName: String?
}

struct LiveActivityTransitionStep: Codable, Equatable, Sendable {
    var scheduledAt: Date
    var staleAt: Date?
    var state: ShowLiveActivityAttributes.ContentState
    var reminderEvents: [LiveActivityReminderEvent]? = nil

    init(
        scheduledAt: Date,
        staleAt: Date? = nil,
        state: ShowLiveActivityAttributes.ContentState,
        reminderEvents: [LiveActivityReminderEvent]? = nil
    ) {
        self.scheduledAt = scheduledAt
        self.staleAt = staleAt
        self.state = state
        self.reminderEvents = reminderEvents
    }
}

struct LiveActivityBoundedTransitionPlan: Codable, Equatable, Sendable {
    var planID: String
    var showID: String
    var appInstanceID: String
    var activityPushToken: String
    var isProduction: Bool
    var version: Int
    var deadline: Date
    var language: String? = nil
    var steps: [LiveActivityTransitionStep]

    init(
        planID: String = UUID().uuidString,
        showID: String,
        appInstanceID: String,
        activityPushToken: String,
        isProduction: Bool,
        version: Int,
        deadline: Date,
        steps: [LiveActivityTransitionStep]
    ) {
        self.planID = planID
        self.showID = showID
        self.appInstanceID = appInstanceID
        self.activityPushToken = activityPushToken
        self.isProduction = isProduction
        self.version = version
        self.deadline = deadline
        self.language = Bundle.main.preferredLocalizations.first
        self.steps = steps
    }
}

enum LiveActivityTransitionPlanBuilder {
    /// 依据当前快照生成有界计划（截至 activityEnd）
    static func buildPlan(
        snapshot: WidgetShowSnapshot,
        now: Date,
        appInstanceID: String,
        activityPushToken: String,
        isProduction: Bool,
        version: Int,
        coverFilename: String? = nil,
        focusedPerformanceID: UUID? = nil,
        artistImageFilename: (String) -> String? = { _ in nil }
    ) -> LiveActivityBoundedTransitionPlan? {
        guard let currentDesired = LiveActivityPlanner.desiredState(
            snapshot: snapshot,
            now: now,
            coverFilename: coverFilename,
            focusedPerformanceID: focusedPerformanceID,
            artistImageFilename: artistImageFilename
        ) else {
            return nil
        }

        let activityEnd = currentDesired.activityEnd
        var refreshDates: Set<Date> = [now]

        var cursor = now
        while let next = LiveActivityPlanner.nextRefreshDate(snapshot: snapshot, now: cursor) {
            if next >= activityEnd {
                refreshDates.insert(activityEnd)
                break
            }
            refreshDates.insert(next)
            cursor = next
        }
        refreshDates.insert(activityEnd)

        let sortedDates = refreshDates.filter { $0 >= now && $0 <= activityEnd }.sorted()
        var steps: [LiveActivityTransitionStep] = []

        for date in sortedDates {
            if date >= activityEnd {
                // 自然散场态
                if let boundaries = LiveActivityPlanner.naturalEndBoundary(snapshot: snapshot, now: date) {
                    let finalState = LiveActivityPlanner.naturalFinalState(
                        snapshot: snapshot,
                        dayStart: boundaries.dayStart,
                        activityEnd: boundaries.activityEnd,
                        coverFilename: coverFilename
                    )
                    steps.append(LiveActivityTransitionStep(
                        scheduledAt: date,
                        staleAt: date.addingTimeInterval(LiveActivityPlanner.dismissalGracePeriod),
                        state: finalState
                    ))
                }
            } else if let desired = LiveActivityPlanner.desiredState(
                snapshot: snapshot,
                now: date,
                coverFilename: coverFilename,
                focusedPerformanceID: focusedPerformanceID,
                artistImageFilename: artistImageFilename
            ) {
                steps.append(LiveActivityTransitionStep(
                    scheduledAt: date,
                    staleAt: desired.state.staleDate,
                    state: desired.state,
                    reminderEvents: snapshot.timetable.flatMap {
                        LiveActivityPlanner.activeReminder(in: $0, now: date)?.events
                    }
                ))
            }
        }

        guard !steps.isEmpty else { return nil }

        return LiveActivityBoundedTransitionPlan(
            showID: snapshot.showID.uuidString,
            appInstanceID: appInstanceID,
            activityPushToken: activityPushToken,
            isProduction: isProduction,
            version: version,
            deadline: activityEnd,
            steps: steps
        )
    }
}
