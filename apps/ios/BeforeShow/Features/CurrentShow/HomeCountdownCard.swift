import SwiftUI

/// The countdown printed on the lip of the stage: one big serif number, its unit and the exact
/// time beside it, a lit rule, then the show and the one action that matters now.
struct HomeCountdownLockup: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    var onEndShow: (() -> Void)? = nil
    var onMemoryFragments: (() -> Void)? = nil
    var onMemoryCreate: (() -> Void)? = nil
    var onOpenRoute: (() -> Void)? = nil
    /// 当前阶段的功能推荐（由主卡 owner 每天定一次）。
    var recommendation: RecommendedFeature? = nil
    var onRecommendation: ((RecommendedFeature) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ticker {
        /// The big number; nil when the stage has words instead (ended, cancelled).
        var value: String? = nil
        var headline: String? = nil
        var unit: String
        var detail: String
        var tint: Color
    }

    var body: some View {
        let phase = snapshot.phase
        let timeState = snapshot.timeState
        let ticker = ticker(phase: phase, timeState: timeState, now: snapshot.now)
        VStack(alignment: .leading, spacing: 0) {
            tickerRow(ticker)
            LinearGradient(colors: [ticker.tint.opacity(0.9), ticker.tint.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.top, 14)
                .padding(.bottom, 14)

            let identity = ShowIdentityCopy(name: show.name, venueName: show.venueName, city: show.city)
            Text(identity.title)
                .font(BSFont.Editorial.serif(24))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The date and time are already beside the number; only the venue follows the name,
            // and before doors the map module below carries the venue instead.
            if identity.venueSummary != nil, phase != .pre {
                ViewThatFits(in: .horizontal) {
                    identityDetails(dateText: nil, venueSummary: identity.venueSummary, opensRoute: onOpenRoute != nil, stacked: false)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    identityDetails(dateText: nil, venueSummary: identity.venueSummary, opensRoute: onOpenRoute != nil, stacked: true)
                }
                .padding(.top, 6)
            }

            if let action = availablePrimaryAction(phase: phase, timeState: timeState) {
                primaryActionButton(action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(.large ... .accessibility2)
        .accessibilityElement(children: onEndShow == nil && onOpenRoute == nil ? .combine : .contain)
    }

    @ViewBuilder
    private func tickerRow(_ ticker: Ticker) -> some View {
        if ticker.value == nil, let headline = ticker.headline {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if snapshot.phase == .live { HomeLivePulse(reduceMotion: reduceMotion) }
                    Text(headline)
                        .font(BSFont.Editorial.serif(34))
                        .foregroundStyle(ticker.tint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ticker.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(2)
            }
        } else {
            numberRow(ticker)
        }
    }

    private func numberRow(_ ticker: Ticker) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            if let value = ticker.value {
                Text(value)
                    .font(BSFont.Editorial.serif(96))
                    .tracking(-3)
                    .monospacedDigit()
                    .foregroundStyle(ticker.tint)
                    .shadow(color: ticker.tint.opacity(0.45), radius: 22)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.vertical, -14)
            } else if let headline = ticker.headline {
                Text(headline)
                    .font(BSFont.Editorial.serif(40))
                    .foregroundStyle(ticker.tint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if ticker.value != nil {
                    Text(ticker.unit)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(BSColor.Stage.foreground)
                }
                Text(ticker.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(2)
            }
            .layoutPriority(ticker.value == nil ? 0 : 1)
            Spacer(minLength: 0)
        }
    }

    private func ticker(phase: HomeShowPhase, timeState: CurrentShowTimeState, now: Date) -> Ticker {
        let calendar = show.timingCalendar()
        let start = timeState.effectiveStartTime
        let startLine = start.map { date -> String in
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("MMMdEEEHHmm")
            return formatter.string(from: date)
        } ?? ""
        let tint = statusColor(for: phase, timeState: timeState)
        switch phase {
        case .pre:
            guard let total = Self.remainingSeconds(to: start, from: now) else {
                return Ticker(value: "--", unit: "", detail: startLine, tint: BSColor.Stage.dim)
            }
            let detail = timeState.isDatedPostponement
                ? BSLocalization.format("原定 %@", Self.originalDateText(for: show, calendar: calendar))
                : startLine
            if let days = ShowCountdownRule.dayCount(remainingSeconds: total, dayDistance: timeState.dayDistance) {
                return Ticker(value: String(format: "%02d", days), unit: BSLocalization.text("天后"), detail: detail, tint: timeState.isDatedPostponement ? tint : BSColor.Stage.heroIvory)
            }
            if total >= 3_600 {
                return Ticker(value: "\(total / 3_600)", unit: BSLocalization.format("小时 %lld 分后开场", (total % 3_600) / 60), detail: detail, tint: BSColor.Stage.heroWarmGold)
            }
            return Ticker(value: "\(max(1, Int((Double(total) / 60).rounded(.up))))", unit: BSLocalization.text("分钟后开场"), detail: detail, tint: BSColor.Stage.accent)
        case .live:
            return Ticker(headline: BSLocalization.text("正在演出"), unit: "", detail: BSLocalization.format("已开场 %@", Self.elapsedText(since: start, now: now)), tint: BSColor.Stage.liveTitle)
        case .ended:
            if timeState.kind == .dayEnded {
                return Ticker(headline: BSLocalization.text("今天结束了"), unit: "", detail: dayEndedCopy(timeState), tint: BSColor.Stage.foreground)
            }
            if show.endedAt == nil {
                return Ticker(headline: BSLocalization.text("这场已经结束了吗？"), unit: "", detail: startLine, tint: BSColor.Stage.foreground)
            }
            return Ticker(headline: BSLocalization.text("这一场结束了"), unit: "", detail: startLine, tint: BSColor.Stage.foreground)
        case .inactive:
            let canceled = timeState.kind == .canceled
            return Ticker(
                headline: canceled ? BSLocalization.text("这场取消了") : BSLocalization.text("还在等新的日期"),
                unit: "",
                detail: canceled ? BSLocalization.text("现场资料还帮你留着") : BSLocalization.text("新日期确定后，会继续倒数"),
                tint: BSColor.Stage.dim
            )
        }
    }

    private func dayEndedCopy(_ timeState: CurrentShowTimeState) -> String {
        guard let nextStart = timeState.nextSessionStartsAt else { return BSLocalization.text("稍作休息，下次现场见") }
        let eventCalendar = show.timingFields.eventCalendar(fallback: .current)
        let distance = FestivalDay.distance(from: .now, to: nextStart, calendar: eventCalendar)
        if distance <= 1 { return BSLocalization.text("稍作休息，明天见") }
        if distance == 2 { return BSLocalization.text("稍作休息，后天见") }
        return BSLocalization.format("稍作休息，%@继续", FestivalDay.word(for: nextStart, distance: distance, calendar: eventCalendar))
    }

    @ViewBuilder
    private func identityDetails(
        dateText: String?,
        venueSummary: String?,
        opensRoute: Bool,
        stacked: Bool
    ) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 3) {
                if let dateText {
                    identityDateText(dateText)
                }
                if let venueSummary {
                    locationControl(venueSummary, opensRoute: opensRoute)
                }
            }
            .lineLimit(2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let dateText {
                    identityDateText(dateText)
                }
                if dateText != nil, venueSummary != nil {
                    Text(" · ")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                if let venueSummary {
                    locationControl(venueSummary, opensRoute: opensRoute)
                }
            }
        }
    }

    private func identityDateText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(BSColor.Stage.muted)
    }

    @ViewBuilder
    private func locationControl(_ summary: String, opensRoute: Bool) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: 3) {
            if opensRoute {
                Image(systemName: "map")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent.opacity(0.85))
            }
            Text(summary)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(opensRoute ? BSColor.Stage.foreground.opacity(0.78) : BSColor.Stage.muted)
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


    // MARK: Primary action（规则见 HomeCountdownPrimaryAction.swift）

    private func availablePrimaryAction(
        phase: HomeShowPhase,
        timeState: CurrentShowTimeState
    ) -> PrimaryAction? {
        Self.primaryAction(
            phase: phase,
            timeState: timeState,
            hasConfirmedEnd: show.endedAt != nil,
            hasEndHandler: onEndShow != nil,
            hasRouteHandler: false,
            hasCompletedDispersal: show.hasCompletedDispersalCeremony,
            recommendation: onRecommendation == nil ? nil : recommendation
        )
    }

    private func primaryActionButton(_ action: PrimaryAction) -> some View {
        Button(action: primaryActionHandler(action)) {
            Text(action.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.background)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(BSColor.Stage.foreground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(action.accessibilityHint)
        .padding(.top, 16)
    }

    private func primaryActionHandler(_ action: PrimaryAction) -> () -> Void {
        switch action {
        case .end: return { onEndShow?() }
        case .memoryFragments: return { onMemoryFragments?() }
        case .memoryCreate: return { (onMemoryCreate ?? onMemoryFragments)?() }
        case .route: return { onOpenRoute?() }
        case .dispersal: return { onRecommendation?(.dispersal) }
        case .recommendation(let feature): return { onRecommendation?(feature) }
        }
    }


    // MARK: 时间计算

    private static func remainingSeconds(to start: Date?, from now: Date) -> Int? {
        guard let start else { return nil }
        return max(0, Int(start.timeIntervalSince(now)))
    }

    private static func elapsedText(since start: Date?, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start ?? now)))
        let hours = total / 3_600, minutes = (total % 3_600) / 60
        return hours > 0 ? BSLocalization.format("%lld 小时 %lld 分", hours, minutes) : BSLocalization.format("%lld 分钟", minutes)
    }

    private static func originalDateText(for show: Show, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month, .day], from: show.date)
        return BSLocalization.format("%lld月%lld日", components.month ?? 0, components.day ?? 0)
    }
}
