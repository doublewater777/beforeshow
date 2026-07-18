import SwiftUI

// MARK: - Home Show Phase
// 首页三态（设计稿 pre / live / ended）从 CurrentShowTimeState 推导：
// - pre: 开场前（含当天未到开场时间）
// - live: 开场中（越过开场时间，未到谢幕边界）
// - ended: 谢幕后（停留期与已结束）
// - inactive: 已取消 / 待定，卡片回退为文本态
enum HomeShowPhase: Equatable {
    case pre
    case live
    case ended
    case inactive

    init(timeState: CurrentShowTimeState, now: Date = Date()) {
        switch timeState.kind {
        case .before:
            self = .pre
        case .today:
            if let start = timeState.effectiveStartTime, now >= start {
                self = .live
            } else {
                self = .pre
            }
        case .postShow, .ended:
            self = .ended
        case .canceled, .postponed:
            self = .inactive
        }
    }

    /// Hero kicker 文案；inactive 由调用方回退到 timeState.title（已取消 / 时间待定）。
    func kickerText(city: String?) -> String {
        let trimmed = city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stop = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        switch self {
        case .pre:
            return stop.map { "即将开场 · \($0)站" } ?? "即将开场"
        case .live:
            return "LIVE · 开场中"
        case .ended:
            return stop.map { "已落幕 · \($0)站" } ?? "已落幕"
        case .inactive:
            return ""
        }
    }
}

// MARK: - Home Countdown Card

/// 压住海报下缘的浮动倒计时卡（设计稿 countdown）：
/// pre 天/时/分/秒秒级四格；live 脉冲 + 已进行时长；ended 冷静收束 + 本场时长。
/// TimelineView 每秒按当前时间重算 phase，跨越开场 / 谢幕边界自动切换。
struct HomeCountdownCard: View {
    let show: Show

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timeState = CurrentShowTimeState(show: show, now: context.date)
            let phase = HomeShowPhase(timeState: timeState, now: context.date)
            card(phase: phase, timeState: timeState, now: context.date)
        }
    }

    @ViewBuilder
    private func card(phase: HomeShowPhase, timeState: CurrentShowTimeState, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label(for: phase, timeState: timeState))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BSColor.Home.muted)
                Spacer(minLength: 0)
                Text(badge(for: phase))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(badgeColor(for: phase))
            }

            switch phase {
            case .pre:
                countdownGrid(timeState: timeState, now: now)
            case .live:
                liveStatus(timeState: timeState, now: now)
            case .ended:
                endedStatus(timeState: timeState)
            case .inactive:
                inactiveStatus(timeState: timeState)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(countdownSurface(for: phase))
        .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: pre：四格倒计时

    private func countdownGrid(timeState: CurrentShowTimeState, now: Date) -> some View {
        let remaining = Self.remainingParts(to: timeState.effectiveStartTime, from: now)
        return HStack(spacing: 8) {
            countdownCell(value: remaining.days, unit: "天")
            countdownCell(value: remaining.hours, unit: "时")
            countdownCell(value: remaining.minutes, unit: "分")
            countdownCell(value: remaining.seconds, unit: "秒")
        }
    }

    private func countdownCell(value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundColor(BSColor.Home.foreground)
            Text(unit)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(BSColor.Home.dim)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(BSColor.Home.foreground.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [BSColor.Home.accent.opacity(0.08), .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.7)
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(BSColor.Home.foreground.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: live：脉冲 + 已进行

    private func liveStatus(timeState: CurrentShowTimeState, now: Date) -> some View {
        HStack(spacing: 12) {
            HomeLivePulse(reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 4) {
                Text("灯光已亮 · 开场中")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(BSColor.Home.liveTitle)
                Text("现场进行中，收好票夹与手机电量")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BSColor.Home.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(Self.elapsedText(since: timeState.effectiveStartTime, now: now))
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(BSColor.Home.foreground)
                Text("已进行")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Home.dim)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: ended：冷静收束

    private func endedStatus(timeState: CurrentShowTimeState) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(BSColor.Home.dim)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("谢幕了 · 回味还在")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(BSColor.Home.foreground)
                Text("记下的碎片都留在这一场")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BSColor.Home.muted)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(Self.durationText(from: timeState.effectiveStartTime, to: timeState.endBoundary))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(BSColor.Home.muted)
                    .multilineTextAlignment(.trailing)
                Text("本场时长")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Home.dim)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: inactive：已取消 / 待定

    private func inactiveStatus(timeState: CurrentShowTimeState) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(BSColor.Home.dim)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(timeState.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(BSColor.Home.muted)
                Text(timeState.helperText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BSColor.Home.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: 文案与样式

    private func label(for phase: HomeShowPhase, timeState: CurrentShowTimeState) -> String {
        switch phase {
        case .pre: return "距离灯亮还有"
        case .live: return "演出进行中"
        case .ended: return "今晚场已结束"
        case .inactive: return timeState.title
        }
    }

    private func badge(for phase: HomeShowPhase) -> String {
        switch phase {
        case .pre: return "COUNTDOWN"
        case .live: return "ON STAGE"
        case .ended: return "ENDED"
        case .inactive: return "—"
        }
    }

    private func badgeColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Home.accent
        case .live: return BSColor.Home.liveTitle
        case .ended, .inactive: return BSColor.Home.muted
        }
    }

    private func countdownSurface(for phase: HomeShowPhase) -> some View {
        let borderColor: Color
        let tintColor: Color
        switch phase {
        case .pre:
            borderColor = BSColor.Home.foreground.opacity(0.10)
            tintColor = BSColor.Home.foreground.opacity(0.06)
        case .live:
            borderColor = BSColor.Home.live.opacity(0.28)
            tintColor = BSColor.Home.live.opacity(0.12)
        case .ended, .inactive:
            borderColor = BSColor.Home.foreground.opacity(0.08)
            tintColor = BSColor.Home.foreground.opacity(0.04)
        }

        return RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .fill(BSColor.Home.surfaceRaised.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [tintColor, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.55)
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    // MARK: 时间计算

    private static func remainingParts(to start: Date?, from now: Date) -> (days: String, hours: String, minutes: String, seconds: String) {
        guard let start else { return ("--", "--", "--", "--") }
        let total = max(0, Int(start.timeIntervalSince(now)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return (
            String(format: "%02d", days),
            String(format: "%02d", hours),
            String(format: "%02d", minutes),
            String(format: "%02d", seconds)
        )
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

    private static func durationText(from start: Date?, to end: Date?) -> String {
        guard let start, let end, end > start else { return "—" }
        let minutes = Int(end.timeIntervalSince(start)) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 {
            return "\(hours) 小时 \(rest) 分"
        }
        if hours > 0 {
            return "\(hours) 小时"
        }
        return "\(max(1, rest)) 分钟"
    }
}

// MARK: - Live Pulse

/// 开场中的呼吸脉冲点（设计稿 pulse-ring）；Reduce Motion 时静止。
struct HomeLivePulse: View {
    let reduceMotion: Bool
    @State private var rippling = false

    var body: some View {
        Circle()
            .fill(BSColor.Home.live)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(BSColor.Home.live.opacity(0.55), lineWidth: 1)
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
