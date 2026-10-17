import SwiftUI
import WidgetKit

// MARK: - 内容模型
// 设计稿:Design 画布「实时活动」。四种状态共用一套版式:
// 左列 = 状态标签 + 大计时;右列 = 主角(艺人或演出名)+ 舞台/场馆 + 下一场一行。
// 红 = 正在演，金 = 等待开场。

struct LiveActivityContent {
    enum Mode {
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
    let title: String
    let subtitle: String?
    let timeRange: String?
    let progress: ClosedRange<Date>?
    let next: Next?
    /// 现场模式:主角艺人头像、舞台、同时在演;非 nil 时用「阵容」版式。
    var lineup: (avatar: String?, stage: String?, also: Also?)? = nil

    init(state: ShowLiveActivityAttributes.ContentState, isStale: Bool, now: Date = .now) {
        timerInterval = state.timerInterval
        let isLive = now >= state.startDate
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

        let isEnded = state.hasEnded(isStale: isStale, now: now)

        if isEnded {
            mode = .ended
            kicker = BSLocalization.text("已散场")
            caption = nil
            title = state.showName
            subtitle = state.venueName
            timeRange = nil
            progress = nil
            next = nil
        } else if let artist = state.currentArtistName {
            let start = state.currentStartsAt ?? state.startDate
            let end = state.currentEndsAt ?? state.endDate ?? state.startDate
            mode = .set
            kicker = BSLocalization.text("正在演出")
            // 与普通演出同一语义:正计时「已开场」，剩余交给进度条与静态结束时刻。
            caption = BSLocalization.text("已开场")
            title = artist
            let ends = BSLocalization.format("%@ 结束", clock(end))
            subtitle = state.currentStageName.map { BSLocalization.format("%1$@ · %2$@", $0, ends) } ?? ends
            timeRange = "\(clock(start))–\(clock(end))"
            progress = start < end ? start...end : nil
            next = upcoming
            if state.isFestivalDayActive {
                let also = state.alsoArtistName.map {
                    Also(artist: $0, stage: state.alsoStageName, image: state.alsoArtistImageFilename)
                }
                lineup = (state.currentArtistImageFilename, state.currentStageName, also)
            }
        } else if state.isFestivalDayActive, let artist = state.nextArtistName {
            // 场间:startDate 指向下一场开演。过点后 app 没来得及更新时,
            // 下一场就是正在演的那场,计时转为已开演时长。
            mode = isLive ? .set : .between
            kicker = BSLocalization.text(isLive ? "正在演出" : "下一场")
            caption = isLive ? BSLocalization.text("已开场") : nil
            title = artist
            subtitle = state.nextStageName
            timeRange = state.nextStartsAt.map(clock)
            nextStartText = timeRange
            progress = nil
            next = nil
            lineup = (state.nextArtistImageFilename, state.nextStageName, nil)
        } else if isLive {
            mode = .started
            kicker = BSLocalization.text("现场计时")
            caption = BSLocalization.text("已开场")
            title = state.showName
            subtitle = state.endDate.map { BSLocalization.format("%@ 散场", LiveActivityCopy.clockText($0, calendar: state.endCalendar)) }
                ?? state.venueName
            timeRange = nil
            // 普通演出:开场到预计散场的进度，与现场模式同一条进度条。
            progress = state.endDate.flatMap { $0 > state.startDate ? state.startDate...$0 : nil }
            next = nil
        } else {
            mode = .pre
            kicker = BSLocalization.text("现场计时")
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
        }
    }

    var showsWave: Bool { mode == .set }

    var nextStartText: String?

    /// 右上角:正在演给本场「HH:mm–HH:mm」，场间给下一场开演时刻。
    func cornerHint() -> String? {
        switch mode {
        case .set:
            return timeRange
        case .between:
            return nextStartText.map { BSLocalization.format("%@ 开场", $0) }
        case .pre, .started, .ended:
            return nil
        }
    }

    var kickerColor: Color {
        switch mode {
        case .set: WidgetTheme.liveTitle
        case .between: WidgetTheme.accent
        case .pre, .started, .ended: WidgetTheme.muted
        }
    }

    var timerColor: Color {
        switch mode {
        case .set, .started, .pre: WidgetTheme.foreground
        case .between, .ended: WidgetTheme.heroWarmGold
        }
    }

    var glowColor: Color {
        showsWave ? WidgetTheme.live : WidgetTheme.accent
    }
}

enum LiveActivityCopy {
    /// 24 小时制，时区使用活动所在地。
    static func clockText(_ date: Date, calendar: Calendar) -> String {
        BSDateFormat.clock(date, timeZone: calendar.timeZone)
    }
}

// MARK: - 计时文本
// Text(timerInterval:) 由系统时间驱动，在开场前保持零，散场后停止累计。

struct LiveActivityTimerText: View {
    let content: LiveActivityContent
    var fontSize: CGFloat
    var alignment: TextAlignment = .trailing

    var body: some View {
        Text(timerInterval: content.timerInterval, countsDown: false)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(content.timerColor)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(alignment)
    }
}
