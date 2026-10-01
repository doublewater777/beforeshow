import Foundation

struct LocalNotificationScheduler {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func futureRequests(
        for show: Show,
        now: Date = Date(),
        scheduledShowDayFireDate: Date? = nil
    ) -> [ScheduledShowNotification] {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else {
            return []
        }

        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        return milestoneDates(
            for: timeState, show: show, calendar: eventCalendar, now: now,
            scheduledShowDayFireDate: scheduledShowDayFireDate
        )
            .filter { $0.fireDate > now }
            .map {
                ScheduledShowNotification(
                    showID: show.id,
                    milestone: $0.milestone,
                    fireDate: $0.fireDate,
                    title: notificationTitle(for: $0.milestone, context: context),
                    body: notificationBody(for: $0.milestone, context: context),
                    showStartTime: $0.milestone == .showDay ? timeState.effectiveStartTime : nil
                )
            }
    }

    /// 已确认散场（endedAt != nil）的现场的「次日回看」请求。
    /// 只在未来触发时刻存在时返回；未确认散场的现场由 futureRequests 负责。
    func afterShowRequest(for show: Show, now: Date = Date()) -> ScheduledShowNotification? {
        guard show.endedAt != nil else { return nil }
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard let fireDate = afterShowReminderDate(for: timeState, calendar: eventCalendar, confirmedEnd: show.endedAt),
              fireDate > now else { return nil }
        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        return ScheduledShowNotification(
            showID: show.id,
            milestone: .afterShow,
            fireDate: fireDate,
            title: notificationTitle(for: .afterShow, context: context),
            body: notificationBody(for: .afterShow, context: context)
        )
    }

    private func milestoneDates(
        for timeState: CurrentShowTimeState,
        show: Show,
        calendar: Calendar,
        now: Date,
        scheduledShowDayFireDate: Date? = nil
    ) -> [(milestone: ShowNotificationMilestone, fireDate: Date)] {
        let showStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let planned: [(ShowNotificationMilestone, Date?)] = [
            (.fourteenDaysBefore, dayRelativeToShow(timeState, offset: -14, hour: 20, calendar: calendar)),
            (.sevenDaysBefore, dayRelativeToShow(timeState, offset: -7, hour: 20, calendar: calendar)),
            (.threeDaysBefore, dayRelativeToShow(timeState, offset: -3, hour: 20, calendar: calendar)),
            (.oneDayBefore, dayRelativeToShow(timeState, offset: -1, hour: 20, calendar: calendar)),
            (.showDayMorning, dayRelativeToShow(timeState, offset: 0, hour: 9, calendar: calendar)),
            (.showDay, scheduledShowDayFireDate ?? showDayReminderDate(for: timeState, calendar: calendar, now: now)),
            (
                .openingMemory,
                (show.endedAt == nil && now < showStart) ? showStart : nil
            ),
            (.afterShow, afterShowReminderDate(for: timeState, calendar: calendar))
        ]

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

    /// 情绪曲线：期待 → 想象 → 具体 → 收束 → 出门 → 紧迫 → 回看。
    /// 有场馆 / 城市时说得更具体，缺字段时退回通用句，不出现空占位。
    private func notificationBody(
        for milestone: ShowNotificationMilestone,
        context: NotificationCopyContext
    ) -> String {
        let name = context.showName

        switch milestone {
        case .fourteenDaysBefore:
            return BSLocalization.format("%@，还有两周。先一起听几首，慢慢等。", name)

        case .sevenDaysBefore:
            return BSLocalization.format("再过一周，我们就去见 %@ 了。这几天，把歌先听起来。", name)

        case .threeDaysBefore:
            return BSLocalization.format("%@ 已经很近了。再听几首，我们现场见。", name)

        case .oneDayBefore:
            if context.isMultiDay {
                return BSLocalization.format("%@ 明天开始。今晚再听一会儿，明天一起去。", name)
            }
            return BSLocalization.format("最后再听一晚。明天，我们去见 %@。", name)

        case .showDayMorning:
            if let place = context.place, let clock = context.startClock {
                return BSLocalization.format("%1$@ · %2$@ · %3$@。今天，我们现场见。", name, clock, place)
            }
            if let clock = context.startClock {
                return BSLocalization.format("%1$@ · %2$@。今天，我们现场见。", name, clock)
            }
            return BSLocalization.format("%@。今天，我们现场见。", name)

        case .showDay:
            if let place = context.place {
                return BSLocalization.format("%1$@ · %2$@。只剩几个小时了，现场见。", name, place)
            }
            return BSLocalization.format("%@。只剩几个小时了，我们现场见。", name)

        case .afterShow:
            return BSLocalization.format("%@ 散场了。想记住的，我们慢慢留在这里。", name)

        case .openingMemory:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return BSLocalization.text("开始了。想留下什么，我们就留一点下来。")
            }
            return BSLocalization.format("%@ 开始了。想留下什么，我们就留一点下来。", trimmed)
        }
    }

    private func notificationTitle(
        for milestone: ShowNotificationMilestone,
        context: NotificationCopyContext
    ) -> String {
        switch milestone {
        case .fourteenDaysBefore:
            return BSLocalization.text("开场之前，先进入状态")
        case .sevenDaysBefore:
            return BSLocalization.text("又近了一点")
        case .threeDaysBefore:
            return BSLocalization.text("这周就见")
        case .oneDayBefore:
            return BSLocalization.text("明天见")
        case .showDayMorning:
            return BSLocalization.text("就是今天")
        case .showDay:
            return BSLocalization.text("快开场了")
        case .afterShow:
            return BSLocalization.text("昨晚怎么样")
        case .openingMemory:
            return BSLocalization.text("留下此刻")
        }
    }
}
