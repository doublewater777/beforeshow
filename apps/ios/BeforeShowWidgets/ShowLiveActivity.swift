import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Show Live Activity
// 生命周期由 app 侧 ShowLiveActivityController 管理(决策在 Shared/LiveActivityPlanner)。
// 无 push 时 ContentState 不能保证在开场/谢幕边界准点 Activity.update；Live Activity 也不使用
// 普通 widget timeline。因此离散文案/颜色必须跨边界始终成立，不能依赖 TimelineView 到点翻转。
// 系统 Text(startDate, style: .timer) 负责自驱计时；下一次 app 同步时 controller 再 update/end。

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
                    layout: .compact
                )
            } minimal: {
                LiveActivityMark(filename: context.state.coverImageFilename, size: 14)
                    .overlay {
                        Circle()
                            .stroke(WidgetTheme.accent, lineWidth: 1.5)
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

// MARK: - 边界安全的实时时间

/// Live Activity 没有可靠的本地「到点重算离散状态」机制。
/// 这里故意只展示跨开场/谢幕都成立的「开场计时」+ 系统 timer：
/// timer 可以自行穿过 0，而标签不会在后台错误残留「还有」「已开场」或 LIVE。
private struct LiveActivityTimeStatus: View {
    enum Layout {
        case compact
        case expanded
        case banner
    }

    let startDate: Date
    let layout: Layout

    var body: some View {
        switch layout {
        case .compact:
            timerText(size: 10.5)
                .minimumScaleFactor(0.65)
                .frame(width: 52, alignment: .trailing)
                .clipped()
        case .expanded:
            VStack(alignment: .trailing, spacing: 1) {
                Text(BSLocalization.text("开场计时"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.muted)
                timerText(size: 17)
            }
        case .banner:
            VStack(alignment: .trailing, spacing: 1) {
                Text(BSLocalization.text("开场计时"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WidgetTheme.muted)
                timerText(size: 20)
            }
        }
    }

    private func timerText(size: CGFloat) -> some View {
        // POSIX 强制紧凑数字格式，避免中文 locale 把 compact 岛展开成「N小时 N分钟」。
        // `.timer` 由系统时钟驱动，不需要 widget timeline，也不会依赖 app 在零点被唤醒。
        Text(startDate, style: .timer)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(WidgetTheme.foreground)
            .lineLimit(1)
            .accessibilityHidden(true)
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
    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        Capsule()
            .fill(WidgetTheme.dim.opacity(0.35))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(WidgetTheme.accent)
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
                    layout: .banner
                )
            }

            if let end = state.endDate, end > state.startDate {
                VStack(spacing: 4) {
                    // 进度是装饰性信息；即使 TimelineView 在锁屏下暂停，核心 timer 仍由系统自驱。
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ProgressView(value: Self.progressFraction(start: state.startDate, end: end, now: context.date))
                            .progressViewStyle(LiveActivityBarStyle())
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
