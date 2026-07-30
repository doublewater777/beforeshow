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

// HomeShowPhase 已移至 Shared/HomeShowPhase.swift（app 与 widget 共用）。

// MARK: - Home Countdown Lockup

/// V4 首页倒计时节拍:封面之后 20pt 停顿的扁 lockup(不再是压住海报的浮动卡片)。
/// pre 远场超大天数、当天秒级时钟、临近 1 小时金色时钟;
/// live 脉冲 + 已进行;ended 冷静收束;inactive 文本态(时间待定 / 已取消)。
struct HomeCountdownLockup: View {
    let show: Show

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
            HStack(alignment: .firstTextBaseline) {
                Text(label(for: phase, timeState: timeState, now: now))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(BSColor.Stage.muted)
                Spacer(minLength: 0)
                if let badge = badge(for: phase, timeState: timeState) {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.6)
                        .foregroundColor(badgeColor(for: phase))
                }
            }
            .padding(.bottom, 6)

            switch phase {
            case .pre:
                preCountdown(timeState: timeState, now: now)
            case .live:
                liveStatus(timeState: timeState, now: now)
            case .ended:
                endedStatus(timeState: timeState)
            case .inactive:
                inactiveStatus(timeState: timeState)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: pre:渐进精度倒计时
    // 精度随临近程度收束:>1 天只到「天」超大节拍,<24h 秒开始跳,<1h 时钟变金色。

    @ViewBuilder
    private func preCountdown(timeState: CurrentShowTimeState, now: Date) -> some View {
        if let total = Self.remainingSeconds(to: timeState.effectiveStartTime, from: now) {
            if total >= 86_400 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text("\(total / 86_400)")
                            .font(.system(size: 84, weight: .thin))
                            .tracking(-2.5)
                            .monospacedDigit()
                            .foregroundStyle(Self.heroNumberGradient)
                        Text("天")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    if timeState.isDatedPostponement {
                        Text("原日期 \(Self.originalDateText(for: show)) · 已按新日期重排提醒")
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

    // MARK: live:脉冲 + 已进行

    private func liveStatus(timeState: CurrentShowTimeState, now: Date) -> some View {
        HStack(spacing: 14) {
            HomeLivePulse(reduceMotion: reduceMotion)

            Text("灯光已亮")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(BSColor.Stage.liveTitle)

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(Self.elapsedText(since: timeState.effectiveStartTime, now: now))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.3)
                    .foregroundColor(BSColor.Stage.foreground)
                Text("已进行")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: ended:冷静收束

    private func endedStatus(timeState: CurrentShowTimeState) -> some View {
        let isPostShow = timeState.kind == .postShow
        return VStack(alignment: .leading, spacing: 0) {
            Text(isPostShow ? "已落幕" : "已结束")
                .font(.system(size: 44, weight: .light))
                .tracking(1)
                .foregroundColor(isPostShow ? BSColor.Stage.foreground : BSColor.Stage.dim)

            Text(isPostShow ? timeState.helperText : "这场已落幕 · 首页等待下一场现场")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    // MARK: inactive:已取消 / 时间待定

    private func inactiveStatus(timeState: CurrentShowTimeState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(timeState.title)
                .font(.system(size: 44, weight: .light))
                .tracking(1)
                .foregroundColor(BSColor.Stage.dim)

            Text(timeState.kind == .canceled
                 ? "现场资料保留在我的现场 · 不再收到提醒"
                 : "新日期公布后会继续倒数 · 现场资料都还在")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    // MARK: 文案与样式

    private func label(for phase: HomeShowPhase, timeState: CurrentShowTimeState, now: Date) -> String {
        switch phase {
        case .pre:
            if timeState.isDatedPostponement { return "距离灯亮(新日期)" }
            if let total = Self.remainingSeconds(to: timeState.effectiveStartTime, from: now), total < 3_600 {
                return "快开场了"
            }
            return "距离灯亮"
        case .live: return "演出进行中"
        case .ended: return timeState.kind == .postShow ? "谢幕了 · 回味还在" : "这场已经结束"
        case .inactive: return timeState.kind == .canceled ? "这场取消了" : "倒计时暂停"
        }
    }

    private func badge(for phase: HomeShowPhase, timeState: CurrentShowTimeState) -> String? {
        switch phase {
        case .pre:
            if timeState.isDatedPostponement { return "RESCHEDULED" }
            return timeState.kind == .today ? "TONIGHT" : "COUNTDOWN"
        case .live: return "ON STAGE"
        case .ended: return "ENDED"
        case .inactive: return timeState.kind == .canceled ? "CANCELED" : "TBD"
        }
    }

    private func badgeColor(for phase: HomeShowPhase) -> Color {
        switch phase {
        case .pre: return BSColor.Stage.accent
        case .live: return BSColor.Stage.liveTitle
        case .ended, .inactive: return BSColor.Stage.dim
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
        return "\(components.month ?? 0).\(components.day ?? 0)"
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
