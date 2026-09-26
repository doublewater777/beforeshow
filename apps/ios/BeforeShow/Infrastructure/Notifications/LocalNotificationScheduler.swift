import Foundation

struct LocalNotificationScheduler {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func futureRequests(for show: Show, now: Date = Date()) -> [ScheduledShowNotification] {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else {
            return []
        }

        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        return milestoneDates(for: timeState, show: show, calendar: eventCalendar, now: now)
            .filter { $0.fireDate > now }
            .map {
                ScheduledShowNotification(
                    showID: show.id,
                    milestone: $0.milestone,
                    fireDate: $0.fireDate,
                    title: notificationTitle(for: $0.milestone, context: context),
                    body: notificationBody(for: $0.milestone, context: context)
                )
            }
    }

    // MARK: - Backfill

    private static let maxBackfillCount = 3
    private static let firstBackfillDelay: TimeInterval = 60 * 60
    private static let backfillInterval: TimeInterval = 12 * 60 * 60
    private static let backfillCrowdingGap: TimeInterval = 4 * 60 * 60

    /// 临近开场才添加的现场，期待期节点已经错过。逐条补发、间隔铺开、封顶 3 条，
    /// 让晚添加的用户也能收到期待曲线，而不是干等下一个自然节点。
    ///
    /// 节奏：首条 1 小时后，之后每 12 小时一条；落在 22:00–08:00 的顺延到清醒时段。
    /// 防拥挤：与任一自然未来节点相距 <4h、或不早于开场时刻的槽位直接丢弃
    /// （残局由 showDay / openingMemory 覆盖）。
    ///
    /// 只在 reconcileAfterShowAdded 里 mint（每场现场一次，见 backfillMintedShowIDs）；
    /// 普通 portfolio reconcile 不调用它——补发时刻依赖 mint 当时的 now，重算会得到另一组时刻。
    func backfillRequests(for show: Show, now: Date = Date()) -> [ScheduledShowNotification] {
        let eventCalendar = show.timingCalendar(fallback: calendar)
        let timeState = CurrentShowTimeState(show: show, calendar: eventCalendar, now: now)
        guard timeState.canScheduleNotifications else { return [] }

        let milestones = milestoneDates(for: timeState, show: show, calendar: eventCalendar, now: now)
        // milestoneDates 按 14→7→3→1 的时间顺序产出，suffix 取最近错过的 3 条，
        // 重放时仍然沿着情绪曲线走。
        let missed = milestones
            .filter { $0.milestone.isAnticipation && $0.fireDate <= now }
            .suffix(Self.maxBackfillCount)
        guard !missed.isEmpty else { return [] }

        let naturalFireDates = milestones.filter { $0.fireDate > now }.map(\.fireDate)
        let showStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: eventCalendar)
        let context = NotificationCopyContext(show: show, timeState: timeState, calendar: eventCalendar)
        let showDay = eventCalendar.startOfDay(for: timeState.effectiveDate)

        // 槽位链式推进：每条在上一条（顺延后的）基础上 +12h，保证相邻补发
        // 至少隔半天；直接落在 22:00–08:00 的先顺延到清醒时段再入链。
        var requests: [ScheduledShowNotification] = []
        var nextSlot = wakingHoursAdjusted(
            now + Self.firstBackfillDelay,
            calendar: eventCalendar
        )
        for entry in missed {
            guard let slot = nextSlot else { break }
            nextSlot = wakingHoursAdjusted(
                slot + Self.backfillInterval,
                calendar: eventCalendar
            )
            // 不早于开场时刻的槽位丢弃；槽位只会越来越晚，可以直接收工。
            guard slot < showStart else { break }
            // 与自然未来节点相距 <4h 的槽位丢弃，避免两条挤在一起。
            guard !naturalFireDates.contains(where: {
                abs($0.timeIntervalSince(slot)) < Self.backfillCrowdingGap
            }) else { continue }

            // 文案按补发触发当天的实际剩余天数写，原节点文案里「还有 N 天」已经不准了。
            let slotDay = eventCalendar.startOfDay(for: slot)
            let days = eventCalendar.dateComponents([.day], from: slotDay, to: showDay).day ?? 0
            let copy = backfillCopy(daysRemaining: days, context: context)
            requests.append(ScheduledShowNotification(
                showID: show.id,
                milestone: entry.milestone,
                fireDate: slot,
                title: copy.title,
                body: copy.body,
                isBackfill: true
            ))
        }
        return requests
    }

    /// 深夜不打扰：22:00–08:00 的槽位顺延，<8 点到当天 08:00，≥22 点到次日 10:00。
    private func wakingHoursAdjusted(_ date: Date, calendar: Calendar) -> Date? {
        let hour = calendar.component(.hour, from: date)
        if hour < 8 {
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date)
        }
        if hour >= 22 {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDay)
        }
        return date
    }

    /// 补发文案：触发当天就开场的复用「今天开场」；更早的用带实际剩余天数的
    /// 通用句（不复用「明天见」——临场前一天添加时会和当晚的自然节点文案撞车），
    /// 标题映射到最近的情绪节点。
    private func backfillCopy(
        daysRemaining: Int,
        context: NotificationCopyContext
    ) -> (title: String, body: String) {
        if daysRemaining <= 0 {
            return (
                notificationTitle(for: .showDayMorning, context: context),
                notificationBody(for: .showDayMorning, context: context)
            )
        }
        return (
            BSLocalization.text("离开场更近了"),
            BSLocalization.format("%1$@ 还有 %2$d 天。先一起听几首，慢慢等。", context.showName, daysRemaining)
        )
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
        now: Date
    ) -> [(milestone: ShowNotificationMilestone, fireDate: Date)] {
        let showStart = CurrentShowTimeState.effectiveStartTime(for: show, calendar: calendar)
        let planned: [(ShowNotificationMilestone, Date?)] = [
            (.fourteenDaysBefore, dayRelativeToShow(timeState, offset: -14, hour: 20, calendar: calendar)),
            (.sevenDaysBefore, dayRelativeToShow(timeState, offset: -7, hour: 20, calendar: calendar)),
            (.threeDaysBefore, dayRelativeToShow(timeState, offset: -3, hour: 20, calendar: calendar)),
            (.oneDayBefore, dayRelativeToShow(timeState, offset: -1, hour: 20, calendar: calendar)),
            (.showDayMorning, dayRelativeToShow(timeState, offset: 0, hour: 9, calendar: calendar)),
            (.showDay, showDayReminderDate(for: timeState, calendar: calendar, now: now)),
            (
                .openingMemory,
                OpeningMemoryWindow.notificationFireDate(
                    now: now,
                    showStart: showStart,
                    hasConfirmedEnd: show.endedAt != nil
                )
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
