import SwiftUI

// MARK: - Lineup Parser

/// 音乐节阵容解析:艺人字段按 ASCII 逗号 / 中文全角逗号 / 顿号 / 斜杠拆分;
/// 拆出 ≥ 3 个名字才视为音乐节阵容(只读展示,不做交互)。
enum HomeLineupParser {
    static let separators = CharacterSet(charactersIn: ",，、/")

    static func names(from artist: String?) -> [String] {
        guard let artist else { return [] }
        return artist
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func lineup(from artist: String?) -> [String] {
        let parsed = names(from: artist)
        return parsed.count >= 3 ? parsed : []
    }
}

// HomeShowPhase 已移至 Shared/HomeShowPhase.swift（app 与 widget 共用；含 dayEnded 文案）。

// MARK: - Home Countdown Lockup

enum HomeCountdownDisplayState: Equatable {
    case countdownDays(Int)
    case countdownClock(hours: Int, minutes: Int, seconds: Int, urgent: Bool)
    case live
    case askingEnd
    case confirmedEnded
    case dayEnded
    case postponed
    case canceled
}

enum HomeCountdownPresentationPolicy {
    static func state(
        for show: Show,
        timeState: CurrentShowTimeState,
        now: Date
    ) -> HomeCountdownDisplayState {
        switch timeState.kind {
        case .canceled:
            return .canceled
        case .postponed:
            return .postponed
        case .dayEnded:
            return .dayEnded
        case .postShow, .ended:
            return show.endedAt == nil ? .askingEnd : .confirmedEnded
        case .before, .today:
            let phase = HomeShowPhase(timeState: timeState, now: now)
            guard phase == .live else {
                guard let total = remainingSeconds(to: timeState.effectiveStartTime, from: now) else {
                    return .countdownClock(hours: 0, minutes: 0, seconds: 0, urgent: false)
                }
                if total >= 86_400 {
                    return .countdownDays(total / 86_400)
                }
                return clockState(total)
            }
            return .live
        }
    }

    private static func clockState(_ total: Int) -> HomeCountdownDisplayState {
        let total = max(0, total)
        return .countdownClock(
            hours: total / 3_600,
            minutes: (total % 3_600) / 60,
            seconds: total % 60,
            urgent: total < 3_600
        )
    }

    private static func remainingSeconds(to start: Date?, from now: Date) -> Int? {
        guard let start else { return nil }
        return max(0, Int(start.timeIntervalSince(now)))
    }
}

enum HomeShowIdentityPresentation {
    static func statusPillText(
        for timeState: CurrentShowTimeState,
        city: String?,
        now: Date
    ) -> String {
        switch timeState.kind {
        case .before:
            return timeState.isDatedPostponement ? "新日期" : "下一场"
        case .today:
            guard let start = timeState.effectiveStartTime, now >= start else {
                return citySiteText("今天开场", city: city)
            }
            return "LIVE · 开场中"
        case .dayEnded:
            return citySiteText("已落幕", city: city)
        case .postShow:
            return citySiteText("已落幕", city: city)
        case .ended:
            return citySiteText("已落幕", city: city)
        case .canceled:
            return "已取消"
        case .postponed:
            return "延期 · 时间待定"
        }
    }

    static func statusText(
        for timeState: CurrentShowTimeState,
        now: Date
    ) -> String {
        switch timeState.kind {
        case .before: return "开场前"
        case .today:
            guard let start = timeState.effectiveStartTime, now >= start else {
                return "今天开场"
            }
            return "正在现场"
        case .dayEnded: return "今日已落幕"
        case .postShow: return "散场后"
        case .ended: return "已结束"
        case .canceled: return "已取消"
        case .postponed: return "时间待定"
        }
    }

    private static func citySiteText(_ prefix: String, city: String?) -> String {
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let city, !city.isEmpty else { return prefix }
        return "\(prefix) · \(city)站"
    }

    static func venueSummary(venue: String?, city: String?) -> String? {
        let venue = trimmed(venue)
        let city = trimmed(city)
        let cityText = {
            guard let city else { return nil as String? }
            guard let venue else { return city }
            guard !venue.localizedCaseInsensitiveContains(city) else { return nil }
            return city
        }()

        let summary = [venue, cityText].compactMap { $0 }.joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }

    static func dateText(
        for show: Show,
        timeState: CurrentShowTimeState,
        calendar: Calendar = .current
    ) -> String? {
        guard timeState.hasKnownEffectiveDate else { return nil }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "zh_Hans_CN")
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy.MM.dd E"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_Hans_CN")
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"

        if CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar),
           let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar) {
            var daily = timeFormatter.string(from: show.startTime)
            if let endTime = show.endTime {
                daily += "-\(timeFormatter.string(from: endTime))"
            }
            let year = calendar.component(.year, from: show.effectiveDate)
            return "\(year).\(monthDayText(show.effectiveDate, calendar: calendar))-\(monthDayText(endDay, calendar: calendar)) · 每日 \(daily)"
        }

        let base = "\(dayFormatter.string(from: show.effectiveDate)) \(timeFormatter.string(from: show.startTime))"
        guard let start = timeState.effectiveStartTime,
              let end = timeState.effectiveEndTime,
              end > start else {
            return base
        }

        let minutes = Int(end.timeIntervalSince(start)) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        let duration: String
        if hours > 0 && rest > 0 {
            duration = "\(hours) 小时 \(rest) 分"
        } else if hours > 0 {
            duration = "\(hours) 小时"
        } else {
            duration = "\(max(1, rest)) 分钟"
        }
        return "\(base) · 预计演出 \(duration)"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func monthDayText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", components.month ?? 0, components.day ?? 0)
    }
}

/// V4 首页倒计时卡片:封面之后的深色卡片。
/// pre 远场超大天数、当天秒级时钟、临近 1 小时金色时钟;
/// live 脉冲 + 已进行;ended 冷静收束;inactive 文本态(时间待定 / 已取消)。
struct HomeCountdownLockup: View {
    let show: Show
    var onEndShow: (() -> Void)? = nil
    var onCompanion: (() -> Void)? = nil
    var onMemoryFragments: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timeState = CurrentShowTimeState(show: show, now: context.date)
            let phase = HomeShowPhase(timeState: timeState, now: context.date)
            lockup(phase: phase, timeState: timeState, now: context.date)
        }
    }

    @ViewBuilder
    private func lockup(phase: HomeShowPhase, timeState: CurrentShowTimeState, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow(phase: phase, timeState: timeState, now: now)
                .padding(.bottom, 8)

            Text(show.name)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.45)
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            let dateText = HomeShowIdentityPresentation.dateText(for: show, timeState: timeState)

            let venueSummary = HomeShowIdentityPresentation.venueSummary(
                venue: show.venueName,
                city: show.city
            )

            if dateText != nil || venueSummary != nil {
                Text([dateText, venueSummary].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            }

            VStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .pre:
                    preCountdown(timeState: timeState, now: now)
                case .live:
                    liveStatus(timeState: timeState, now: now)
                case .ended:
                    if timeState.kind == .dayEnded {
                        endedStatus(timeState: timeState)
                    } else if show.endedAt == nil {
                        askingEndStatus
                    } else {
                        endedStatus(timeState: timeState)
                    }
                case .inactive:
                    inactiveStatus(timeState: timeState)
                }
            }
            .padding(.top, 10)

            if let action = availablePrimaryAction(phase: phase, timeState: timeState) {
                primaryActionButton(action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 9)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(BSColor.Stage.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [BSColor.Stage.accent.opacity(0.07), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.55)
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .accessibilityElement(children: onEndShow == nil ? .combine : .contain)
    }

    private func statusRow(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        now: Date
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(for: phase, timeState: timeState))
                    .frame(width: 6, height: 6)

                Text(HomeShowIdentityPresentation.statusPillText(
                    for: timeState,
                    city: show.city,
                    now: now
                ))
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.65)
                    .foregroundColor(statusColor(for: phase, timeState: timeState))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                Capsule()
                    .stroke(statusBorderColor(for: phase, timeState: timeState), lineWidth: 1)
            )

            Spacer(minLength: 0)

            Text(modeLabel(for: phase, timeState: timeState))
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.45)
                .foregroundColor(modeLabelColor(for: phase))
                .lineLimit(1)
        }
    }

    private func statusColor(
        for phase: HomeShowPhase,
        timeState: CurrentShowTimeState
    ) -> Color {
        switch phase {
        case .pre: return timeState.isDatedPostponement ? BSColor.Accent.warm : BSColor.Stage.accent
        case .live: return BSColor.Stage.liveTitle
        case .ended: return Color.white.opacity(0.70)
        case .inactive:
            return timeState.kind == .canceled ? Color.white.opacity(0.70) : BSColor.Accent.warm
        }
    }

    private func statusBorderColor(
        for phase: HomeShowPhase,
        timeState: CurrentShowTimeState
    ) -> Color {
        switch phase {
        case .pre:
            return (timeState.isDatedPostponement ? BSColor.Accent.warm : BSColor.Stage.accent).opacity(0.24)
        case .live: return BSColor.Stage.live.opacity(0.32)
        case .ended: return Color.white.opacity(0.11)
        case .inactive:
            return timeState.kind == .canceled
                ? Color.white.opacity(0.11)
                : BSColor.Accent.warm.opacity(0.30)
        }
    }

    private func modeLabel(
        for phase: HomeShowPhase,
        timeState: CurrentShowTimeState
    ) -> String {
        switch phase {
        case .pre:
            return timeState.kind == .today ? "TONIGHT" : "COUNTDOWN"
        case .live:
            return "ON STAGE"
        case .ended:
            return "ENDED"
        case .inactive:
            return "TBD"
        }
    }

    private func modeLabelColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Stage.accent.opacity(0.58)
        case .live: return BSColor.Stage.liveTitle.opacity(0.72)
        case .ended, .inactive: return BSColor.Stage.dim
        }
    }

    // MARK: pre:渐进精度倒计时
    // 精度随临近程度收束:>1 天只到「天」超大节拍,<24h 秒开始跳,<1h 使用分:秒。

    @ViewBuilder
    private func preCountdown(timeState: CurrentShowTimeState, now: Date) -> some View {
        if let total = Self.remainingSeconds(to: timeState.effectiveStartTime, from: now) {
            if total >= 86_400 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("\(total / 86_400)")
                            .font(.system(size: 72, weight: .thin))
                            .tracking(-2.5)
                            .monospacedDigit()
                            .foregroundStyle(Self.heroNumberGradient)
                            // 设计稿 line-height .94:系统字行高约 1.19 倍,负 padding 收掉多余行高
                            .padding(.vertical, -9)
                        Text("天")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    if timeState.isDatedPostponement {
                        Text("原定 \(Self.originalDateText(for: show))")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(BSColor.Stage.dim)
                            .padding(.top, 10)
                    }
                }
            } else if total >= 3_600 {
                Text(Self.clockText(total, forceHours: true))
                    .font(.system(size: 54, weight: .thin))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundColor(BSColor.Stage.foreground)
            } else {
                Text(Self.clockText(total, forceHours: false))
                    .font(.system(size: 54, weight: .thin))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(Self.heroNumberGradient)
            }
        } else {
            Text("--")
                .font(.system(size: 54, weight: .thin))
                .monospacedDigit()
                .foregroundColor(BSColor.Stage.dim)
        }
    }

    // MARK: live:脉冲 + 已进行 + 散场确认入口

    private func liveStatus(timeState: CurrentShowTimeState, now: Date) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HomeLivePulse(reduceMotion: reduceMotion)

                Text("正在现场")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(BSColor.Stage.liveTitle)

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text(Self.elapsedText(since: timeState.effectiveStartTime, now: now))
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.3)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text("已开场")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(BSColor.Stage.dim)
                }
            }
            .padding(.vertical, 4)

        }
    }

    // MARK: Primary action:单一主行动随生命周期切换
    // pre → 约人同行;live → 结束现场;ended(未确认) → 确认已结束;其余不出现。
    // 避免 live/ended 用同一句「结束现场」,让确认动作与所处阶段语气一致。

    enum PrimaryAction: Equatable {
        case end(live: Bool)
        case companion
        case memoryFragments
    }

    private func availablePrimaryAction(phase: HomeShowPhase, timeState: CurrentShowTimeState) -> PrimaryAction? {
        Self.primaryAction(
            phase: phase,
            timeState: timeState,
            hasConfirmedEnd: show.endedAt != nil,
            hasEndHandler: onEndShow != nil
        )
    }

    nonisolated static func primaryAction(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        hasConfirmedEnd: Bool,
        hasEndHandler: Bool
    ) -> PrimaryAction? {
        guard !hasConfirmedEnd else { return nil }
        switch phase {
        case .pre:
            return .companion
        case .live:
            return hasEndHandler ? .end(live: true) : nil
        case .ended:
            if timeState.kind == .postShow || timeState.kind == .ended {
                return hasEndHandler ? .end(live: false) : nil
            }
            return .memoryFragments
        case .inactive:
            return nil
        }
    }

    private func primaryActionButton(_ action: PrimaryAction) -> some View {
        let title = primaryActionTitle(action)
        let handler = primaryActionHandler(action)

        return Button(action: handler) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(BSColor.Stage.liveTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(BSColor.Stage.live.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(BSColor.Stage.live.opacity(0.32), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint(for: action))
        .padding(.top, 8)
    }

    private func primaryActionTitle(_ action: PrimaryAction) -> String {
        switch action {
        case .end(live: true): return "结束现场"
        case .end(live: false): return "确认已结束"
        case .companion: return "约人同行"
        case .memoryFragments: return "记一段记忆"
        }
    }

    private func primaryActionHandler(_ action: PrimaryAction) -> () -> Void {
        switch action {
        case .end: return { onEndShow?() }
        case .companion: return { onCompanion?() }
        case .memoryFragments: return { onMemoryFragments?() }
        }
    }

    private func accessibilityHint(for action: PrimaryAction) -> String {
        switch action {
        case .end: return "打开结束现场确认"
        case .companion: return "邀请一位朋友同行"
        case .memoryFragments: return "打开记忆碎片"
        }
    }

    nonisolated static func endActionTitle(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        hasConfirmedEnd: Bool,
        hasEndHandler: Bool
    ) -> String? {
        guard let action = primaryAction(
            phase: phase,
            timeState: timeState,
            hasConfirmedEnd: hasConfirmedEnd,
            hasEndHandler: hasEndHandler
        ) else { return nil }
        guard case let .end(live) = action else { return nil }
        return live ? "结束现场" : "确认已结束"
    }

    // MARK: ended:冷静收束

    private func endedStatus(timeState: CurrentShowTimeState) -> some View {
        let isDayEnded = timeState.kind == .dayEnded
        return VStack(alignment: .leading, spacing: 0) {
            Text(isDayEnded ? "今天结束了" : "这一场结束了")
                .font(.system(size: 44, weight: .light))
                .tracking(1)
                .foregroundColor(BSColor.Stage.foreground)

            Text(isDayEnded ? "稍作休息，明天见" : "散场之后，回味还在")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private var askingEndStatus: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("这场已经结束了吗？")
                .font(.system(size: 30, weight: .light))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)

            Text("如果已经结束，可以在这里确认")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    // MARK: inactive:已取消 / 时间待定

    private func inactiveStatus(timeState: CurrentShowTimeState) -> some View {
        let canceled = timeState.kind == .canceled
        return VStack(alignment: .leading, spacing: 0) {
            Text(canceled ? "这场取消了" : "还在等新的日期")
                .font(.system(size: 44, weight: .light))
                .tracking(1)
                .foregroundColor(BSColor.Stage.dim)

            Text(canceled ? "现场资料还帮你留着" : "新日期确定后，会继续倒数")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    /// 倒计时超大数字的钨丝金渐变(#F5EFE2 → accent)。
    private static var heroNumberGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.961, green: 0.937, blue: 0.886),
                BSColor.Stage.accent
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: 时间计算

    private static func remainingSeconds(to start: Date?, from now: Date) -> Int? {
        guard let start else { return nil }
        return max(0, Int(start.timeIntervalSince(now)))
    }

    private static func clockText(_ total: Int, forceHours: Bool) -> String {
        let total = max(0, total)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 || forceHours {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func elapsedText(since start: Date?, now: Date) -> String {
        guard let start else { return "00:00" }
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func originalDateText(for show: Show) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: show.date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }
}

// MARK: - Home Tip Card

/// V4 首页 Tip 卡:每个生命周期只推一张,轻量阅读建议,不是任务清单。
/// 音乐节(多艺人)在同一张卡里附只读阵容条;停留期给一个安静的「添加下一场」出口。
struct HomeTipCard: View {
    let show: Show
    let phase: HomeShowPhase
    let timeState: CurrentShowTimeState
    var onAddNextShow: () -> Void = {}

    private struct Content {
        let badge: String
        let title: String
        let text: String
        let tone: Tone
        var showsLineup = false
        var quietAction: String? = nil
    }

    private enum Tone {
        case gold, blue, violet, gray

        var badgeColor: Color {
            switch self {
            case .gold: return BSColor.Stage.accent
            case .blue: return Color(red: 0.604, green: 0.722, blue: 0.910)
            case .violet: return Color(red: 0.718, green: 0.639, blue: 0.788)
            case .gray: return BSColor.Stage.muted
            }
        }

        var topTint: Color {
            switch self {
            case .gold: return BSColor.Stage.accent.opacity(0.07)
            case .blue: return BSColor.Stage.glowBlue.opacity(0.14)
            case .violet: return BSColor.Stage.prepare.opacity(0.14)
            case .gray: return Color.white.opacity(0.035)
            }
        }
    }

    /// 艺人字段里名字 ≥ 3 个时视为音乐节阵容(只读展示,不做交互)。
    private var lineup: [String] {
        HomeLineupParser.lineup(from: show.artist)
    }

    private var content: Content? {
        switch phase {
        case .pre:
            if timeState.isDatedPostponement {
                return Content(
                    badge: "现场变更",
                    title: "等待被延长了",
                    text: "新日期的倒计时和提醒已重新排好。",
                    tone: .violet
                )
            }
            if !lineup.isEmpty {
                return Content(
                    badge: "现场准备",
                    title: "草地、阳光和一整天的音乐",
                    text: "野餐垫、防晒和充电宝,让这两天从容很多。",
                    tone: .violet,
                    showsLineup: true
                )
            }
            if timeState.kind == .today {
                return Content(
                    badge: "现场准备",
                    title: "今晚的事,白天就顺手办了",
                    text: "出门前看一眼天气,给手机充满电,票根截图提前放到相册最前面。",
                    tone: .blue
                )
            }
            return Content(
                badge: "进入状态",
                title: "离开场又近了一天",
                text: "把歌单里那几首老歌翻出来听听,等灯亮的时候,大合唱会有你一份。",
                tone: .gold
            )
        case .live:
            return Content(
                badge: "正在现场",
                title: "享受这一晚",
                text: "散场后人多,提前想好从哪个出口离开。",
                tone: .gray
            )
        case .ended:
            if timeState.kind == .dayEnded {
                return Content(
                    badge: "今日已落幕",
                    title: "今天先到这里",
                    text: timeState.helperText,
                    tone: .gray
                )
            }
            guard timeState.kind == .postShow else { return nil }
            return Content(
                badge: "散场之后",
                title: "余温还留在这里",
                text: "这场的资料还会保留。想好下一场去哪了吗?",
                tone: .gray,
                quietAction: "添加下一场现场 →"
            )
        case .inactive:
            guard timeState.kind == .postponed else { return nil }
            return Content(
                badge: "现场变更",
                title: "先把它放在这里",
                text: "等主办方公布新日期,在编辑现场里记一下,倒计时就会继续。",
                tone: .gray
            )
        }
    }

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: 0) {
                Text(content.badge)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(content.tone.badgeColor)
                    .padding(.bottom, 8)

                Text(content.title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundColor(BSColor.Stage.foreground)
                    .padding(.bottom, 5)

                Text(content.text)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineSpacing(4)
                    .foregroundColor(BSColor.Stage.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if content.showsLineup {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(lineup, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(BSColor.Stage.foreground.opacity(0.88))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.045))
                                    )
                                    .overlay(
                                        Capsule().stroke(BSColor.Stage.border, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                if let quiet = content.quietAction {
                    Button(action: onAddNextShow) {
                        Text(quiet)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(BSColor.Stage.foreground)
                            .frame(minHeight: BSLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 13)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(BSColor.Stage.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [content.tone.topTint, .clear],
                                    startPoint: .top,
                                    endPoint: UnitPoint(x: 0.5, y: 0.55)
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Live Pulse

/// 开场中的呼吸脉冲点(设计稿 pulse-ring);Reduce Motion 时静止。
struct HomeLivePulse: View {
    let reduceMotion: Bool
    @State private var rippling = false

    var body: some View {
        Circle()
            .fill(BSColor.Stage.live)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(BSColor.Stage.live.opacity(0.55), lineWidth: 1)
                    .scaleEffect(rippling ? 2.2 : 1)
                    .opacity(rippling ? 0 : 1)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    rippling = true
                }
            }
    }
}
