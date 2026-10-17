import Foundation

// MARK: - Live Activity Planner
// 生命周期决策的纯逻辑,与 ActivityKit 解耦:输入「现在 + 快照 + 现有活动摘要」,
// 输出动作。actor 只负责把动作翻译成 ActivityKit 调用。
// 规则(评审定稿):
// - 活跃窗口 = 预计谢幕前最多 8h(平台活跃上限)
// - 窗口外:iOS 26+ 可 schedule;pending 内容未变时保留,不重复 schedule
// - pending 的 start 在 request/schedule 时固定,update 无法改启动时刻
//   → 内容变了必须 end + request/schedule(或超出视野则 end),不能 .update / .none 保留
// - 无现场 / 已取消 / 已过谢幕:结束全部

/// 现有活动的最小摘要(由 actor 从 ActivityKit 读取后传入)
struct LiveActivityExisting: Equatable {
    var showID: String
    var isPending: Bool
    var state: ShowLiveActivityAttributes.ContentState
}

enum LiveActivityAction: Equatable {
    case keep(ShowLiveActivityAttributes.ContentState)
    case none
    case update(ShowLiveActivityAttributes.ContentState)
    case request(ShowLiveActivityAttributes.ContentState)
    case schedule(ShowLiveActivityAttributes.ContentState, start: Date)
    case endAll
}

enum LiveActivityPlanner {
    static let maxActiveDuration: TimeInterval = 8 * 3_600
    static let scheduleHorizon: TimeInterval = 7 * 86_400

    static func desiredState(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        coverFilename: String?,
        focusedPerformanceID: UUID? = nil,
        artistImageFilename: (String) -> String? = { _ in nil }
    ) -> (state: ShowLiveActivityAttributes.ContentState, activityEnd: Date)? {
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

            switch liveState.phase {
            case .dayEnded:
                return nil
            case .fullyEnded:
                // A later explicit closing can outlive the final scheduled set.
                guard CurrentShowTimeState(timing: snapshot.timing, now: now).kind == .today else { return nil }
                break

            case .active:
                let dayEnd: Date
                if let activeDayID = liveState.activeDayID,
                   let day = liveDays.first(where: { $0.id == activeDayID }),
                   let maxEnd = day.performances.map({ $0.endsAt }).max() {
                    dayEnd = snapshot.timing.resolvedSessions(calendar: snapshot.timing.eventCalendar(fallback: .current))
                        .first { $0.date == day.date }?.endsAt ?? maxEnd
                } else {
                    dayEnd = now.addingTimeInterval(TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600)
                }

                guard now < dayEnd else { return nil }

                let current = liveState.currentPerformances.first
                let also = liveState.currentPerformances.dropFirst().first
                let upcoming = liveState.upcomingPerformances.first
                // 场间:计时倒数到下一场开演(staleDate 也随之落在开演时刻)。
                let start = current?.startsAt ?? upcoming?.startsAt ?? now

                return (
                    ShowLiveActivityAttributes.ContentState(
                        showName: snapshot.name,
                        city: snapshot.city,
                        venueName: snapshot.venueName,
                        startDate: start,
                        endDate: dayEnd,
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
                        currentArtistImageFilename: image(current?.id),
                        alsoArtistImageFilename: image(also?.id),
                        nextArtistImageFilename: image(upcoming?.id)
                    ),
                    dayEnd
                )

            case .upcoming(let firstStartsAt):
                let upcoming = liveState.upcomingPerformances.first
                let activityEnd: Date
                if let activeDayID = liveState.activeDayID,
                   let day = liveDays.first(where: { $0.id == activeDayID }),
                   let maxEnd = day.performances.map({ $0.endsAt }).max() {
                    activityEnd = snapshot.timing.resolvedSessions(calendar: snapshot.timing.eventCalendar(fallback: .current))
                        .first { $0.date == day.date }?.endsAt ?? maxEnd
                } else {
                    activityEnd = firstStartsAt.addingTimeInterval(TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600)
                }

                return (
                    ShowLiveActivityAttributes.ContentState(
                        showName: snapshot.name,
                        city: snapshot.city,
                        venueName: snapshot.venueName,
                        startDate: firstStartsAt,
                        endDate: activityEnd,
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
                        nextArtistImageFilename: image(upcoming?.id)
                    ),
                    activityEnd
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

        return (
            ShowLiveActivityAttributes.ContentState(
                showName: snapshot.name,
                city: snapshot.city,
                venueName: snapshot.venueName,
                startDate: start,
                endDate: explicitEnd,
                timeZoneSecondsFromGMT: snapshot.timing.timeZoneSecondsFromGMT,
                endTimeZoneSecondsFromGMT: snapshot.timing.endTimeZoneSecondsFromGMT,
                timeZoneIdentifier: snapshot.timing.sessionTimeZoneIdentifier ?? snapshot.timing.timeZoneIdentifier,
                endTimeZoneIdentifier: snapshot.timing.endTimeZoneIdentifier,
                coverImageFilename: coverFilename,
                hasStarted: now >= start
            ),
            activityEnd
        )
    }

    static func earliestStart(activityStart: Date, activityEnd: Date) -> Date {
        min(activityStart, activityEnd.addingTimeInterval(-maxActiveDuration))
    }

    static func action(
        snapshot: WidgetShowSnapshot?,
        now: Date,
        existing: [LiveActivityExisting],
        coverFilename: String?,
        focusedPerformanceID: UUID? = nil,
        artistImageFilename: (String) -> String? = { _ in nil }
    ) -> LiveActivityAction {
        guard let desired = desiredState(
            snapshot: snapshot, now: now, coverFilename: coverFilename,
            focusedPerformanceID: focusedPerformanceID, artistImageFilename: artistImageFilename
        ),
              let snapshot else {
            return .endAll
        }

        let showID = snapshot.showID.uuidString
        let matching = existing.filter { $0.showID == showID }
        let earliest = earliestStart(activityStart: desired.state.startDate, activityEnd: desired.activityEnd)
        let inWindow = now >= earliest
        let pending = matching.filter(\.isPending)
        let hasStalePending = pending.contains { $0.state != desired.state }
        let hasUnchangedPending = pending.contains { $0.state == desired.state }

        if inWindow {
            if hasStalePending || matching.isEmpty {
                return .request(desired.state)
            }
            return .update(desired.state)
        }

        if hasUnchangedPending {
            return .keep(desired.state)
        }

        if earliest.timeIntervalSince(now) > scheduleHorizon {
            return matching.isEmpty ? .none : .endAll
        }

        return .schedule(desired.state, start: earliest)
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
