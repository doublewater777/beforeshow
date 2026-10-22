import SwiftUI
import WidgetKit

// MARK: - 内容模型
// 设计稿:Design 画布「实时活动」。四种状态共用一套版式:
// 左列 = 状态标签 + 大计时;右列 = 主角(艺人或演出名)+ 舞台/场馆 + 下一场一行。
// 红 = 正在演，金 = 等待开场。

struct LiveActivityContent {
    enum Mode {
        /// 想看演出开演前 15 分钟提醒
        case reminder
        /// 时刻表里正在演的一场
        case set
        /// 场间:倒数下一场
        case between
        /// 开场前(含音乐节今日首场前)
        case pre
        /// 普通演出已开场
        case started
        /// 已散场
        case ended
    }

    struct Next {
        let time: String
        let artist: String
        let stage: String?
        let isInterested: Bool
        let isSoon: Bool
        var image: String? = nil
    }

    /// 与主现场同时在演的另一位(现场模式)。
    struct Also {
        let artist: String
        let stage: String?
        let image: String?
    }

    let mode: Mode
    let kicker: String
    let timerInterval: ClosedRange<Date>
    let caption: String?
    let isStale: Bool
    let title: String
    let subtitle: String?
    let timeRange: String?
    let progress: ClosedRange<Date>?
    let next: Next?
    var reminderSummary: String? = nil
    /// 现场模式:主角艺人头像、舞台、同时在演;非 nil 时用「阵容」版式。
    var lineup: (avatar: String?, stage: String?, also: Also?)? = nil

    init(state: ShowLiveActivityAttributes.ContentState, isStale: Bool, now: Date = .now) {
        self.isStale = isStale || now >= state.staleDate
        let currentEnded = state.currentEndsAt.map { now >= $0 } ?? false
        let clock = { (date: Date) in LiveActivityCopy.clockText(date, calendar: state.startCalendar) }
        let upcoming = state.nextArtistName.map { artist in
            Next(
                time: state.nextStartsAt.map(clock) ?? "",
                artist: artist,
                stage: state.nextStageName,
                isInterested: state.isInterestedNext,
                isSoon: state.isNextStartingSoon,
                image: state.nextArtistImageFilename
            )
        }

        let standardPhase = state.standardPhase(at: now, isStale: isStale)

        let hasValidReminder: Bool = {
            guard state.isReminderActive, let startsAt = state.reminderStartsAt else { return false }
            let expiresAt = state.reminderExpiresAt ?? startsAt
            return now < expiresAt
        }()

        if standardPhase == .ended {
            mode = .ended
            switch state.endKind {
            case "tracking": kicker = BSLocalization.text("本次跟踪已结束")
            case "festival": kicker = BSLocalization.text("今日演出已结束")
            default:
                if state.hasTimetable == true || state.isFestivalDayActive {
                    kicker = BSLocalization.text("今日演出已结束")
                } else {
                    kicker = state.endDate == nil ? BSLocalization.text("本次跟踪已结束") : BSLocalization.text("已散场")
                }
            }
            caption = nil
            title = state.showName
            subtitle = state.venueName
            timeRange = nil
            progress = nil
            next = nil
            timerInterval = state.timerInterval
        } else if hasValidReminder, let reminderArtist = state.reminderArtistName {
            mode = .reminder
            kicker = BSLocalization.text("快开始了")
            caption = nil
            title = reminderArtist
            let startsText = state.reminderStartsAt.map { LiveActivityCopy.reminderOpening($0, calendar: state.startCalendar) }
            if let stage = state.reminderStageName, !stage.isEmpty {
                subtitle = startsText.map { BSLocalization.format("%1$@ · %2$@", stage, $0) } ?? stage
            } else {
                subtitle = startsText
            }
            timeRange = state.reminderStartsAt.map(clock)
            nextStartText = timeRange
            progress = nil
            let samePerformance: Bool
            if let reminderID = state.reminderPerformanceID, let nextID = state.nextPerformanceID {
                samePerformance = reminderID == nextID && state.nextStartsAt == state.reminderStartsAt
            } else {
                samePerformance = state.nextArtistName == reminderArtist && state.nextStartsAt == state.reminderStartsAt
                    && state.nextStageName == state.reminderStageName
            }
            next = samePerformance ? nil : upcoming
            let additionalCount = (state.reminderCount ?? state.reminderPerformanceIDs?.count ?? 1) - 1
            reminderSummary = additionalCount > 0 ? LiveActivityCopy.additionalReminders(additionalCount) : nil
            lineup = (state.reminderArtistImageFilename, state.reminderStageName, nil)
            let target = state.reminderStartsAt ?? state.endBoundary
            timerInterval = min(now, target)...target
        } else if let artist = state.currentArtistName, !currentEnded {
            let start = state.currentStartsAt ?? state.startDate
            let end = state.currentEndsAt ?? state.endDate ?? state.startDate
            mode = .set
            kicker = BSLocalization.text("正在演出")
            // 与普通演出同一语义:正计时「已开场」，剩余交给进度条与静态结束时刻。
            caption = BSLocalization.text("已开场")
            title = artist
            let ends = BSLocalization.format("%@ 结束", clock(end))
            subtitle = state.currentStageName.map { BSLocalization.format("%1$@ · %2$@", $0, ends) } ?? ends
            timeRange = state.startCalendar.isDate(start, inSameDayAs: end)
                ? "\(clock(start))–\(clock(end))"
                : BSLocalization.format("%1$@–次日 %2$@", clock(start), clock(end))
            progress = start < end ? start...end : nil
            next = upcoming
            if state.isFestivalDayActive {
                let also = state.alsoArtistName.map {
                    Also(artist: $0, stage: state.alsoStageName, image: state.alsoArtistImageFilename)
                }
                lineup = (state.currentArtistImageFilename, state.currentStageName, also)
            }
            timerInterval = state.timerInterval
        } else if state.isFestivalDayActive, let artist = state.nextArtistName {
            // 场间:倒数下一场开演。
            mode = .between
            kicker = BSLocalization.text("下一场")
            caption = nil
            title = artist
            subtitle = state.nextStageName
            timeRange = state.nextStartsAt.map(clock)
            nextStartText = timeRange
            progress = nil
            next = nil
            lineup = (state.nextArtistImageFilename, state.nextStageName, nil)
            let target = state.nextStartsAt ?? state.endBoundary
            timerInterval = min(now, target)...target
        } else if standardPhase == .live {
            mode = .started
            kicker = BSLocalization.text("已开场")
            caption = BSLocalization.text("已开场")
            title = state.showName
            subtitle = state.endDate.map { LiveActivityCopy.expectedEnd($0, state: state) }
                ?? state.venueName
            timeRange = nil
            // 普通演出:开场到预计散场的进度，与现场模式同一条进度条。
            progress = state.endDate.flatMap { $0 > state.startDate ? state.startDate...$0 : nil }
            next = nil
            timerInterval = state.timerInterval
        } else {
            mode = .pre
            kicker = BSLocalization.text("距离开场")
            caption = nil
            title = state.showName
            let opening = BSLocalization.format("%@ 开场", clock(state.startDate))
            if let venue = state.venueName, !venue.isEmpty {
                subtitle = BSLocalization.format("%1$@ · %2$@", opening, venue)
            } else {
                subtitle = opening
            }
            timeRange = nil
            progress = nil
            next = upcoming
            timerInterval = min(now, state.startDate)...state.startDate
        }
    }

    var showsWave: Bool { (mode == .set || mode == .started) && !isStale }

    var nextStartText: String?

    /// 右上角:正在演给本场「HH:mm–HH:mm」，场间给下一场开演时刻。
    func cornerHint() -> String? {
        switch mode {
        case .set:
            return timeRange
        case .reminder:
            return nextStartText.map { BSLocalization.format("%@ 开演", $0) }
        case .between:
            return nextStartText.map { BSLocalization.format("%@ 开场", $0) }
        case .pre, .started, .ended:
            return nil
        }
    }

    var kickerColor: Color {
        switch mode {
        case .set, .started: WidgetTheme.liveTitle
        case .between, .reminder: WidgetTheme.accent
        case .pre, .ended: WidgetTheme.muted
        }
    }

    var timerColor: Color {
        switch mode {
        case .set, .started, .pre: WidgetTheme.foreground
        case .between, .ended, .reminder: WidgetTheme.heroWarmGold
        }
    }

    var glowColor: Color {
        showsWave ? WidgetTheme.live : WidgetTheme.accent
    }
}

enum LiveActivityCopy {
    static func reminderOpening(_ date: Date, calendar: Calendar) -> String {
        BSLocalization.format("%@ 开演", clockText(date, calendar: calendar))
    }

    static func additionalReminders(_ count: Int) -> String {
        BSLocalization.format("另有 %lld 场想看即将开演", count)
    }

    static func expectedEnd(_ date: Date, state: ShowLiveActivityAttributes.ContentState) -> String {
        let clock = clockText(date, calendar: state.endCalendar)
        let calendar = state.startCalendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: state.startDate),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return BSLocalization.format("预计次日 %@ 散场", clock) }
        let time = days == 0 ? clock : BSDateFormat.dateTime(date, timeZone: state.endCalendar.timeZone)
        return BSLocalization.format("预计 %@ 散场", time)
    }

    /// 24 小时制，时区使用活动所在地。
    static func clockText(_ date: Date, calendar: Calendar) -> String {
        BSDateFormat.clock(date, timeZone: calendar.timeZone)
    }
}

// MARK: - 计时文本
// 等待开场时按目标日期倒计时；开场后用有结束边界的系统正计时。
// 数字由系统驱动；完整状态文案的跨边界切换仍取决于 ActivityKit 重新渲染。

struct LiveActivityTimerText: View {
    let content: LiveActivityContent
    var fontSize: CGFloat
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if content.mode == .pre || content.mode == .between || content.mode == .reminder {
                Text(timerInterval: content.timerInterval, countsDown: true)
            } else {
                Text(timerInterval: content.timerInterval, countsDown: false)
            }
        }
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(content.timerColor)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .multilineTextAlignment(alignment)
    }
}
