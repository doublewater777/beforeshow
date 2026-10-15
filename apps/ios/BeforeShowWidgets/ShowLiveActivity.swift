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
                let content = LiveActivityContent(state: context.state, isLive: isLive)
                HStack(spacing: 4) {
                    if content.showsWave {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WidgetTheme.live)
                    }
                    LiveActivityTimerText(content: content, fontSize: 11)
                        .frame(width: 48, alignment: .trailing)
                }
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
// context.isStale(staleDate = startDate)。

private struct LiveActivityTimerText: View {
    let content: LiveActivityContent
    var fontSize: CGFloat
    var alignment: TextAlignment = .trailing

    var body: some View {
        Text(content.timerTarget, style: .timer)
            .font(.system(size: fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(content.timerColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(alignment)
            .accessibilityLabel(Text("\(content.kicker) \(Text(content.timerTarget, style: .timer))"))
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
        .frame(width: 44, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 9))
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

// MARK: - 内容
// 设计稿:Design 画布「实时活动」。四种状态共用一套版式:
// 左列 = 状态标签 + 大计时;右列 = 主角(艺人或演出名)+ 舞台/场馆 + 下一场一行。
// 红 = 正在演，金 = 等待开场。

private struct LiveActivityContent {
    enum Mode {
        /// 时刻表里正在演的一场
        case set
        /// 场间:倒数下一场
        case between
        /// 开场前(含音乐节今日首场前)
        case pre
        /// 普通演出已开场
        case started
    }

    struct Next {
        let time: String
        let artist: String
        let stage: String?
        let isInterested: Bool
        let isSoon: Bool
    }

    let mode: Mode
    let kicker: String
    let timerTarget: Date
    let caption: String?
    let title: String
    let subtitle: String?
    let timeRange: String?
    let progress: ClosedRange<Date>?
    let next: Next?

    init(state: ShowLiveActivityAttributes.ContentState, isLive: Bool) {
        let clock = { (date: Date) in LiveActivityCopy.clockText(date, calendar: state.startCalendar) }
        let upcoming = state.nextArtistName.map { artist in
            Next(
                time: state.nextStartsAt.map(clock) ?? "",
                artist: artist,
                stage: state.nextStageName,
                isInterested: state.isInterestedNext,
                isSoon: state.isNextStartingSoon
            )
        }

        if let artist = state.currentArtistName {
            let start = state.currentStartsAt ?? state.startDate
            let end = state.currentEndsAt ?? state.endDate ?? state.startDate
            mode = .set
            kicker = BSLocalization.text("正在演出")
            // 现场模式正在演:倒数到本场结束，配合进度条决定何时去下一个舞台。
            timerTarget = end
            caption = BSLocalization.text("剩余")
            title = artist
            subtitle = state.currentStageName
            timeRange = "\(clock(start))–\(clock(end))"
            progress = start < end ? start...end : nil
            next = upcoming
        } else if state.isFestivalDayActive, let artist = state.nextArtistName {
            // 场间:startDate 指向下一场开演。过点后 app 没来得及更新时,
            // 下一场就是正在演的那场,计时转为已开演时长。
            mode = isLive ? .set : .between
            kicker = BSLocalization.text(isLive ? "正在演出" : "下一场")
            timerTarget = state.nextStartsAt ?? state.startDate
            caption = isLive ? BSLocalization.text("已开场") : nil
            title = artist
            subtitle = state.nextStageName
            timeRange = state.nextStartsAt.map(clock)
            progress = nil
            next = nil
        } else if isLive {
            mode = .started
            kicker = BSLocalization.text("正在现场")
            timerTarget = state.startDate
            caption = BSLocalization.text("已开场")
            title = state.showName
            subtitle = state.endDate.map { BSLocalization.format("预计 %@ 散场", LiveActivityCopy.clockText($0, calendar: state.endCalendar)) }
                ?? state.venueName
            timeRange = nil
            // 普通演出:开场到预计散场的进度，与现场模式同一条进度条。
            progress = state.endDate.flatMap { $0 > state.startDate ? state.startDate...$0 : nil }
            next = nil
        } else {
            mode = .pre
            kicker = BSLocalization.text("距离开场")
            timerTarget = state.startDate
            caption = nil
            title = state.showName
            let opening = BSLocalization.format("%@ 开场", clock(state.startDate))
            if let venue = state.venueName, !venue.isEmpty {
                subtitle = BSLocalization.format("%1$@ · %2$@", opening, venue)
            } else {
                subtitle = opening
            }
            timeRange = nil
            progress = nil
            next = upcoming
        }
    }

    var showsWave: Bool { mode == .set || mode == .started }

    var kickerColor: Color {
        switch mode {
        case .set, .started: WidgetTheme.liveTitle
        case .between: WidgetTheme.accent
        case .pre: WidgetTheme.muted
        }
    }

    var timerColor: Color {
        switch mode {
        case .set, .started: WidgetTheme.foreground
        case .between, .pre: WidgetTheme.heroWarmGold
        }
    }

    var glowColor: Color {
        showsWave ? WidgetTheme.live : WidgetTheme.accent
    }
}

private enum LiveActivityCopy {
    /// 阶段判定:staleDate = startDate 时 isStale 即「已过开场」;
    /// 若 staleDate 已让位给 endDate(开场后才同步),用渲染时刻兜底。
    static func isLive(isStale: Bool, startDate: Date, now: Date = .now) -> Bool {
        isStale || now >= startDate
    }

    /// 24 小时制，时区使用活动所在地。
    static func clockText(_ date: Date, calendar: Calendar) -> String {
        BSDateFormat.clock(date, timeZone: calendar.timeZone)
    }
}

// MARK: - 共用部件

private struct LiveActivityKicker: View {
    let content: LiveActivityContent

    var body: some View {
        HStack(spacing: 5) {
            if content.showsWave {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.live)
            }
            Text(content.kicker)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(content.kickerColor)
                .lineLimit(1)
        }
    }
}

/// 「♥ 18:00 椅子乐团 风舞台」:想看给金心，快开始给红环。
private struct LiveActivityNextLine: View {
    let next: LiveActivityContent.Next

    var body: some View {
        HStack(spacing: 5) {
            if next.isSoon {
                Circle()
                    .strokeBorder(WidgetTheme.live, lineWidth: 1.5)
                    .frame(width: 6, height: 6)
            } else if next.isInterested {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.accent)
            }
            Text(next.time)
                .monospacedDigit()
                .foregroundStyle(WidgetTheme.muted)
            Text(next.artist)
                .fontWeight(.semibold)
                .foregroundStyle(WidgetTheme.foreground)
            if let stage = next.stage {
                Text(stage)
                    .foregroundStyle(WidgetTheme.dim)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}

private struct LiveActivitySetProgress: View {
    let range: ClosedRange<Date>

    var body: some View {
        ProgressView(timerInterval: range, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(WidgetTheme.live)
        .labelsHidden()
    }
}

// MARK: - Dynamic Island expanded bottom
// 封面 3:4 在左;右侧状态行(右端时段或计时)+ 主角 + 舞台;其下进度条与下一场。

private struct LiveActivityExpandedDetails: View {
    let state: ShowLiveActivityAttributes.ContentState
    let isLive: Bool

    var body: some View {
        let content = LiveActivityContent(state: state, isLive: isLive)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                LiveActivityExpandedArtwork(filename: state.coverImageFilename)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        LiveActivityKicker(content: content)
                        Spacer(minLength: 4)
                        if let range = content.timeRange, content.mode == .set {
                            Text(range)
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(WidgetTheme.muted)
                                .lineLimit(1)
                        } else {
                            LiveActivityTimerText(content: content, fontSize: 13)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    Text(content.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(WidgetTheme.muted)
                            .lineLimit(1)
                    }
                }
            }

            if let progress = content.progress {
                LiveActivitySetProgress(range: progress)
            }
            if let next = content.next {
                LiveActivityNextLine(next: next)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .offset(y: -5)
    }
}

// MARK: - Lock Screen
// 两列:左列状态 + 大计时(固定宽,Text(.timer) 理想宽度近乎无限,不能与标题同列争宽);
// 右列主角 + 舞台 + 下一场;现场模式正在演底部给进度条。不放主按钮。

private struct LiveActivityBannerView: View {
    let state: ShowLiveActivityAttributes.ContentState
    let isLive: Bool

    var body: some View {
        let content = LiveActivityContent(state: state, isLive: isLive)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    LiveActivityKicker(content: content)
                    LiveActivityTimerText(content: content, fontSize: 23, alignment: .leading)
                    if let caption = content.caption {
                        Text(caption)
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetTheme.muted)
                            .accessibilityHidden(true)
                    }
                }
                // 「1 小时 24 分钟」这类长计时也要和右列留出呼吸。
                .frame(width: 108, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(2)
                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(WidgetTheme.muted)
                            .lineLimit(1)
                    }
                    if let next = content.next {
                        LiveActivityNextLine(next: next)
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let progress = content.progress {
                LiveActivitySetProgress(range: progress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(alignment: .topLeading) {
            RadialGradient(
                colors: [content.glowColor.opacity(0.22), content.glowColor.opacity(0)],
                center: .topLeading,
                startRadius: 0,
                endRadius: 200
            )
        }
        .activityBackgroundTint(Color.black.opacity(0.72))
        .activitySystemActionForegroundColor(WidgetTheme.foreground)
    }
}
