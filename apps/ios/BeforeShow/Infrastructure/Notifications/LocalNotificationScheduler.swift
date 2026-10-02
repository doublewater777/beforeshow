import Foundation

/// 下一场的事实，只用于散场后第 3 天那条「下一场」文案。
struct NotificationNextShow: Equatable {
    let name: String
    let daysUntil: Int

    init(name: String, daysUntil: Int) {
        self.name = name
        self.daysUntil = daysUntil
    }

    init(show: Show, now: Date) {
        let calendar = show.timingCalendar()
        let state = CurrentShowTimeState(show: show, calendar: calendar, now: now)
        self.init(name: show.name, daysUntil: max(0, state.dayDistance))
    }
}

/// 当前现场排全部节点；其他现场只排开场前 3 小时（ADR 0037）。
struct NotificationScheduleScope {
    let includesAllMilestones: Bool
    var recommendations = FeatureRecommendationContext()
    var nextShow: NotificationNextShow?

    static let all = NotificationScheduleScope(includesAllMilestones: true)
    static let showDayOnly = NotificationScheduleScope(includesAllMilestones: false)
}

struct LocalNotificationScheduler {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func futureRequests(
        for show: Show,
        now: Date = Date(),
        scheduledShowDayFireDate: Date? = nil,
        scope: NotificationScheduleScope = .all
    ) -> [ScheduledShowNotification] {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else {
            return []
        }

        let copy = NotificationCopy(
            context: NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        )
        let showDayDate = scheduledShowDayFireDate
            ?? showDayReminderDate(for: timeState, calendar: eventCalendar, now: now)
        var nodes: [(milestone: ShowNotificationMilestone, fireDate: Date)] = []
        if let showDayDate {
            nodes.append((.showDay, showDayDate))
        }
        if scope.includesAllMilestones {
            nodes += milestoneDates(
                for: show, timeState: timeState, calendar: eventCalendar, now: now, showDayDate: showDayDate
            )
        }

        var plannedExposures: [RecommendedFeature: Int] = [:]
        var requests: [ScheduledShowNotification] = []
        for node in nodes.filter({ $0.fireDate > now }).sorted(by: { $0.fireDate < $1.fireDate }) {
            guard let content = content(
                for: node.milestone, fireDate: node.fireDate, show: show, timeState: timeState,
                calendar: eventCalendar, copy: copy, scope: scope, plannedExposures: plannedExposures
            ) else {
                continue
            }
            if let feature = content.feature {
                plannedExposures[feature, default: 0] += 1
            }
            requests.append(ScheduledShowNotification(
                showID: show.id,
                milestone: node.milestone,
                fireDate: node.fireDate,
                title: copy.title,
                body: content.body,
                showStartTime: node.milestone == .showDay ? timeState.effectiveStartTime : nil,
                destination: content.destination,
                feature: content.feature
            ))
        }
        return requests
    }

    // MARK: - Dates

    private func milestoneDates(
        for show: Show,
        timeState: CurrentShowTimeState,
        calendar: Calendar,
        now: Date,
        showDayDate: Date?
    ) -> [(milestone: ShowNotificationMilestone, fireDate: Date)] {
        var planned: [(ShowNotificationMilestone, Date?)] = []
        if show.endedAt == nil {
            let showStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
            planned += [
                (.addedFollowUp, followUpDate(for: show, timeState: timeState, calendar: calendar)),
                (.fourteenDaysBefore, dayRelativeToShow(timeState, offset: -14, hour: 20, calendar: calendar)),
                (.sevenDaysBefore, dayRelativeToShow(timeState, offset: -7, hour: 20, calendar: calendar)),
                (.threeDaysBefore, dayRelativeToShow(timeState, offset: -3, hour: 20, calendar: calendar)),
                (.oneDayBefore, dayRelativeToShow(timeState, offset: -1, hour: 20, calendar: calendar)),
                (.showDayMorning, morningDate(timeState, showStart: showStart, showDayDate: showDayDate, calendar: calendar)),
                (.openingMemory, now < showStart ? showStart : nil)
            ]
        }

        // 散场时间只由用户确认；没确认时按预计散场排，点进去先确认散场时间。
        if let end = show.endedAt ?? estimatedFinalEnd(for: show, calendar: calendar) {
            if !show.hasCompletedDispersalCeremony {
                planned.append((.postShowRitual, calendar.date(byAdding: .minute, value: 15, to: end)))
                planned.append((.afterShow, afterShowReminderDate(for: timeState, calendar: calendar, confirmedEnd: show.endedAt)))
            }
            planned.append((.footprintArrival, dayAfter(end, days: 3, hour: 20, calendar: calendar)))
        }

        return planned.compactMap { milestone, fireDate in
            fireDate.map { (milestone, $0) }
        }
    }

    private func dayRelativeToShow(
        _ timeState: CurrentShowTimeState,
        offset: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date? {
        let showDay = calendar.startOfDay(for: timeState.effectiveDate)
        guard let targetDay = calendar.date(byAdding: .day, value: offset, to: showDay) else {
            return nil
        }

        return calendar.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: targetDay
        )
    }

    private func dayAfter(_ date: Date, days: Int, hour: Int, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    /// 添加后次日 20:00；离开场不足 8 天、或正好落在 T-14 那天时不发。
    private func followUpDate(for show: Show, timeState: CurrentShowTimeState, calendar: Calendar) -> Date? {
        guard let fireDate = dayAfter(show.createdAt, days: 1, hour: 20, calendar: calendar) else { return nil }
        let distance = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: fireDate),
            to: calendar.startOfDay(for: timeState.effectiveDate)
        ).day ?? 0
        return distance >= 8 && distance != 14 ? fireDate : nil
    }

    /// 当天 09:00；开场前 3 小时早于 10:00 时并入那一条，不再单发。
    private func morningDate(
        _ timeState: CurrentShowTimeState,
        showStart: Date,
        showDayDate: Date?,
        calendar: Calendar
    ) -> Date? {
        guard let morning = dayRelativeToShow(timeState, offset: 0, hour: 9, calendar: calendar),
              morning < showStart else {
            return nil
        }
        if let showDayDate,
           let tenOClock = dayRelativeToShow(timeState, offset: 0, hour: 10, calendar: calendar),
           showDayDate < tenOClock {
            return nil
        }
        return morning
    }

    /// 开场前 3 小时。临时添加的现场（3 小时内开场）不能因为节点已过就静默，
    /// 只要还没开场就顺延到 10 分钟后，保证至少收到一条。
    private func showDayReminderDate(
        for timeState: CurrentShowTimeState,
        calendar: Calendar,
        now: Date
    ) -> Date? {
        guard let startTime = timeState.effectiveStartTime else {
            return calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: calendar.startOfDay(for: timeState.effectiveDate)
            )
        }

        guard let threeHoursBefore = calendar.date(byAdding: .hour, value: -3, to: startTime) else {
            return nil
        }
        if threeHoursBefore > now {
            return threeHoursBefore
        }
        // 已经进入开场前 3 小时窗口：还没开场就补一条，开场后不再补。
        guard now < startTime, let soon = calendar.date(byAdding: .minute, value: 10, to: now) else {
            return nil
        }
        return min(soon, startTime)
    }

    /// 散场次日 11:00。用户确认过散场就以真实散场时刻为准，否则按最后一天的估算边界。
    private func afterShowReminderDate(
        for timeState: CurrentShowTimeState,
        calendar: Calendar,
        confirmedEnd: Date? = nil
    ) -> Date? {
        let lastDay = calendar.startOfDay(
            for: confirmedEnd ?? timeState.effectiveEndDate ?? timeState.effectiveDate
        )
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        return calendar.date(bySettingHour: 11, minute: 0, second: 0, of: nextDay)
    }

    /// 整场（多日为最后一天）的预计散场。开场前的时间状态给出的就是整场边界。
    private func estimatedFinalEnd(for show: Show, calendar: Calendar) -> Date? {
        CurrentShowTimeState(show: show, calendar: calendar, now: .distantPast).endBoundary
    }

    // MARK: - Content

    private func content(
        for milestone: ShowNotificationMilestone,
        fireDate: Date,
        show: Show,
        timeState: CurrentShowTimeState,
        calendar: Calendar,
        copy: NotificationCopy,
        scope: NotificationScheduleScope,
        plannedExposures: [RecommendedFeature: Int]
    ) -> NotificationNodeContent? {
        func recommended(_ slot: FeatureRecommendationSlot) -> RecommendedFeature? {
            FeatureRecommendationPolicy.candidate(
                from: slot.chain(isFestival: copy.context.isFestival, hasFutureShow: scope.nextShow != nil),
                context: scope.recommendations,
                plannedExposures: plannedExposures
            )
        }

        if let slot = milestone.recommendationSlot {
            guard let feature = recommended(slot) else { return nil }
            let daysLeft = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: fireDate),
                to: calendar.startOfDay(for: timeState.effectiveDate)
            ).day ?? 0
            return NotificationNodeContent(
                body: copy.recommendation(feature, daysLeft: daysLeft),
                destination: feature.notificationDestination,
                feature: feature
            )
        }

        let isConfirmed = show.endedAt != nil
        switch milestone {
        case .oneDayBefore:
            return NotificationNodeContent(body: copy.oneDayBefore(), destination: .listen)
        case .showDayMorning:
            let timetable = copy.context.isFestival
            return NotificationNodeContent(
                body: copy.morning(showsTimetable: timetable),
                destination: timetable ? .timetable : .route
            )
        case .showDay:
            let remaining = timeState.effectiveStartTime.map { Int($0.timeIntervalSince(fireDate)) }
            let isBackfill = remaining.map { $0 < 3 * 3_600 - 60 } ?? false
            return NotificationNodeContent(
                body: copy.showDay(remainingSeconds: isBackfill ? remaining : nil),
                destination: .route
            )
        case .openingMemory:
            return NotificationNodeContent(body: copy.opening, destination: .memoryCreate)
        case .postShowRitual:
            return NotificationNodeContent(body: copy.postShowRitual(isConfirmed: isConfirmed), destination: .dispersal)
        case .afterShow:
            return NotificationNodeContent(body: copy.afterShow(isConfirmed: isConfirmed), destination: .dispersal)
        case .footprintArrival:
            guard isConfirmed else {
                return NotificationNodeContent(body: copy.confirmEndForFootprint, destination: .dispersal)
            }
            guard let feature = recommended(.footprintArrival) else { return nil }
            return NotificationNodeContent(
                body: copy.afterRetention(feature, nextShow: scope.nextShow),
                destination: feature.notificationDestination,
                feature: feature
            )
        case .addedFollowUp, .fourteenDaysBefore, .sevenDaysBefore, .threeDaysBefore:
            return nil
        }
    }
}
