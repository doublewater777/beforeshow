import SwiftUI

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
                // 与 widget 共用同一阈值:remaining 恰好 24h 时是时钟,不是「1 天」
                if WidgetTimelinePlanner.isDayCountHero(remainingSeconds: total) {
                    return .countdownDays(total / Int(WidgetTimelinePlanner.dayCountdownThreshold))
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
            return timeState.isDatedPostponement ? BSLocalization.text("新日期") : BSLocalization.text("下一场")
        case .today:
            guard let start = timeState.effectiveStartTime, now >= start else {
                return citySiteText("今天开场 · %@站", city: city, bare: "今天开场")
            }
            return BSLocalization.text("LIVE · 开场中")
        case .dayEnded:
            return citySiteText("已落幕 · %@站", city: city, bare: "已落幕")
        case .postShow:
            return citySiteText("已落幕 · %@站", city: city, bare: "已落幕")
        case .ended:
            return citySiteText("已落幕 · %@站", city: city, bare: "已落幕")
        case .canceled:
            return BSLocalization.text("已取消")
        case .postponed:
            return BSLocalization.text("延期 · 时间待定")
        }
    }

    static func statusText(
        for timeState: CurrentShowTimeState,
        now: Date
    ) -> String {
        switch timeState.kind {
        case .before: return BSLocalization.text("开场前")
        case .today:
            guard let start = timeState.effectiveStartTime, now >= start else {
                return BSLocalization.text("今天开场")
            }
            return BSLocalization.text("正在现场")
        case .dayEnded: return BSLocalization.text("今日已落幕")
        case .postShow: return BSLocalization.text("散场后")
        case .ended: return BSLocalization.text("已结束")
        case .canceled: return BSLocalization.text("已取消")
        case .postponed: return BSLocalization.text("时间待定")
        }
    }

    private static func citySiteText(_ formatKey: String, city: String?, bare: String) -> String {
        let city = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let city, !city.isEmpty else { return BSLocalization.text(bare) }
        return BSLocalization.format(formatKey, city)
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
        calendar: Calendar = .current,
        locale: Locale = AppLanguageManager.persisted.locale
    ) -> String? {
        guard timeState.hasKnownEffectiveDate else { return nil }
        let calendar = show.timingCalendar(fallback: calendar)

        let dayFormatter = DateFormatter()
        dayFormatter.locale = locale
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy.MM.dd E"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let endTimeFormatter = DateFormatter()
        endTimeFormatter.locale = locale
        endTimeFormatter.calendar = show.endTimingCalendar(fallback: calendar)
        endTimeFormatter.timeZone = show.endTimingCalendar(fallback: calendar).timeZone
        endTimeFormatter.dateFormat = "HH:mm"

        if CurrentShowTimeState.isMultiDayDailyCycle(for: show, calendar: calendar),
           let endDay = CurrentShowTimeState.effectiveEndDate(for: show, calendar: calendar) {
            var daily = timeFormatter.string(from: show.startTime)
            if let endTime = show.endTime {
                daily += "-\(endTimeFormatter.string(from: endTime))"
            }
            let startYear = calendar.component(.year, from: show.effectiveDate)
            let endYear = calendar.component(.year, from: endDay)
            let endDateText = startYear == endYear
                ? monthDayText(endDay, calendar: calendar)
                : "\(endYear).\(monthDayText(endDay, calendar: calendar))"
            return BSLocalization.format("%@-%@ · 每日 %@", "\(startYear).\(monthDayText(show.effectiveDate, calendar: calendar))", endDateText, daily)
        }

        let base = "\(dayFormatter.string(from: show.effectiveDate)) \(timeFormatter.string(from: show.startTime))"

        // 已确认散场的现场展示实际时长(开场→散场),不再说「预计」。
        if let endedAt = show.endedAt,
           let actual = ShowDurationFormatter.single(from: timeState.effectiveStartTime ?? show.startTime, to: endedAt) {
            return BSLocalization.format("%@ · 实际演出 %@", base, actual)
        }

        guard let start = timeState.effectiveStartTime,
              let end = timeState.effectiveEndTime,
              let duration = ShowDurationFormatter.single(from: start, to: end) else {
            return base
        }
        return BSLocalization.format("%@ · 预计演出 %@", base, duration)
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

    // The countdown is the visual hero. Respect the user's Dynamic Type
    // setting so accessibility readers get the same weight, but cap at
    // .accessibility2 — above that, a 3-digit day number at 1.85× scale
    // would push the HStack past the safe area and break the card.
    @ScaledMetric(relativeTo: .largeTitle) private var dayNumber: CGFloat = 72
    @ScaledMetric(relativeTo: .title) private var clockNumber: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timeState = CurrentShowTimeState(show: show, now: context.date)
            let phase = HomeShowPhase(timeState: timeState, now: context.date)
            lockup(phase: phase, timeState: timeState, now: context.date)
        }
        .dynamicTypeSize(.large ... .accessibility2)
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

    /// 估算散场时间已过、用户尚未确认 endedAt:状态条说「待确认」,不提前宣布 ENDED。
    private func isAwaitingEndConfirmation(_ timeState: CurrentShowTimeState) -> Bool {
        CurrentShowTimeState.isUnconfirmedEstimatedEnd(
            kind: timeState.kind,
            hasConfirmedEnd: show.endedAt != nil
        )
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

                Text(
                    isAwaitingEndConfirmation(timeState)
                        ? BSLocalization.text("待确认")
                        : HomeShowIdentityPresentation.statusText(for: timeState, now: now)
                )
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

            let mode = modeLabel(for: phase, timeState: timeState)
            if !mode.isEmpty {
                Text(mode)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.45)
                    .foregroundColor(modeLabelColor(for: phase))
                    .lineLimit(1)
            }
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
            return "LIVE"
        case .ended:
            // 估算散场未确认时不标 ENDED,避免状态条与「这场已经结束了吗?」自相矛盾。
            return isAwaitingEndConfirmation(timeState) ? "" : "ENDED"
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
    // 精度随临近程度收束:>24h 只到「天」超大节拍;≤24h 只到分(每分钟跳一下),<1h 切 MM:SS 走秒。
    // 色温递进:远场奶白 heroIvory → 当天暖金 heroWarmGold → <1h 纯金 accent + 光晕,
    // 字重同步加码(ultraLight → regular → semibold),视觉强度随临近升温。
    // 天数/时钟的阈值与 widget 共用 WidgetTimelinePlanner.isDayCountHero。

    @ViewBuilder
    private func preCountdown(timeState: CurrentShowTimeState, now: Date) -> some View {
        if let total = Self.remainingSeconds(to: timeState.effectiveStartTime, from: now) {
            if WidgetTimelinePlanner.isDayCountHero(remainingSeconds: total) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("\(total / Int(WidgetTimelinePlanner.dayCountdownThreshold))")
                            .font(.system(size: dayNumber, weight: .ultraLight))
                            .tracking(-1.5)
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundColor(BSColor.Stage.heroIvory)
                            // 设计稿 line-height .94:系统字行高约 1.19 倍,负 padding 收掉多余行高
                            .padding(.vertical, -9)
                        Text("天")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    if timeState.isDatedPostponement {
                        Text(BSLocalization.format("原定 %@", Self.originalDateText(for: show, calendar: show.timingCalendar())))
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(BSColor.Stage.dim)
                            .padding(.top, 10)
                    }
                }
            } else if total >= 3_600 {
                Text(Self.clockText(total))
                    .font(.system(size: clockNumber, weight: .regular))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundColor(BSColor.Stage.heroWarmGold)
            } else {
                Text(Self.clockText(total))
                    .font(.system(size: clockNumber, weight: .semibold))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundColor(BSColor.Stage.accent)
                    .shadow(color: BSColor.Stage.accent.opacity(0.35), radius: 16)
            }
        } else {
            Text("--")
                .font(.system(size: clockNumber, weight: .thin))
                .monospacedDigit()
                .foregroundColor(BSColor.Stage.dim)
        }
    }

    // MARK: live:脉冲 + 已开场时长 + 散场确认入口
    // 状态只说一遍:顶部 pill 是「正在现场」,Hero 只展示新增信息——已开场多久。

    private func liveStatus(timeState: CurrentShowTimeState, now: Date) -> some View {
        HStack(spacing: 14) {
            HomeLivePulse(reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.elapsedText(since: timeState.effectiveStartTime, now: now))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.3)
                    .foregroundColor(BSColor.Stage.foreground)
                Text("已开场")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
        case .end(live: true): return BSLocalization.text("结束现场")
        case .end(live: false): return BSLocalization.text("确认已结束")
        case .companion: return BSLocalization.text("约人同行")
        case .memoryFragments: return BSLocalization.text("记一段记忆")
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
        case .end: return BSLocalization.text("打开结束现场确认")
        case .companion: return BSLocalization.text("邀请一位朋友同行")
        case .memoryFragments: return BSLocalization.text("打开记忆碎片")
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

    // MARK: 时间计算

    private static func remainingSeconds(to start: Date?, from now: Date) -> Int? {
        guard let start else { return nil }
        return max(0, Int(start.timeIntervalSince(now)))
    }

    /// >1h 只到分(HH:MM,每分钟跳一下);<1h 切 MM:SS 走秒。
    private static func clockText(_ total: Int) -> String {
        let total = max(0, total)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d", hours, minutes)
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

    private static func originalDateText(for show: Show, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: show.date)
        return BSLocalization.format("%lld月%lld日", components.month ?? 0, components.day ?? 0)
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
        show.artistNames.count >= 3 ? Array(show.artistNames.prefix(8)) : []
    }

    private var content: Content? {
        switch phase {
        case .pre:
            if timeState.isDatedPostponement {
                return Content(
                    badge: BSLocalization.text("现场变更"),
                    title: BSLocalization.text("等待被延长了"),
                    text: BSLocalization.text("新日期的倒计时和提醒已重新排好。"),
                    tone: .violet
                )
            }
            if !lineup.isEmpty {
                return Content(
                    badge: BSLocalization.text("现场准备"),
                    title: BSLocalization.text("草地、阳光和一整天的音乐"),
                    text: BSLocalization.text("野餐垫、防晒和充电宝,让这两天从容很多。"),
                    tone: .violet,
                    showsLineup: true
                )
            }
            if timeState.kind == .today {
                return Content(
                    badge: BSLocalization.text("现场准备"),
                    title: BSLocalization.text("今晚的事,白天就顺手办了"),
                    text: BSLocalization.text("出门前看一眼天气,给手机充满电,票根截图提前放到相册最前面。"),
                    tone: .blue
                )
            }
            return Content(
                badge: BSLocalization.text("进入状态"),
                title: BSLocalization.text("离开场又近了一天"),
                text: BSLocalization.text("把歌单里那几首老歌翻出来听听,等灯亮的时候,大合唱会有你一份。"),
                tone: .gold
            )
        case .live:
            return Content(
                badge: BSLocalization.text("正在现场"),
                title: BSLocalization.text("享受这一晚"),
                text: BSLocalization.text("散场后人多,提前想好从哪个出口离开。"),
                tone: .gray
            )
        case .ended:
            if timeState.kind == .dayEnded {
                return Content(
                    badge: BSLocalization.text("今日已落幕"),
                    title: BSLocalization.text("今天先到这里"),
                    text: timeState.helperText,
                    tone: .gray
                )
            }
            guard timeState.kind == .postShow else { return nil }
            return Content(
                badge: BSLocalization.text("散场之后"),
                title: BSLocalization.text("余温还留在这里"),
                text: BSLocalization.text("这场的资料还会保留。想好下一场去哪了吗?"),
                tone: .gray,
                quietAction: BSLocalization.text("添加下一场现场 →")
            )
        case .inactive:
            guard timeState.kind == .postponed else { return nil }
            return Content(
                badge: BSLocalization.text("现场变更"),
                title: BSLocalization.text("先把它放在这里"),
                text: BSLocalization.text("等主办方公布新日期,在编辑现场里记一下,倒计时就会继续。"),
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
