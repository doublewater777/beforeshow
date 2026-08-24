import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Show Live Activity
// 原型契约:docs/design/live-activity-time-prototype/index.html(HIG 四表面)
// 生命周期由 app 侧 ShowLiveActivityController 管理(决策在 Shared/LiveActivityPlanner)。
//
// 平台事实(实测 iOS 26.5):Live Activity 视图是归档快照,TimelineView 不会
// 每秒重渲染;只有 Text 的系统时间样式(.timer)由系统数据源驱动走动。
// 因此:
// - 可见计时 = Text(state.startDate, style: .timer):开场前倒数、过零自动
//   正计时、永远无正负号。不能加 locale 覆盖(实测 en_US_POSIX 会让 .timer
//   退化成「1 hour, 17 minutes」长句撑破布局)。不覆盖时由系统按 locale 与
//   可用宽度自选格式:zh 锁屏宽卡片倒数为「N 分钟」短语、正计时为纯数字,
//   岛 compact 窄宽度下均为纯数字。
// - 阶段(金/红、「距开场 / 已开场」)= context.isStale 或渲染时刻已过
//   startDate;staleDate 指向 startDate(app 侧 WidgetDataSync),过 T 系统把
//   内容标记 stale 并重渲染翻阶段,无需 push、无需打开 app。
//   hasStarted 仅为兼容保留,UI 不使用。

struct ShowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShowLiveActivityAttributes.self) { context in
            LiveActivityBannerView(
                state: context.state,
                isLive: LiveActivityCopy.isLive(isStale: context.isStale, startDate: context.state.startDate)
            )
        } dynamicIsland: { context in
            let isLive = LiveActivityCopy.isLive(isStale: context.isStale, startDate: context.state.startDate)
            return DynamicIsland {
                // expanded 顶部 leading/trailing 都留空:leading 图标与 bottom 封面位
                // 视觉重复;trailing 计时贴岛右上圆角会被裁。计时改放 bottom 右中,
                // 大字号,与信息列垂直居中。
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityExpandedDetails(state: context.state, isLive: isLive)
                }
            } compactLeading: {
                LiveActivityAppIconMark(size: 20)
            } compactTrailing: {
                LiveActivityTimerText(state: context.state, isLive: isLive, fontSize: 11)
                    .frame(width: 48, alignment: .trailing)
            } minimal: {
                LiveActivityAppIconMark(size: 14)
                    .accessibilityLabel(Text(context.state.showName))
            }
        }
    }
}

// MARK: - 计时文本
// Text(style: .timer) 由系统时间驱动,是 Live Activity 里唯一不依赖 app 运行
// 就能走动的计时;跨零自动从倒数切到正计时,始终无符号。阶段颜色跟
// context.isStale(staleDate = startDate)。不引入 ProgressView /
// GeometryReader(仓库有 Live Activity renderer 因二者崩溃的历史)。

private struct LiveActivityTimerText: View {
    let state: ShowLiveActivityAttributes.ContentState
    let isLive: Bool
    var fontSize: CGFloat

    var body: some View {
        Text(state.startDate, style: .timer)
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(LiveActivityCopy.phaseColor(isLive: isLive))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(.trailing)
            // 阶段 + 动态计时一起读:开场前「距开场 + 倒数」,开场后「已开场 + 正计时」
            .accessibilityLabel(
                Text(LiveActivityCopy.statusLabel(isLive: isLive))
                    + Text(" ")
                    + Text(state.startDate, style: .timer)
            )
    }
}

// MARK: - App 图标 / 演出封面
// compact / minimal 固定用 BeforeShow App 图标(不是封面),多 Activity 竞争时
// 也保持品牌可识别;expanded 顶部不放图标(bottom 封面位已承担识别),
// 封面只出现在 expandedBottom 与锁屏卡片。

private struct LiveActivityAppIconMark: View {
    var size: CGFloat

    var body: some View {
        // 必须走扩展自己 asset catalog 的小图引用:Live Activity 要求图片
        // 分辨率不超过展示区域(岛 minimal/compact 约 45x36.67pt),超了系统
        // 静默渲染成灰色占位圆——实测 1024px 的 PNG(无论包内读取还是
        // asset 引用)都会被占位,20/40/60px 的 1x/2x/3x 才正常。
        Image("live_activity_icon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

private struct LiveActivityExpandedArtwork: View {
    let filename: String?

    var body: some View {
        Group {
            if let image = LiveActivityArtwork.image(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(WidgetTheme.surfaceRaised)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum LiveActivityArtwork {
    static func image(filename: String?) -> UIImage? {
        if let filename, !filename.isEmpty,
           let container = WidgetSnapshotStore.containerURL {
            let cover = UIImage(contentsOfFile: container.appendingPathComponent(filename).path)
            if let cover { return cover }
        }
        return appIcon()
    }

    /// 小组件包里没有 App Icon;从宿主 `.app` 根上的系统导出文件读。
    /// 仅作封面缺失时的兜底(锁屏/expanded 的 UIImage 路径可用),
    /// 灵动岛图标不走这里(见 LiveActivityAppIconMark)。
    static func appIcon() -> UIImage? {
        if let url = Bundle.main.url(forResource: "LiveActivityAppIcon", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return downscaled(image)
        }

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

    /// Live Activity 视图要序列化给系统渲染进程,1024px/1MB 的原图会超预算;
    /// 显示尺寸只有 20-48pt,缩到 128px 足够。
    private static func downscaled(_ image: UIImage, maxPixels: CGFloat = 128) -> UIImage {
        guard max(image.size.width, image.size.height) > maxPixels else { return image }
        let size = CGSize(width: maxPixels, height: maxPixels)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private enum LiveActivityCopy {
    /// expanded 岛与锁屏卡片的详情行:演出名 + 场馆;场馆为空只显示名称。
    static func detailLine(for state: ShowLiveActivityAttributes.ContentState) -> String {
        guard let venue = state.venueName, !venue.isEmpty else { return state.showName }
        return BSLocalization.format("%1$@ · %2$@", state.showName, venue)
    }

    /// 时间元数据合并为一行:开场前「14:49 开场 · 预计 18:49 谢幕」(无预计
    /// 谢幕时仅「14:49 开场」);开场后不再展示开场时刻(正计时与「已开场」
    /// 阶段已表达),只保留「预计 18:49 谢幕」。en:「Starts 14:49 · Est. ends 18:49」。
    static func timeLine(for state: ShowLiveActivityAttributes.ContentState, isLive: Bool) -> String? {
        let end = state.endDate.map { clockText($0, calendar: state.endCalendar) }
        if isLive {
            guard let end else { return nil }
            return BSLocalization.format("预计 %@ 谢幕", end)
        }
        let start = clockText(state.startDate, calendar: state.startCalendar)
        guard let end else { return BSLocalization.format("%@ 开场", start) }
        return BSLocalization.format("%@ 开场 · 预计 %@ 谢幕", start, end)
    }

    static func statusLabel(isLive: Bool) -> String {
        BSLocalization.text(isLive ? "已开场" : "距开场")
    }

    static func phaseColor(isLive: Bool) -> Color {
        isLive ? WidgetTheme.live : WidgetTheme.accent
    }

    /// 阶段判定:staleDate = startDate 时 isStale 即「已过开场」;
    /// 若 staleDate 已让位给 endDate(开场后才同步),用渲染时刻兜底。
    static func isLive(isStale: Bool, startDate: Date, now: Date = .now) -> Bool {
        isStale || now >= startDate
    }

    /// locale-aware 短时间,套用活动自己的时区;语言跟随 App Group 同步的
    /// 语言选择(与 WidgetLanguage 同一来源),未选择时随系统。
    static func clockText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = calendar.timeZone
        if let code = UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?
            .string(forKey: "appLanguage"), !code.isEmpty {
            formatter.locale = Locale(identifier: code)
        }
        return formatter.string(from: date)
    }
}

// MARK: - Dynamic Island expanded bottom
// 两段式:行 1 = 封面(左) + 大字号计时/阶段标签(右);其下通栏 =
// 演出名·场馆(可截断) + 时间行(开场·预计谢幕合并,见 LiveActivityCopy.timeLine)。
// 通栏放下长演出名/场馆,不再与计时抢宽度。顶部 leading/trailing 区域留空
// (见 ShowLiveActivity.body)。

private struct LiveActivityExpandedDetails: View {
    let state: ShowLiveActivityAttributes.ContentState
    let isLive: Bool

    var body: some View {
        // 尺寸/间距对齐设计原型(docs 侧 HTML):行 1 行距 11、行间距 9、
        // 计时与标签距 5、信息区内部距 4;计时 23 > 详情行 15 > 时间行 13 > 标签 12。
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                LiveActivityExpandedArtwork(filename: state.coverImageFilename)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    LiveActivityTimerText(state: state, isLive: isLive, fontSize: 23)
                    Text(LiveActivityCopy.statusLabel(isLive: isLive))
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetTheme.dim)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LiveActivityCopy.detailLine(for: state))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(1)

                if let timeLine = LiveActivityCopy.timeLine(for: state, isLive: isLive) {
                    Text(timeLine)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(WidgetTheme.muted)
                }
            }
        }
        // 对称小内收即可:计时已挪到行 1,远离 bottom 区域伸进岛圆角的右下缘,
        // 旧版为躲圆角的 trailing 36 补偿不再需要(会把计时推得偏左)。
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .offset(y: -5)
    }
}

// MARK: - Lock Screen
// 系统 Live Activity 卡片,14pt 水平边距;与 expanded 岛同款两段式:
// 行 1 = 封面 + 计时/阶段标签,其下通栏 = 演出名·场馆 + 时间行。
// 阶段标签与计时颜色跟 context.isStale(staleDate = startDate,过 T 由系统
// 标记)。可见「距开场 / 已开场」对 VoiceOver 隐藏,阶段前缀已并入计时文本的
// accessibilityLabel,避免重复朗读。

private struct LiveActivityBannerView: View {
    let state: ShowLiveActivityAttributes.ContentState
    let isLive: Bool

    private var coverImage: UIImage? {
        guard let filename = state.coverImageFilename,
              let container = WidgetSnapshotStore.containerURL else {
            return nil
        }
        return UIImage(contentsOfFile: container.appendingPathComponent(filename).path)
    }

    // 两段式:计时独占行 1 右侧,不再与标题同列争宽——绕开 iOS 26.5 实测的
    // 坑(Text(.timer) 理想宽度近乎无限且不吃 minimumScaleFactor,同列
    // 布局下无论 layoutPriority 给哪侧都会截断另一侧)。
    // 尺寸/间距对齐设计原型(docs 侧 HTML):行间距 9、计时与标签距 5、
    // 信息区内部距 4;计时 23 > 详情行 15 > 时间行 13 > 标签 12。
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                coverView

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    LiveActivityTimerText(state: state, isLive: isLive, fontSize: 23)
                    Text(LiveActivityCopy.statusLabel(isLive: isLive))
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetTheme.dim)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LiveActivityCopy.detailLine(for: state))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(1)

                if let timeLine = LiveActivityCopy.timeLine(for: state, isLive: isLive) {
                    Text(timeLine)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .activityBackgroundTint(Color.black.opacity(0.72))
        .activitySystemActionForegroundColor(WidgetTheme.foreground)
    }

    @ViewBuilder
    private var coverView: some View {
        if let coverImage {
            Image(uiImage: coverImage)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let icon = LiveActivityArtwork.appIcon() {
            // 无封面兜底:App 图标铺满封面位
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(WidgetTheme.surfaceRaised)
                .frame(width: 48, height: 48)
        }
    }
}
