import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Show Live Activity
// 设计稿:docs/design/widget/BeforeShow Widgets.html
// 生命周期由 app 侧 ShowLiveActivityController 管理:
// 预计谢幕前最多 8h 启动(平台活跃上限),越过预计谢幕结束。
// 展示字段在 ContentState;phase 以 start/end 日期为准,减少对 update 的依赖。
// 纯展示,无快捷操作(已定稿)。计时用 Text(timerInterval:) / style: .timer 原生跳动。

struct ShowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShowLiveActivityAttributes.self) { context in
            LiveActivityBannerView(state: context.state)
        } dynamicIsland: { context in
            let phase = LiveActivityPhaseResolver.phase(for: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        phaseDot(phase: phase)
                        Text(phase == .live ? "LIVE" : "开场前")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.showName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WidgetTheme.foreground)
                                .lineLimit(1)
                            Text(bottomLine(state: context.state, phase: phase))
                                .font(.system(size: 11))
                                .foregroundStyle(WidgetTheme.dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                phaseDot(phase: phase)
            } compactTrailing: {
                Text(context.state.startDate, style: .timer)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.foreground)
            } minimal: {
                phaseDot(phase: phase)
            }
        }
    }

    private func phaseDot(phase: ShowLiveActivityPhase) -> some View {
        Circle()
            .fill(phase == .live ? WidgetTheme.live : WidgetTheme.accent)
            .frame(width: 7, height: 7)
    }

    private func bottomLine(state: ShowLiveActivityAttributes.ContentState, phase: ShowLiveActivityPhase) -> String {
        let venue = state.venueName.flatMap { $0.isEmpty ? nil : $0 }
        let city = state.city.flatMap { $0.isEmpty ? nil : $0 }
        let place = [city, venue].compactMap { $0 }.joined(separator: " · ")
        if phase == .live, let end = state.endDate {
            let components = Calendar.current.dateComponents([.hour, .minute], from: end)
            let endText = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            return place.isEmpty ? "预计 \(endText) 谢幕" : "\(place) · 预计 \(endText) 谢幕"
        }
        return place.isEmpty ? "灯亮之前,先进入状态" : place
    }
}

// MARK: - Phase from dates
// ContentState.phase 只在 app update 时刷新;UI 以 startDate 为准,避免过期 phase 误导。

enum LiveActivityPhaseResolver {
    static func phase(for state: ShowLiveActivityAttributes.ContentState, now: Date = .now) -> ShowLiveActivityPhase {
        if now >= state.startDate {
            return .live
        }
        return .countdown
    }
}

// MARK: - 锁屏 banner

private struct LiveActivityBannerView: View {
    let state: ShowLiveActivityAttributes.ContentState

    private var phase: ShowLiveActivityPhase {
        LiveActivityPhaseResolver.phase(for: state)
    }

    private var coverImage: UIImage? {
        guard let filename = state.coverImageFilename,
              let container = WidgetSnapshotStore.containerURL else {
            return nil
        }
        return UIImage(contentsOfFile: container.appendingPathComponent(filename).path)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                coverView

                VStack(alignment: .leading, spacing: 1) {
                    Text(titleLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if phase == .live {
                            Circle()
                                .fill(WidgetTheme.live)
                                .frame(width: 6, height: 6)
                        }
                        Text(phase == .live ? "LIVE · 开场中" : "即将灯亮")
                            .font(.system(size: 11))
                            .foregroundStyle(phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
                    }
                }

                Spacer(minLength: 0)

                Text(state.startDate, style: .timer)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
            }

            // 进度条不依赖 phase update:有 endDate 就画,ProgressView 自驱;开场前进度为 0。
            if let end = state.endDate, end > state.startDate {
                VStack(spacing: 4) {
                    ProgressView(timerInterval: state.startDate...end)
                        .tint(phase == .live ? WidgetTheme.live : WidgetTheme.accent)
                    HStack {
                        Text("\(clockText(state.startDate)) 开场")
                        Spacer(minLength: 0)
                        Text("预计 \(clockText(end)) 谢幕")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.dim)
                    .monospacedDigit()
                }
                .opacity(phase == .live ? 1 : 0.55)
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

    private func clockText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
