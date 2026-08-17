import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Show Live Activity
// 设计稿:docs/design/widget/BeforeShow Widgets.html
// 生命周期由 app 侧 ShowLiveActivityController 管理(决策在 Shared/LiveActivityPlanner)。
//
// 关键约束(评审定稿):无 push 时 ContentState 只在 app 运行时更新,
// 不能依赖任何「到点自动切换」——所以 UI 是中性设计:
// - 文案跨开场/谢幕零点恒成立(「19:30 开场」「预计 22:00 谢幕」)
// - 计时 Text(startDate, style: .timer) 系统自驱,倒数后自动正数
// - 进度由 TimelineView 每秒重算 fraction(不用 ProgressView(timerInterval:),
//   其默认 linear 样式的 GeometryReader 会崩 LA 渲染进程,见 LiveActivityBarStyle)
// - 无 LIVE 徽标/红点:越过谢幕也不会残留「LIVE」误导

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
                    Text(context.state.startDate, style: .timer)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.accent)
                        .accessibilityHidden(true)
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
                // style:.timer 中文会按「N小时 N分钟」抢理想宽度,把 compact 岛拉满整条顶栏。
                // 定宽 + POSIX 数字,岛只包住镜头两侧一小截。
                Text(context.state.startDate, style: .timer)
                    .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: 48, alignment: .trailing)
                    .clipped()
                    .accessibilityHidden(true)
            } minimal: {
                LiveActivityMark(filename: context.state.coverImageFilename, size: 14)
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
/// 传进 LayoutSubview.place,直接 assert 崩掉整个 WidgetRenderer_Activities 进程
/// (2026-08-15~17 共 26 份同签名崩溃:GeometryReaderLayout.placeSubviews → place)。
/// 改为 scaleEffect 实现:不需要测量容器宽度,也不引入 GeometryReader;
/// 驱动方是外面的 TimelineView(每秒重算 fraction 传进来)。
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
                        .foregroundStyle(WidgetTheme.accent)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    // 不要加 .fixedSize():iOS 26.5 LA renderer 下会把整个 VStack
                    // 渲染成空白(2026-08-17 实测,静态文本同样消失)。
                    // banner 的 .timer 系统自驱,按分钟刷新(「1小时43分钟」);
                    // 秒级跳动在 compact 岛(数字格式)。Text(timerInterval:) 秒位
                    // 在 LA 里渲染成「——」,不要用。
                    Text(state.startDate, style: .timer)
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.accent)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                    if state.hasStarted ?? (Date() >= state.startDate) {
                        Text("已开场")
                            .font(.system(size: 10))
                            .foregroundStyle(WidgetTheme.dim)
                    }
                }
            }

            // 进度条:不用 ProgressView(timerInterval:)——默认 linear 样式内部的
            // GeometryReader 会崩 LA 渲染进程(见 LiveActivityBarStyle)。
            // 用 TimelineView 每秒重算 fraction + 手画 Capsule;TimelineView 在 LA 里
            // 不是每次熄屏都跳,但进度条允许短暂停留,计时数字由 .timer 系统自驱兜底。
            if let end = state.endDate, end > state.startDate {
                VStack(spacing: 4) {
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
