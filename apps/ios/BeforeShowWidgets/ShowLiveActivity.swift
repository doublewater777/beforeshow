import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Show Live Activity
// 生命周期由 app 侧 ShowLiveActivityController 管理(决策在 Shared/LiveActivityPlanner)。
// ContentState 无 push 时不能保证在开场/谢幕边界被 app 主动改写，所以数字继续依赖系统 .timer 自驱。
// TimelineView 只负责从当前时间推导三态：开场前暖金、现场中 live 色、预计谢幕后待确认。

struct ShowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShowLiveActivityAttributes.self) { context in
            LiveActivityBannerView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityMark(filename: context.state.coverImageFilename, size: 32)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityTimeStatus(
                        startDate: context.state.startDate,
                        endDate: context.state.endDate,
                        layout: .expanded
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.showName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WidgetTheme.foreground)
                                .lineLimit(1)
                            Text(bottomLine(state: context.state))
                                .font(.system(size: 11))
                                .foregroundStyle(WidgetTheme.dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                LiveActivityMark(filename: context.state.coverImageFilename, size: 20)
            } compactTrailing: {
                LiveActivityTimeStatus(
                    startDate: context.state.startDate,
                    endDate: context.state.endDate,
                    layout: .compact
                )
            } minimal: {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let phase = LiveActivityClockPhase.resolve(
                        now: timeline.date,
                        startDate: context.state.startDate,
                        endDate: context.state.endDate
                    )
                    LiveActivityMark(filename: context.state.coverImageFilename, size: 14)
                        .overlay {
                            Circle()
                                .stroke(phase.ringColor, lineWidth: 1.5)
                        }
                }
            }
        }
    }

    private func bottomLine(state: ShowLiveActivityAttributes.ContentState) -> String {
        let venue = state.venueName.flatMap { $0.isEmpty ? nil : $0 }
        let city = state.city.flatMap { $0.isEmpty ? nil : $0 }
        let place = [city, venue].compactMap { $0 }.joined(separator: " · ")
        if let end = state.endDate {
            let components = state.endCalendar.dateComponents([.hour, .minute], from: end)
            let endText = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            let endLine = BSLocalization.format("预计 %@ 谢幕", endText)
            return place.isEmpty ? endLine : "\(place) · \(endLine)"
        }
        return place.isEmpty ? BSLocalization.text("灯亮之前,先进入状态") : place
    }
}

// MARK: - 实时时间语义

private enum LiveActivityClockPhase: Equatable {
    case before
    case live
    case awaitingEndConfirmation

    static func resolve(now: Date, startDate: Date, endDate: Date?) -> Self {
        if now < startDate { return .before }
        if let endDate, now >= endDate { return .awaitingEndConfirmation }
        return .live
    }

    var color: Color {
        switch self {
        case .before: return WidgetTheme.accent
        case .live: return WidgetTheme.liveTitle
        case .awaitingEndConfirmation: return WidgetTheme.muted
        }
    }

    var ringColor: Color {
        switch self {
        case .before: return WidgetTheme.accent
        case .live: return WidgetTheme.live
        case .awaitingEndConfirmation: return WidgetTheme.dim
        }
    }
}

private struct LiveActivityTimeStatus: View {
    enum Layout {
        case compact
        case expanded
        case banner
    }

    let startDate: Date
    let endDate: Date?
    let layout: Layout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let phase = LiveActivityClockPhase.resolve(
                now: context.date,
                startDate: startDate,
                endDate: endDate
            )

            switch layout {
            case .compact:
                compactView(phase: phase)
            case .expanded:
                expandedView(phase: phase, now: context.date)
            case .banner:
                bannerView(phase: phase, now: context.date)
            }
        }
    }

    @ViewBuilder
    private func compactView(phase: LiveActivityClockPhase) -> some View {
        switch phase {
        case .before, .live:
            HStack(spacing: 3) {
                Text(BSLocalization.text(phase == .live ? "已开" : "还有"))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(phase.color.opacity(0.92))
                timerText(size: 10.5, color: phase.color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 72, alignment: .trailing)
            .clipped()
        case .awaitingEndConfirmation:
            Text(BSLocalization.text("待确认"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
                .frame(width: 72, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func expandedView(phase: LiveActivityClockPhase, now: Date) -> some View {
        switch phase {
        case .before, .live:
            VStack(alignment: .trailing, spacing: 1) {
                statusLabel(phase: phase, size: 9)
                timerText(size: 17, color: phase.color)
                Text(unitLegend(now: now))
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(WidgetTheme.dim)
            }
        case .awaitingEndConfirmation:
            Text(BSLocalization.text("待确认"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetTheme.muted)
        }
    }

    @ViewBuilder
    private func bannerView(phase: LiveActivityClockPhase, now: Date) -> some View {
        switch phase {
        case .before, .live:
            VStack(alignment: .trailing, spacing: 1) {
                statusLabel(phase: phase, size: 9.5)
                timerText(size: 20, color: phase.color)
                Text(unitLegend(now: now))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(WidgetTheme.dim)
            }
        case .awaitingEndConfirmation:
            VStack(alignment: .trailing, spacing: 2) {
                Text(BSLocalization.text("待确认"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetTheme.muted)
                Text(BSLocalization.text("已到预计散场时间"))
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.dim)
            }
        }
    }

    private func statusLabel(phase: LiveActivityClockPhase, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            if phase == .live {
                LiveActivityDot(size: size <= 9 ? 5 : 6)
            }
            Text(BSLocalization.text(phase == .live ? "已开场" : "距离开场"))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(phase.color.opacity(0.94))
        }
    }

    private func timerText(size: CGFloat, color: Color) -> some View {
        // POSIX 强制数字格式，避免中文 locale 把 compact 岛展开成「N小时 N分钟」。
        // .timer 由系统自驱，跨过 0 后继续正向计时；TimelineView 只负责标签和颜色翻转。
        Text(startDate, style: .timer)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityHidden(true)
    }

    private func unitLegend(now: Date) -> String {
        let seconds = abs(Int(now.timeIntervalSince(startDate)))
        return seconds >= Int(CountdownTimePresentationPolicy.hourThreshold)
            ? BSLocalization.text("时 : 分 : 秒")
            : BSLocalization.text("分 : 秒")
    }
}

private struct LiveActivityDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(WidgetTheme.live)
            .frame(width: size, height: size)
    }
}

// MARK: - 封面 / App 图标
// compact / minimal 空间只够一枚圆标;封面优先,读不到再回退宿主 App 图标。

private struct LiveActivityMark: View {
    let filename: String?
    var size: CGFloat

    var body: some View {
        Group {
            if let image = LiveActivityArtwork.image(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(WidgetTheme.surfaceRaised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private enum LiveActivityArtwork {
    static func image(filename: String?) -> UIImage? {
        if let filename, !filename.isEmpty,
           let container = WidgetSnapshotStore.containerURL {
            let cover = UIImage(contentsOfFile: container.appendingPathComponent(filename).path)
            if let cover { return cover }
        }
        return appIcon()
    }

    /// 小组件包里没有 App Icon;从宿主 `.app` 根上的系统导出文件读。
    static func appIcon() -> UIImage? {
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let names = [
            "AppIcon60x60@3x.png",
            "AppIcon60x60@2x.png",
            "AppIcon76x76@2x~ipad.png",
        ]
        for name in names {
            if let image = UIImage(contentsOfFile: app.appendingPathComponent(name).path) {
                return image
            }
        }
        return nil
    }
}

// MARK: - 锁屏 banner

/// 默认 linear 样式内部是 GeometryReader;LA 内容换入动画期间会把非法(负/非有限)尺寸
/// 传进 LayoutSubview.place,直接 assert 崩掉整个 WidgetRenderer_Activities 进程。
/// 保持 scaleEffect 实现，不重新引入 GeometryReader。
private struct LiveActivityBarStyle: ProgressViewStyle {
    let fillColor: Color

    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        Capsule()
            .fill(WidgetTheme.dim.opacity(0.35))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(fillColor)
                    .scaleEffect(x: fraction, anchor: .leading)
            }
            .clipShape(Capsule())
            .frame(height: 3)
    }
}

private struct LiveActivityBannerView: View {
    let state: ShowLiveActivityAttributes.ContentState

    private var coverImage: UIImage? {
        guard let filename = state.coverImageFilename,
              let container = WidgetSnapshotStore.containerURL else {
            return nil
        }
        return UIImage(contentsOfFile: container.appendingPathComponent(filename).path)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                coverView

                VStack(alignment: .leading, spacing: 1) {
                    Text(titleLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                    Text(BSLocalization.format("%@ 开场", clockText(state.startDate, calendar: state.startCalendar)))
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetTheme.muted)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                LiveActivityTimeStatus(
                    startDate: state.startDate,
                    endDate: state.endDate,
                    layout: .banner
                )
            }

            if let end = state.endDate, end > state.startDate {
                VStack(spacing: 4) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let phase = LiveActivityClockPhase.resolve(
                            now: context.date,
                            startDate: state.startDate,
                            endDate: end
                        )
                        ProgressView(value: Self.progressFraction(start: state.startDate, end: end, now: context.date))
                            .progressViewStyle(LiveActivityBarStyle(fillColor: phase.ringColor))
                    }
                    .accessibilityHidden(true)
                    HStack {
                        Spacer(minLength: 0)
                        Text(BSLocalization.format("预计 %@ 谢幕", clockText(end, calendar: state.endCalendar)))
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.dim)
                    .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color.black.opacity(0.72))
        .activitySystemActionForegroundColor(WidgetTheme.foreground)
    }

    private var titleLine: String {
        guard let city = state.city, !city.isEmpty else { return state.showName }
        return "\(state.showName) · \(city)站"
    }

    @ViewBuilder
    private var coverView: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(WidgetTheme.surfaceRaised)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "ticket")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WidgetTheme.accent)
                }
        }
    }

    private func clockText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// 进度条 fraction:配合上面的 TimelineView 每秒重算。
    fileprivate static func progressFraction(start: Date, end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }
}
