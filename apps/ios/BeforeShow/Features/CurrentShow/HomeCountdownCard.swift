import SwiftUI

struct HomeCountdownLockup: View {
    let show: Show
    var onEndShow: (() -> Void)? = nil
    var onCompanion: (() -> Void)? = nil
    var onMemoryFragments: (() -> Void)? = nil
    var onMemoryCreate: (() -> Void)? = nil
    var onOpenRoute: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var languageController = AppLanguageController.shared

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
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let dateText {
                        Text(dateText)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    if dateText != nil, venueSummary != nil {
                        Text(" · ")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    if let venueSummary {
                        locationControl(venueSummary, opensRoute: onOpenRoute != nil)
                    }
                }
                .lineLimit(2)
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

            if let action = availablePrimaryAction(phase: phase, timeState: timeState, now: now) {
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
        .accessibilityElement(children: onEndShow == nil && onOpenRoute == nil ? .combine : .contain)
    }

    /// 估算散场时间已过、用户尚未确认 endedAt:状态条说「待确认」,不提前宣布 ENDED。
    private func isAwaitingEndConfirmation(_ timeState: CurrentShowTimeState) -> Bool {
        CurrentShowTimeState.isUnconfirmedEstimatedEnd(
            kind: timeState.kind,
            hasConfirmedEnd: show.endedAt != nil
        )
    }

    @ViewBuilder
    private func locationControl(_ summary: String, opensRoute: Bool) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: 3) {
            if opensRoute {
                Image(systemName: "map")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent.opacity(0.85))
            }
            Text(summary)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(opensRoute ? BSColor.Stage.foreground.opacity(0.78) : BSColor.Stage.muted)
        }

        if opensRoute {
            Button {
                onOpenRoute?()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary)
            .accessibilityHint(BSLocalization.text("打开路线"))
        } else {
            label
        }
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
    // 精度随临近程度收束:>24h 只到「天」超大节拍;≤24h 显示小时,<1h 显示分钟。
    // 色温递进:远场奶白 heroIvory → 当天暖金 heroWarmGold → <1h 纯金 accent + 光晕,
    // 字重同步加码(ultraLight → regular → semibold),视觉强度随临近升温。
    // 天数/时钟的阈值与 widget 共用 WidgetTimelinePlanner.isDayCountHero。

    @ViewBuilder
    private func preCountdown(timeState: CurrentShowTimeState, now: Date) -> some View {
        if let total = Self.remainingSeconds(to: timeState.effectiveStartTime, from: now) {
            if WidgetTimelinePlanner.isDayCountHero(remainingSeconds: total) {
                let days = total / Int(WidgetTimelinePlanner.dayCountdownThreshold)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("\(days)")
                            .font(.system(size: dayNumber, weight: .ultraLight))
                            .tracking(-1.5)
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            // TimelineView re-renders without a transaction, so the
                            // numericText roll needs its own animation keyed to the value.
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.32),
                                value: days
                            )
                            .lineLimit(1)
                            .foregroundColor(BSColor.Stage.heroIvory)
                            // 设计稿 line-height .94:系统字行高约 1.19 倍,负 padding 收掉多余行高
                            .padding(.vertical, -9)
                        Text(BSLocalization.text("天"))
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
                styledCountdown(
                    total: total,
                    numberWeight: .regular,
                    numberColor: BSColor.Stage.heroWarmGold
                )
            } else {
                styledCountdown(
                    total: total,
                    numberWeight: .semibold,
                    numberColor: BSColor.Stage.accent
                )
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
    // 左侧保留「正在现场」状态,右侧展示已开场时长。

    private func liveStatus(timeState: CurrentShowTimeState, now: Date) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                HomeLivePulse(reduceMotion: reduceMotion)

                Text(BSLocalization.text("正在现场"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.liveTitle)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                let elapsed = Self.elapsedText(since: timeState.effectiveStartTime, now: now)
                Text(elapsed)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.22),
                        value: elapsed
                    )
                    .tracking(-0.3)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("已开场"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Primary action:单一主行动随生命周期切换
    // pre → 约人同行;开场记忆窗 → 记一段记忆;其余 live → 结束现场;
    // ended(未确认) → 确认已结束。开场记忆窗内结束现场降到快捷区。

    enum PrimaryAction: Equatable {
        case end(live: Bool)
        case memoryFragments
        case memoryCreate
    }

    private func availablePrimaryAction(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        now: Date
    ) -> PrimaryAction? {
        Self.primaryAction(
            phase: phase,
            timeState: timeState,
            now: now,
            showStart: CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar()),
            hasConfirmedEnd: show.endedAt != nil,
            hasEndHandler: onEndShow != nil
        )
    }

    nonisolated static func primaryAction(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        now: Date,
        showStart: Date,
        hasConfirmedEnd: Bool,
        hasEndHandler: Bool
    ) -> PrimaryAction? {
        guard !hasConfirmedEnd else { return nil }
        switch phase {
        case .pre:
            return nil
        case .live:
            if OpeningMemoryWindow.isActive(now: now, showStart: showStart, isLive: true) {
                return .memoryCreate
            }
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
        case .memoryFragments, .memoryCreate: return BSLocalization.text("记一段记忆")
        }
    }

    private func primaryActionHandler(_ action: PrimaryAction) -> () -> Void {
        switch action {
        case .end: return { onEndShow?() }
        case .memoryFragments: return { onMemoryFragments?() }
        case .memoryCreate: return { (onMemoryCreate ?? onMemoryFragments)?() }
        }
    }

    private func accessibilityHint(for action: PrimaryAction) -> String {
        switch action {
        case .end: return BSLocalization.text("打开结束现场确认")
        case .memoryFragments: return BSLocalization.text("打开记忆碎片")
        case .memoryCreate: return BSLocalization.text("打开新增记忆")
        }
    }

    nonisolated static func endActionTitle(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState,
        now: Date,
        showStart: Date,
        hasConfirmedEnd: Bool,
        hasEndHandler: Bool
    ) -> String? {
        guard let action = primaryAction(
            phase: phase,
            timeState: timeState,
            now: now,
            showStart: showStart,
            hasConfirmedEnd: hasConfirmedEnd,
            hasEndHandler: hasEndHandler
        ) else { return nil }
        guard case let .end(live) = action else { return nil }
        return live ? BSLocalization.text("结束现场") : BSLocalization.text("确认已结束")
    }

    // MARK: ended:冷静收束

    private func endedStatus(timeState: CurrentShowTimeState) -> some View {
        let isDayEnded = timeState.kind == .dayEnded
        return VStack(alignment: .leading, spacing: 0) {
            Text(isDayEnded ? BSLocalization.text("今天结束了") : BSLocalization.text("这一场结束了"))
                .font(.system(size: 44, weight: .light))
                .tracking(1)
                .foregroundColor(BSColor.Stage.foreground)

            Text(isDayEnded ? BSLocalization.text("稍作休息，明天见") : BSLocalization.text("散场之后，回味还在"))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private var askingEndStatus: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BSLocalization.text("这场已经结束了吗？"))
                .font(.system(size: 30, weight: .light))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)

        }
    }

    // MARK: inactive:已取消 / 时间待定

    private func inactiveStatus(timeState: CurrentShowTimeState) -> some View {
        let canceled = timeState.kind == .canceled
        return VStack(alignment: .leading, spacing: 0) {
            Text(canceled ? BSLocalization.text("这场取消了") : BSLocalization.text("还在等新的日期"))
                .font(.system(size: 44, weight: .light))
                .tracking(1)
                .foregroundColor(BSColor.Stage.dim)

            Text(canceled ? BSLocalization.text("现场资料还帮你留着") : BSLocalization.text("新日期确定后，会继续倒数"))
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

    private func styledCountdown(
        total: Int,
        numberWeight: Font.Weight,
        numberColor: Color
    ) -> Text {
        var attributed = AttributedString(CountdownCopy.until(remainingSeconds: total))
        attributed.font = .system(size: 22, weight: .medium)
        attributed.foregroundColor = BSColor.Stage.muted
        let number = String(CountdownCopy.value(remainingSeconds: total))
        if let range = attributed.range(of: number) {
            attributed[range].font = .system(size: clockNumber, weight: numberWeight)
            attributed[range].foregroundColor = numberColor
        }
        return Text(attributed)
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

// MARK: - Live Pulse

// MARK: - Live Pulse

/// 开场中的呼吸脉冲点(设计稿 pulse-ring);Reduce Motion 时静止。
