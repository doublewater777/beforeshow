import SwiftUI
import WidgetKit

// MARK: - Festival widget variants
// 设计稿:Design 画布「小组件 · 音乐节各状态」「锁屏 · 音乐节各状态」。
// 有时刻表时，与首页现场模式同一口径：正在演 / 场间 / 今日首场 / DAY n 已结束 / 全部结束。
// 红 = 现在，金 = 想看，夜蓝 = 今日已结束。

struct WidgetFestivalNow {
    enum Phase {
        case live(main: LivePerformanceSnapshot, next: [LivePerformanceSnapshot])
        case between(slot: [LivePerformanceSnapshot], later: LivePerformanceSnapshot?)
        case firstSet(first: LivePerformanceSnapshot, later: [LivePerformanceSnapshot])
        /// `resumes` is 今天 / 明天 / a date, so festivals that skip days read right.
        case dayEnded(day: Int, next: [LivePerformanceSnapshot], resumes: String)
        case finished(days: Int, sets: Int, picks: Int)
    }

    /// nil:不在现场模式(例如音乐节前几天)，由普通倒计时接管。
    let phase: Phase?
    /// 开场前的第一场想看，用于倒计时下方的一行提示。
    let firstPick: LivePerformanceSnapshot?

    init?(snapshot: WidgetShowSnapshot?, now: Date) {
        guard let snapshot, let timetable = snapshot.timetable, !timetable.days.isEmpty else { return nil }
        let days = timetable.days.map { day in
            LiveDayInput(id: day.id, date: day.date, performances: day.performances.map {
                LivePerformanceInput(
                    id: $0.id, artistName: $0.artistName, stageID: $0.stageID, stageName: $0.stageName,
                    startsAt: $0.startsAt, endsAt: $0.endsAt, isInterested: $0.isInterested
                )
            })
        }.filter { !$0.performances.isEmpty }.sorted { $0.date < $1.date }
        let state = LiveModeStateEngine.calculate(days: days, now: now)
        let upcoming = state.upcomingPerformances.sorted { $0.startsAt < $1.startsAt }
        firstPick = upcoming.first(where: \.isInterested)

        switch state.phase {
        case .active:
            if let main = state.currentPerformances.first {
                phase = .live(main: main, next: Array(upcoming.prefix(2)))
            } else if let first = upcoming.first {
                let slot = upcoming.filter { $0.startsAt == first.startsAt }
                phase = .between(slot: slot, later: upcoming.dropFirst(slot.count).first)
            } else {
                phase = nil
            }
        case .upcoming(let start):
            // 与首页一致：演出日当天才进现场模式。
            if Calendar.current.isDate(start, inSameDayAs: now), let first = upcoming.first {
                phase = .firstSet(first: first, later: Array(upcoming.dropFirst().prefix(2)))
            } else {
                phase = nil
            }
        case .dayEnded:
            let ended = days.lastIndex { $0.performances.allSatisfy { $0.endsAt <= now } } ?? 0
            let resumes = upcoming.first.map {
                FestivalDay.word(for: $0.startsAt, distance: FestivalDay.distance(from: now, to: $0.startsAt, calendar: .current), calendar: .current)
            } ?? BSLocalization.text("明天")
            phase = .dayEnded(day: ended + 1, next: Array(upcoming.prefix(3)), resumes: resumes)
        case .fullyEnded:
            let all = days.flatMap(\.performances)
            phase = snapshot.timing.endedAt == nil && !all.isEmpty
                ? .finished(days: days.count, sets: all.count, picks: all.filter(\.isInterested).count)
                : nil
        }
    }

    /// Set boundaries inside the window, so the widget flips exactly when a set starts or ends.
    static func boundaries(in snapshot: WidgetShowSnapshot?, from now: Date, to end: Date) -> [Date] {
        guard let timetable = snapshot?.timetable else { return [] }
        var dates = timetable.days.flatMap(\.performances).flatMap { [$0.startsAt, $0.endsAt] }
        // Day-ended copy flips at the 06:00 day turn (明天 → 今天) and when the next
        // day comes within the engine's lead time (back to 今日首场).
        dates += timetable.days.compactMap { $0.performances.map(\.startsAt).min()?.addingTimeInterval(-LiveModeStateEngine.nextDayLead) }
        dates += FestivalDay.turns(after: now, through: end, calendar: .current)
        return dates.filter { $0 > now && $0 <= end }
    }
}

enum FestivalWidgetCopy {
    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// 「♥ 18:00 椅子乐团 爱舞台」一行：想看给金心，快开始给红环。
struct FestivalNextLine: View {
    let performance: LivePerformanceSnapshot
    var showsTime = true
    var showsStage = false
    var fontSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 5) {
            if performance.isStartingSoon {
                Circle()
                    .strokeBorder(WidgetTheme.live, lineWidth: 1.2)
                    .frame(width: 5, height: 5)
            } else if performance.isInterested {
                Image(systemName: "heart.fill")
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(WidgetTheme.accent)
            }
            if showsTime {
                Text(FestivalWidgetCopy.clock(performance.startsAt))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.muted)
            }
            Text(performance.artistName)
                .fontWeight(.semibold)
                .foregroundStyle(WidgetTheme.foreground)
            if showsStage {
                Text(performance.stageName)
                    .foregroundStyle(WidgetTheme.dim)
            }
        }
        .font(.system(size: fontSize))
        .lineLimit(1)
    }
}

private struct FestivalTag: View {
    let text: LocalizedStringKey
    let color: Color
    var dot = false
    var moon = false

    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(WidgetTheme.live).frame(width: 7, height: 7) }
            if moon { Image(systemName: "moon.fill").font(.system(size: 9)) }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .lineLimit(1)
        }
        .foregroundStyle(color)
    }
}

private struct FestivalSetProgress: View {
    let performance: LivePerformanceSnapshot

    var body: some View {
        ProgressView(timerInterval: performance.startsAt...performance.endsAt, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(WidgetTheme.live)
        .labelsHidden()
    }
}

private struct FestivalBigClock: View {
    let date: Date
    var size: CGFloat = 40
    var color: Color = WidgetTheme.heroIvory

    var body: some View {
        Text(FestivalWidgetCopy.clock(date))
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct FestivalCountdown: View {
    let start: Date

    var body: some View {
        Text(timerInterval: Date.now...max(start, Date.now), countsDown: true, showsHours: false)
            .font(.system(size: 40, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(WidgetTheme.heroWarmGold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct FestivalStats: View {
    let days: Int
    let sets: Int
    let picks: Int
    var long = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            stat(days, long ? "天" : "天", WidgetTheme.foreground)
            stat(sets, long ? "场演出" : "场", WidgetTheme.foreground)
            stat(picks, long ? "场想看" : "想看", WidgetTheme.accent)
        }
    }

    private func stat(_ value: Int, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.muted)
        }
    }
}

// MARK: - 小号

struct FestivalSmallView: View {
    let phase: WidgetFestivalNow.Phase
    let showName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .live(let main, let next):
                FestivalTag(text: "正在演出", color: WidgetTheme.liveTitle, dot: true)
                Text(main.artistName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 10)
                Text(main.stageName)
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.dim)
                    .lineLimit(1)
                    .padding(.top, 3)
                Spacer(minLength: 6)
                FestivalSetProgress(performance: main)
                if let first = next.first {
                    FestivalNextLine(performance: first).padding(.top, 6)
                }
            case .between(let slot, _):
                FestivalTag(text: "下一场", color: WidgetTheme.accent)
                Spacer(minLength: 4)
                if let first = slot.first {
                    FestivalCountdown(start: first.startsAt)
                    Spacer(minLength: 6)
                    Text(first.artistName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                    Text("\(first.stageName) · \(FestivalWidgetCopy.clock(first.startsAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetTheme.dim)
                        .lineLimit(1)
                }
            case .firstSet(let first, _):
                FestivalTag(text: "今日首场", color: WidgetTheme.accent)
                Spacer(minLength: 4)
                FestivalBigClock(date: first.startsAt)
                Spacer(minLength: 6)
                FestivalNextLine(performance: first, showsTime: false, fontSize: 13)
                Text(first.stageName)
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.dim)
                    .lineLimit(1)
            case .dayEnded(let day, let next, let resumes):
                FestivalTag(text: "DAY \(day) 已结束", color: WidgetTheme.night, moon: true)
                Spacer(minLength: 4)
                if let first = next.first {
                    Text(resumes)
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetTheme.muted)
                    FestivalBigClock(date: first.startsAt, color: WidgetTheme.foreground)
                    Spacer(minLength: 6)
                    FestivalNextLine(performance: first, showsTime: false)
                }
            case .finished(let days, let sets, let picks):
                FestivalTag(text: "全部结束", color: WidgetTheme.accent)
                Text(showName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(2)
                    .padding(.top, 10)
                Spacer(minLength: 6)
                FestivalStats(days: days, sets: sets, picks: picks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 中号

struct FestivalMediumView<Cover: View>: View {
    let phase: WidgetFestivalNow.Phase
    let showName: String
    @ViewBuilder let cover: () -> Cover

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cover()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .live(let main, let next):
            HStack {
                FestivalTag(text: "正在演出", color: WidgetTheme.liveTitle, dot: true)
                Spacer(minLength: 4)
                Text("\(FestivalWidgetCopy.clock(main.startsAt))–\(FestivalWidgetCopy.clock(main.endsAt))")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.muted)
            }
            Text(main.artistName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 8)
            Text(main.stageName)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
                .lineLimit(1)
                .padding(.top, 3)
            FestivalSetProgress(performance: main).padding(.top, 8)
            Spacer(minLength: 4)
            ForEach(next) { perf in
                FestivalNextLine(performance: perf, showsStage: true).padding(.top, 3)
            }
        case .between(let slot, let later):
            if let first = slot.first {
                HStack {
                    FestivalTag(text: "下一场", color: WidgetTheme.accent)
                    Spacer(minLength: 4)
                    Text(FestivalWidgetCopy.clock(first.startsAt))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.muted)
                }
                Spacer(minLength: 2)
                FestivalCountdown(start: first.startsAt)
                Text(slot.prefix(2).map(\.artistName).joined(separator: " / "))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 4)
                Spacer(minLength: 4)
                if let later {
                    FestivalNextLine(performance: later, showsStage: true)
                }
            }
        case .firstSet(let first, let later):
            FestivalTag(text: "今日首场", color: WidgetTheme.accent)
            Spacer(minLength: 2)
            FestivalBigClock(date: first.startsAt)
            Text(first.artistName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
                .lineLimit(1)
                .padding(.top, 4)
            Spacer(minLength: 4)
            ForEach(later) { perf in
                FestivalNextLine(performance: perf, showsStage: true).padding(.top, 3)
            }
        case .dayEnded(let day, let next, let resumes):
            FestivalTag(text: "DAY \(day) 已结束", color: WidgetTheme.night, moon: true)
            if let first = next.first {
                Text("\(resumes) \(FestivalWidgetCopy.clock(first.startsAt)) 继续")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
            Spacer(minLength: 4)
            ForEach(next) { perf in
                FestivalNextLine(performance: perf, showsStage: true).padding(.top, 3)
            }
        case .finished(let days, let sets, let picks):
            FestivalTag(text: "全部结束", color: WidgetTheme.accent)
            Text("\(days) 天辛苦了")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
                .lineLimit(1)
                .padding(.top, 8)
            Text(showName)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
                .lineLimit(1)
                .padding(.top, 3)
            Spacer(minLength: 4)
            FestivalStats(days: days, sets: sets, picks: picks, long: true)
        }
    }
}

// MARK: - 锁屏(单色)

struct FestivalInlineView: View {
    let phase: WidgetFestivalNow.Phase

    var body: some View {
        Group {
            switch phase {
            case .live(let main, _):
                Text("\(Image(systemName: "waveform")) \(main.artistName) · \(main.stageName)")
            case .between(let slot, _):
                Text("下一场 \(FestivalWidgetCopy.clock(slot.first?.startsAt ?? .now)) · \(slot.first?.artistName ?? "")")
            case .firstSet(let first, _):
                Text("今日首场 \(FestivalWidgetCopy.clock(first.startsAt)) · \(first.artistName)")
            case .dayEnded(let day, let next, let resumes):
                Text("DAY \(day) 已结束 · \(resumes) \(FestivalWidgetCopy.clock(next.first?.startsAt ?? .now))")
            case .finished(_, _, let picks):
                Text("全部结束 · 想看 \(picks) 场")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

struct FestivalCircularView: View {
    let phase: WidgetFestivalNow.Phase

    var body: some View {
        switch phase {
        case .live(let main, _):
            ProgressView(timerInterval: main.startsAt...main.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                label(Text(timerInterval: Date.now...main.endsAt, countsDown: true, showsHours: false), caption: "剩余")
            }
            .progressViewStyle(.circular)
        case .between(let slot, _):
            ZStack {
                AccessoryWidgetBackground()
                label(Text(timerInterval: Date.now...max(slot.first?.startsAt ?? .now, .now), countsDown: true, showsHours: false), caption: "下一场")
            }
        case .firstSet(let first, _):
            ZStack {
                AccessoryWidgetBackground()
                label(Text(FestivalWidgetCopy.clock(first.startsAt)), caption: "首场", captionOnTop: true)
            }
        case .dayEnded(_, let next, let resumes):
            ZStack {
                AccessoryWidgetBackground()
                label(Text(FestivalWidgetCopy.clock(next.first?.startsAt ?? .now)), caption: LocalizedStringKey(resumes), captionOnTop: true)
            }
        case .finished:
            ZStack {
                AccessoryWidgetBackground()
                label(Text("结束"), caption: "全部", captionOnTop: true)
            }
        }
    }

    private func label(_ value: Text, caption: LocalizedStringKey, captionOnTop: Bool = false) -> some View {
        VStack(spacing: 0) {
            if captionOnTop { Text(caption).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
            value
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            if !captionOnTop { Text(caption).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
        }
    }
}

struct FestivalRectangularView: View {
    let phase: WidgetFestivalNow.Phase
    let showName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch phase {
            case .live(let main, let next):
                lines(Text("\(Image(systemName: "waveform")) \(main.stageName)"), Text(main.artistName),
                      next.first.map { Text("\(FestivalWidgetCopy.clock($0.startsAt)) \($0.artistName)") })
            case .between(let slot, _):
                if let first = slot.first {
                    lines(Text("下一场 · \(FestivalWidgetCopy.clock(first.startsAt))"), Text(first.artistName), Text(first.stageName))
                }
            case .firstSet(let first, _):
                lines(Text("今日首场 · \(FestivalWidgetCopy.clock(first.startsAt))"), Text(first.artistName), Text(first.stageName))
            case .dayEnded(let day, let next, let resumes):
                lines(Text("DAY \(day) 已结束"),
                      Text("\(resumes) \(FestivalWidgetCopy.clock(next.first?.startsAt ?? .now)) 继续"),
                      next.first.map { Text($0.artistName) })
            case .finished(let days, _, let picks):
                lines(Text("全部结束"), Text(showName), Text("\(days) 天 · 想看 \(picks) 场"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lines(_ top: Text, _ title: Text, _ bottom: Text?) -> some View {
        top.font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        title.font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
        if let bottom {
            bottom.font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
