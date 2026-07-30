import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Show Live Activity
// 设计稿:docs/design/widget/BeforeShow Widgets.html
// 生命周期由 app 侧 ShowLiveActivityController 管理:开场前 12h 内启动,越过谢幕结束。
// 纯展示,无快捷操作(已定稿)。计时用 Text(timerInterval:) 原生跳动。

struct ShowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShowLiveActivityAttributes.self) { context in
            LiveActivityBannerView(
                attributes: context.attributes,
                phase: context.state.phase
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        phaseDot(phase: context.state.phase)
                        Text(context.state.phase == .live ? "LIVE" : "开场前")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(context.state.phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(attributes: context.attributes, phase: context.state.phase)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(context.state.phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.showName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WidgetTheme.foreground)
                                .lineLimit(1)
                            Text(bottomLine(attributes: context.attributes, phase: context.state.phase))
                                .font(.system(size: 11))
                                .foregroundStyle(WidgetTheme.dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                phaseDot(phase: context.state.phase)
            } compactTrailing: {
                timerText(attributes: context.attributes, phase: context.state.phase)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.foreground)
            } minimal: {
                phaseDot(phase: context.state.phase)
            }
        }
    }

    private func phaseDot(phase: ShowLiveActivityPhase) -> some View {
        Circle()
            .fill(phase == .live ? WidgetTheme.live : WidgetTheme.accent)
            .frame(width: 7, height: 7)
    }

    @ViewBuilder
    private func timerText(attributes: ShowLiveActivityAttributes, phase: ShowLiveActivityPhase) -> some View {
        // .timer 双向:未来日期倒数,过去日期正数
        Text(attributes.startDate, style: .timer)
    }

    private func bottomLine(attributes: ShowLiveActivityAttributes, phase: ShowLiveActivityPhase) -> String {
        let venue = attributes.venueName.flatMap { $0.isEmpty ? nil : $0 }
        let city = attributes.city.flatMap { $0.isEmpty ? nil : $0 }
        let place = [city, venue].compactMap { $0 }.joined(separator: " · ")
        if phase == .live, let end = attributes.endDate {
            let components = Calendar.current.dateComponents([.hour, .minute], from: end)
            let endText = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            return place.isEmpty ? "预计 \(endText) 谢幕" : "\(place) · 预计 \(endText) 谢幕"
        }
        return place.isEmpty ? "灯亮之前,先进入状态" : place
    }
}

// MARK: - 锁屏 banner

private struct LiveActivityBannerView: View {
    let attributes: ShowLiveActivityAttributes
    let phase: ShowLiveActivityPhase

    private var coverImage: UIImage? {
        guard let filename = attributes.coverImageFilename,
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

                Text(attributes.startDate, style: .timer)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(phase == .live ? WidgetTheme.liveTitle : WidgetTheme.accent)
            }

            if phase == .live, let end = attributes.endDate, end > attributes.startDate {
                VStack(spacing: 4) {
                    ProgressView(timerInterval: attributes.startDate...end)
                        .tint(WidgetTheme.live)
                    HStack {
                        Text("\(clockText(attributes.startDate)) 开场")
                        Spacer(minLength: 0)
                        Text("预计 \(clockText(end)) 谢幕")
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
        guard let city = attributes.city, !city.isEmpty else { return attributes.showName }
        return "\(attributes.showName) · \(city)站"
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
