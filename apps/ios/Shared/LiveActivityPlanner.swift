import Foundation

// MARK: - Live Activity Planner
// 实时活动内容与时间边界的纯逻辑,与 ActivityKit 解耦。
// - 平台单个活动最多活跃 8h:音乐节一天(开场前 3h → 散场)从散场往前按 8h 切段,
//   每段一个活动;普通现场只保留散场前最后 8h 一段。
// - 生命周期决策(请求/预约/更新/结束)见 app 侧 LiveActivityLifecyclePlanner。

struct LiveActivitySegment: Equatable {
    var start: Date
    var end: Date
}

enum LiveActivityPlanner {
    struct ActiveReminder {
        let artistName: String
        let stageName: String
        let startsAt: Date
        let expiresAt: Date
        let performanceIDs: [String]
        let summary: String?
        let events: [LiveActivityReminderEvent]
        let performanceID: UUID
    }

    static func activeReminder(
        in timetable: WidgetTimetableSnapshot,
        now: Date
    ) -> ActiveReminder? {
        // 遍历所有天所有舞台的想看场次
        var activePerfs: [(dayDate: Date, perf: WidgetTimetablePerformance)] = []
        for day in timetable.days {
            for p in day.performances where p.isInterested {
                let reminderStart = p.startsAt.addingTimeInterval(-reminderLeadTime)
                if now >= reminderStart && now < p.startsAt {
                    activePerfs.append((day.date, p))
                }
            }
        }
        guard !activePerfs.isEmpty else { return nil }

        // 按开演时间升序，同开演时间按 ID 字典序稳定排序
        activePerfs.sort { lhs, rhs in
            if lhs.perf.startsAt != rhs.perf.startsAt {
                return lhs.perf.startsAt < rhs.perf.startsAt
            }
            return lhs.perf.id.uuidString < rhs.perf.id.uuidString
        }

        let first = activePerfs[0].perf
        let performanceIDs = activePerfs.map { $0.perf.id.uuidString }
        let summary: String? = activePerfs.count > 1
            ? LiveActivityCopy.additionalReminders(activePerfs.count - 1)
            : nil

        return ActiveReminder(
            artistName: first.artistName,
            stageName: first.stageName,
            startsAt: first.startsAt,
            expiresAt: first.startsAt,
            performanceIDs: performanceIDs,
            summary: summary,
            events: activePerfs.map { .init(performanceID: $0.perf.id.uuidString, startsAt: $0.perf.startsAt,
                artistName: $0.perf.artistName, stageName: $0.perf.stageName) },
            performanceID: first.id
        )
    }

    static let maxActiveDuration: TimeInterval = 8 * 3_600
    static let scheduleHorizon: TimeInterval = 7 * 86_400
    static let dismissalGracePeriod: TimeInterval = 15 * 60
    static let reminderLeadTime: TimeInterval = 15 * 60
    /// 开场前提前出现,覆盖出门、排队、入场。
    static let startLeadTime: TimeInterval = 3 * 3_600

    static func desiredState(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        coverFilename: String?,
        focusedPerformanceID: UUID? = nil,
        artistImageFilename: (String) -> String? = { _ in nil }
    ) -> (state: ShowLiveActivityAttributes.ContentState, activityEnd: Date, dayStart: Date)? {
        guard let snapshot,
              snapshot.timing.changeStatus != .canceled,
              snapshot.timing.endedAt == nil,
              !(snapshot.timing.changeStatus == .postponed && snapshot.timing.postponedDate == nil) else {
            return nil
        }

        // 1. Timetable-driven path (Live Mode)
        if let timetable = snapshot.timetable, !timetable.days.isEmpty {
            let liveDays = timetable.days.map { day in
                LiveDayInput(
                    id: day.id,
                    date: day.date,
                    performances: day.performances.map { p in
                        LivePerformanceInput(
                            id: p.id,
                            artistName: p.artistName,
                            stageID: p.stageID,
                            stageName: p.stageName,
                            startsAt: p.startsAt,
                            endsAt: p.endsAt,
                            isInterested: p.isInterested
                        )
                    }
                )
            }
            let liveState = LiveModeStateEngine.calculate(
                days: liveDays, now: now, focusedPerformanceID: focusedPerformanceID
            )
            let imageSources = artistImageSources(in: timetable)
            func image(_ id: UUID?) -> String? {
                id.flatMap { imageSources[$0] }.flatMap(artistImageFilename)
            }
            let reminder = activeReminder(in: timetable, now: now)

            switch liveState.phase {
            case .dayEnded:
                return nil
            case .fullyEnded:
                // A later explicit closing can outlive the final scheduled set.
                guard CurrentShowTimeState(timing: snapshot.timing, now: now).kind == .today else { return nil }
                break

            case .active:
                let dayStart: Date
                let dayEnd: Date
                if let activeDayID = liveState.activeDayID,
                   let day = liveDays.first(where: { $0.id == activeDayID }),
                   let minStart = day.performances.map({ $0.startsAt }).min(),
                   let maxEnd = day.performances.map({ $0.endsAt }).max() {
                    dayStart = snapshot.timing.resolvedSessions(calendar: snapshot.timing.eventCalendar(fallback: .current))
                        .first { $0.date == day.date }?.startsAt ?? minStart
                    dayEnd = snapshot.timing.resolvedSessions(calendar: snapshot.timing.eventCalendar(fallback: .current))
                        .first { $0.date == day.date }?.endsAt ?? maxEnd
                } else {
                    dayStart = now
                    dayEnd = now.addingTimeInterval(TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600)
                }

                guard now < dayEnd else { return nil }

                let current = liveState.currentPerformances.first
                let also = liveState.currentPerformances.dropFirst().first
                let upcoming = liveState.upcomingPerformances.first
                // 场间:计时倒数到下一场开演(staleDate 也随之落在开演时刻)。
                let start = current?.startsAt ?? upcoming?.startsAt ?? now
                // The parallel set ending also makes the content out of date.
                let baseExpiration = [current?.endsAt ?? upcoming?.startsAt, also?.endsAt].compactMap { $0 }.min()
                let contentExpiration: Date?
                if let reminder {
                    contentExpiration = [baseExpiration, reminder.expiresAt].compactMap({ $0 }).min()
                } else {
                    contentExpiration = baseExpiration
                }

                return (
                    ShowLiveActivityAttributes.ContentState(
                        showName: snapshot.name,
                        city: snapshot.city,
                        venueName: snapshot.venueName,
                        startDate: start,
                        endDate: dayEnd,
                        lifecycleEnd: dayEnd,
                        timeZoneSecondsFromGMT: snapshot.timing.timeZoneSecondsFromGMT,
                        endTimeZoneSecondsFromGMT: snapshot.timing.endTimeZoneSecondsFromGMT,
                        timeZoneIdentifier: snapshot.timing.sessionTimeZoneIdentifier ?? snapshot.timing.timeZoneIdentifier,
                        endTimeZoneIdentifier: snapshot.timing.endTimeZoneIdentifier,
                        coverImageFilename: coverFilename,
                        hasStarted: true,
                        currentArtistName: current?.artistName,
                        currentStageName: current?.stageName,
                        currentStartsAt: current?.startsAt,
                        currentEndsAt: current?.endsAt,
                        nextArtistName: upcoming?.artistName,
                        nextStageName: upcoming?.stageName,
                        nextStartsAt: upcoming?.startsAt,
                        isNextStartingSoon: upcoming?.isStartingSoon ?? false,
                        isInterestedNext: upcoming?.isInterested ?? false,
                        isFestivalDayActive: true,
                        alsoArtistName: also?.artistName,
                        alsoStageName: also?.stageName,
                        alsoEndsAt: also?.endsAt,
                        reminderArtistName: reminder?.artistName,
                        reminderStageName: reminder?.stageName,
                        reminderStartsAt: reminder?.startsAt,
                        reminderExpiresAt: reminder?.expiresAt,
                        reminderSummary: reminder?.summary,
                        reminderPerformanceIDs: reminder?.performanceIDs,
                        isReminderActive: reminder != nil,
                        currentArtistImageFilename: image(current?.id),
                        alsoArtistImageFilename: image(also?.id),
                        nextArtistImageFilename: image(upcoming?.id),
                        reminderArtistImageFilename: image(reminder?.performanceID),
                        isEnded: false,
                        contentExpirationDate: contentExpiration,
                        reminderCount: reminder?.events.count,
                        reminderPerformanceID: reminder?.performanceID.uuidString,
                        nextPerformanceID: upcoming?.id.uuidString,
                        hasTimetable: true
                    ),
                    dayEnd,
                    dayStart
                )

            case .upcoming(let firstStartsAt):
                let upcoming = liveState.upcomingPerformances.first
                let dayStart: Date
                let activityEnd: Date
                if let activeDayID = liveState.activeDayID,
                   let day = liveDays.first(where: { $0.id == activeDayID }),
                   let minStart = day.performances.map({ $0.startsAt }).min(),
                   let maxEnd = day.performances.map({ $0.endsAt }).max() {
                    dayStart = snapshot.timing.resolvedSessions(calendar: snapshot.timing.eventCalendar(fallback: .current))
                        .first { $0.date == day.date }?.startsAt ?? minStart
                    activityEnd = snapshot.timing.resolvedSessions(calendar: snapshot.timing.eventCalendar(fallback: .current))
                        .first { $0.date == day.date }?.endsAt ?? maxEnd
                } else {
                    dayStart = firstStartsAt
                    activityEnd = firstStartsAt.addingTimeInterval(TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600)
                }
                let baseExpiration = upcoming?.startsAt ?? firstStartsAt
                let contentExpiration: Date?
                if let reminder {
                    contentExpiration = [baseExpiration, reminder.expiresAt].compactMap({ $0 }).min()
                } else {
                    contentExpiration = baseExpiration
                }

                return (
                    ShowLiveActivityAttributes.ContentState(
                        showName: snapshot.name,
                        city: snapshot.city,
                        venueName: snapshot.venueName,
                        startDate: firstStartsAt,
                        endDate: activityEnd,
                        lifecycleEnd: activityEnd,
                        timeZoneSecondsFromGMT: snapshot.timing.timeZoneSecondsFromGMT,
                        endTimeZoneSecondsFromGMT: snapshot.timing.endTimeZoneSecondsFromGMT,
                        timeZoneIdentifier: snapshot.timing.sessionTimeZoneIdentifier ?? snapshot.timing.timeZoneIdentifier,
                        endTimeZoneIdentifier: snapshot.timing.endTimeZoneIdentifier,
                        coverImageFilename: coverFilename,
                        hasStarted: false,
                        nextArtistName: upcoming?.artistName,
                        nextStageName: upcoming?.stageName,
                        nextStartsAt: upcoming?.startsAt,
                        isNextStartingSoon: upcoming?.isStartingSoon ?? false,
                        isInterestedNext: upcoming?.isInterested ?? false,
                        isFestivalDayActive: false,
                        reminderArtistName: reminder?.artistName,
                        reminderStageName: reminder?.stageName,
                        reminderStartsAt: reminder?.startsAt,
                        reminderExpiresAt: reminder?.expiresAt,
                        reminderSummary: reminder?.summary,
                        reminderPerformanceIDs: reminder?.performanceIDs,
                        isReminderActive: reminder != nil,
                        nextArtistImageFilename: image(upcoming?.id),
                        reminderArtistImageFilename: image(reminder?.performanceID),
                        isEnded: false,
                        contentExpirationDate: contentExpiration,
                        reminderCount: reminder?.events.count,
                        reminderPerformanceID: reminder?.performanceID.uuidString,
                        nextPerformanceID: upcoming?.id.uuidString,
                        hasTimetable: true
                    ),
                    activityEnd,
                    dayStart
                )
            }
        }

        // 2. Non-timetable show fallback
        let timeState = CurrentShowTimeState(timing: snapshot.timing, now: now)
        guard let start = timeState.effectiveStartTime else {
            return nil
        }
        let activityEnd = timeState.endBoundary ?? start.addingTimeInterval(
            TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600
        )
        guard now < activityEnd else {
            return nil
        }

        // 仅在真实设置了散场钟点/时间时提供 endDate；未填写时不计算虚假进度
        let explicitEnd = snapshot.timing.endTime != nil ? timeState.endBoundary : nil
        let contentExpiration = now < start ? start : activityEnd

        return (
            ShowLiveActivityAttributes.ContentState(
                showName: snapshot.name,
                city: snapshot.city,
                venueName: snapshot.venueName,
                startDate: start,
                endDate: explicitEnd,
                lifecycleEnd: activityEnd,
                timeZoneSecondsFromGMT: snapshot.timing.timeZoneSecondsFromGMT,
                endTimeZoneSecondsFromGMT: snapshot.timing.endTimeZoneSecondsFromGMT,
                timeZoneIdentifier: snapshot.timing.sessionTimeZoneIdentifier ?? snapshot.timing.timeZoneIdentifier,
                endTimeZoneIdentifier: snapshot.timing.endTimeZoneIdentifier,
                coverImageFilename: coverFilename,
                hasStarted: now >= start,
                isEnded: false,
                contentExpirationDate: contentExpiration
            ),
            activityEnd,
            start
        )
    }

    /// 下一个会改变实时活动内容的时刻(场次开演/结束、「即将开始」阈值、普通现场开场)。
    /// ActivityKit 不会自己换内容:App 存活时到点用同一快照重新发布。
    static func nextRefreshDate(snapshot: WidgetShowSnapshot?, now: Date) -> Date? {
        guard let snapshot,
              snapshot.timing.changeStatus != .canceled,
              snapshot.timing.endedAt == nil,
              !(snapshot.timing.changeStatus == .postponed && snapshot.timing.postponedDate == nil) else {
            return nil
        }
        var boundaries: [Date] = []
        if let timetable = snapshot.timetable, !timetable.days.isEmpty {
            let calendar = snapshot.timing.eventCalendar(fallback: .current)
            let sessions = snapshot.timing.resolvedSessions(calendar: calendar)
            for day in timetable.days {
                guard let minStart = day.performances.map(\.startsAt).min(),
                      let maxEnd = day.performances.map(\.endsAt).max() else { continue }
                let dayStart = sessions.first { $0.date == day.date }?.startsAt ?? minStart
                let dayEnd = sessions.first { $0.date == day.date }?.endsAt ?? maxEnd
                boundaries += segments(dayStart: dayStart, dayEnd: dayEnd, splitsLongDays: true).map(\.start)
                boundaries.append(dayEnd)
                for performance in day.performances {
                    boundaries.append(performance.startsAt.addingTimeInterval(-LivePerformanceSnapshot.startingSoonLead))
                    if performance.isInterested {
                        boundaries.append(performance.startsAt.addingTimeInterval(-reminderLeadTime))
                    }
                    boundaries.append(performance.startsAt)
                    boundaries.append(performance.endsAt)
                }
            }
        } else if let start = CurrentShowTimeState(timing: snapshot.timing, now: now).effectiveStartTime {
            let timeState = CurrentShowTimeState(timing: snapshot.timing, now: now)
            let activityEnd = timeState.endBoundary ?? start.addingTimeInterval(
                TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600
            )
            boundaries += segments(dayStart: start, dayEnd: activityEnd, splitsLongDays: false).map(\.start)
            boundaries.append(start)
            boundaries.append(activityEnd)
        }
        return boundaries.filter { $0 > now }.min()
    }

    /// 覆盖「开场前 3h → 散场」。拆段时从散场往前切,压轴所在的最后一段最长;
    /// 不拆时只留最后 8h。
    static func segments(dayStart: Date, dayEnd: Date, splitsLongDays: Bool) -> [LiveActivitySegment] {
        let windowStart = dayStart.addingTimeInterval(-startLeadTime)
        guard splitsLongDays else {
            return [LiveActivitySegment(
                start: max(windowStart, dayEnd.addingTimeInterval(-maxActiveDuration)), end: dayEnd
            )]
        }
        var result: [LiveActivitySegment] = []
        var end = dayEnd
        repeat {
            let start = max(windowStart, end.addingTimeInterval(-maxActiveDuration))
            result.insert(LiveActivitySegment(start: start, end: end), at: 0)
            end = start
        } while end > windowStart
        return result
    }

    /// 当前现场这一天的分段(desiredState 选出的那一天)。
    static func segments(
        snapshot: WidgetShowSnapshot,
        desired: (state: ShowLiveActivityAttributes.ContentState, activityEnd: Date, dayStart: Date)
    ) -> [LiveActivitySegment] {
        segments(
            dayStart: desired.dayStart, dayEnd: desired.activityEnd,
            splitsLongDays: !(snapshot.timetable?.days.isEmpty ?? true)
        )
    }

    static func naturalEndBoundary(snapshot: WidgetShowSnapshot, now: Date) -> (dayStart: Date, activityEnd: Date)? {
        if let timetable = snapshot.timetable, !timetable.days.isEmpty {
            let calendar = snapshot.timing.eventCalendar(fallback: .current)
            let sessions = snapshot.timing.resolvedSessions(calendar: calendar)
            for day in timetable.days {
                guard let minStart = day.performances.map(\.startsAt).min(),
                      let maxEnd = day.performances.map(\.endsAt).max() else { continue }
                let dayStart = sessions.first { $0.date == day.date }?.startsAt ?? minStart
                let dayEnd = sessions.first { $0.date == day.date }?.endsAt ?? maxEnd
                if now >= dayStart.addingTimeInterval(-maxActiveDuration) && now <= dayEnd.addingTimeInterval(dismissalGracePeriod) {
                    return (dayStart, dayEnd)
                }
            }
            return nil
        }

        let timeState = CurrentShowTimeState(timing: snapshot.timing, now: now)
        guard let start = timeState.effectiveStartTime else { return nil }
        let activityEnd = timeState.endBoundary ?? start.addingTimeInterval(
            TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600
        )
        if now >= start.addingTimeInterval(-maxActiveDuration) && now <= activityEnd.addingTimeInterval(dismissalGracePeriod) {
            return (start, activityEnd)
        }
        return nil
    }

    static func naturalFinalState(
        snapshot: WidgetShowSnapshot,
        dayStart: Date,
        activityEnd: Date,
        coverFilename: String?
    ) -> ShowLiveActivityAttributes.ContentState {
        ShowLiveActivityAttributes.ContentState(
            showName: snapshot.name,
            city: snapshot.city,
            venueName: snapshot.venueName,
            startDate: dayStart,
            endDate: activityEnd,
            lifecycleEnd: activityEnd,
            timeZoneSecondsFromGMT: snapshot.timing.timeZoneSecondsFromGMT,
            endTimeZoneSecondsFromGMT: snapshot.timing.endTimeZoneSecondsFromGMT,
            timeZoneIdentifier: snapshot.timing.sessionTimeZoneIdentifier ?? snapshot.timing.timeZoneIdentifier,
            endTimeZoneIdentifier: snapshot.timing.endTimeZoneIdentifier,
            coverImageFilename: coverFilename,
            hasStarted: true,
            isEnded: true,
            hasTimetable: !(snapshot.timetable?.days.isEmpty ?? true),
            endKind: !(snapshot.timetable?.days.isEmpty ?? true) ? "festival"
                : snapshot.timing.endTime == nil ? "tracking" : "show"
        )
    }

    /// 实时活动当前会用到的艺人图(主现场 / 同时在演 / 下一场),由 app 侧先缓存小图。
    static func featuredArtistImageSources(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        focusedPerformanceID: UUID? = nil
    ) -> Set<String> {
        var sources = Set<String>()
        _ = desiredState(
            snapshot: snapshot, now: now, coverFilename: nil, focusedPerformanceID: focusedPerformanceID,
            artistImageFilename: { sources.insert($0); return nil }
        )
        return sources
    }

    private static func artistImageSources(in timetable: WidgetTimetableSnapshot) -> [UUID: String] {
        var sources: [UUID: String] = [:]
        for performance in timetable.days.flatMap(\.performances) {
            let url = performance.artistImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !url.isEmpty { sources[performance.id] = url }
        }
        return sources
    }
}

