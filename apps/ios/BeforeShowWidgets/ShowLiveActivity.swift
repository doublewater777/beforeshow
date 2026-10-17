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
                let content = LiveActivityContent(state: context.state, isLive: isLive)
                if let lineup = content.lineup {
                    LiveActivityCompactAvatar(filename: lineup.avatar, name: content.title, size: 22)
                } else if let cover = context.state.coverImageFilename, !cover.isEmpty {
                    LiveActivityCompactAvatar(filename: cover, name: content.title, size: 22)
                } else {
                    LiveActivityAppIconMark(size: 20)
                }
            } compactTrailing: {
                let content = LiveActivityContent(state: context.state, isLive: isLive)
                if content.lineup != nil, content.mode == .set, let progress = content.progress {
                    // 现场模式正在演:右侧一个随本场时间走满的红环，与左侧头像呼应。
                    ZStack {
                        Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 2).padding(0.8)
                        LiveActivityThinRing(progress: progress, size: 20)
                    }
                    .frame(width: 20, height: 20)
                } else if content.mode == .ended {
                    Text(content.kicker)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(content.kickerColor)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 2.5) {
                        if content.showsWave {
                            Image(systemName: "waveform")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(WidgetTheme.live)
                        }
                        LiveActivityTimerText(
                            content: content,
                            fontSize: 11,
                            alignment: content.showsWave ? .leading : .trailing
                        )
                        .frame(width: 44, alignment: content.showsWave ? .leading : .trailing)
                    }
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

struct LiveActivityTimerText: View {
    let content: LiveActivityContent
    var fontSize: CGFloat
    var prefix: String? = nil
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if let prefix, !prefix.isEmpty {
                Text("\(prefix) ")
                    .font(.system(size: fontSize * 0.82, weight: .medium))
                    .foregroundStyle(WidgetTheme.muted)
                +
                Text(content.timerTarget, style: .timer)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(content.timerColor)
            } else {
                Text(content.timerTarget, style: .timer)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(content.timerColor)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .multilineTextAlignment(alignment)
        .accessibilityLabel(Text("\(prefix.map { "\($0) " } ?? "")\(content.kicker) \(Text(content.timerTarget, style: .timer))"))
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

/// 灵动岛 compact 的头像:系统要求图片像素不超过展示区域，否则渲染成灰色占位，
/// 所以先缩到 3x 尺寸再交给归档。
private struct LiveActivityCompactAvatar: View {
    let filename: String?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let filename,
               let image = LiveActivityArtwork.containerImage(filename: filename)
                .map({ LiveActivityArtwork.downscaled($0, maxPixels: size * 3) }) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(WidgetTheme.surfaceRaised)
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(WidgetTheme.foreground)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct LiveActivityExpandedArtwork: View {
    let filename: String?
    var size: CGSize = CGSize(width: 44, height: 58)
    var cornerRadius: CGFloat = 9

    var body: some View {
        Group {
            if let image = LiveActivityArtwork.image(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(WidgetTheme.surfaceRaised)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

enum LiveActivityArtwork {
    /// App Group 内的小图(封面或艺人头像);不做 App 图标兜底。
    static func containerImage(filename: String) -> UIImage? {
        guard !filename.isEmpty, let container = WidgetSnapshotStore.containerURL else { return nil }
        return UIImage(contentsOfFile: container.appendingPathComponent(filename).path)
    }

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
    static func downscaled(_ image: UIImage, maxPixels: CGFloat = 128) -> UIImage {
        guard max(image.size.width, image.size.height) > maxPixels else { return image }
        let size = CGSize(width: maxPixels, height: maxPixels)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
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

struct LiveActivitySetProgress: View {
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

/// 第二行元数据自适应行:空间足够全量展示,空间受限时通过 ViewThatFits 智能降级,并用 layoutPriority 保护关键时间绝不截断。
private struct LiveActivityMetadataLine: View {
    let venue: String?
    let openingText: String
    let endText: String?
    var fontSize: CGFloat = 12

    private var hasVenue: Bool {
        guard let venue else { return false }
        return !venue.isEmpty
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // 阶梯 1: 空间充足时全量展示 (场馆 · 23:00 开场 · 01:00 散场)
            HStack(spacing: 4) {
                if hasVenue {
                    Text(venue!)
                        .truncationMode(.tail)
                    Text("·")
                        .foregroundStyle(WidgetTheme.dim)
                }
                Text(openingText)
                    .monospacedDigit()
                    .layoutPriority(1)
                if let endText {
                    Text("·")
                        .foregroundStyle(WidgetTheme.dim)
                    Text(endText)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
            }

            // 阶梯 2: 空间不足时，若有散场时间优先保散场 (场馆 · 01:00 散场)
            if let endText {
                HStack(spacing: 4) {
                    if hasVenue {
                        Text(venue!)
                            .truncationMode(.tail)
                        Text("·")
                            .foregroundStyle(WidgetTheme.dim)
                    }
                    Text(endText)
                        .monospacedDigit()
                        .layoutPriority(1)
                }
            }

            // 阶梯 3: 仅开场时间 (场馆 · 23:00 开场)
            HStack(spacing: 4) {
                if hasVenue {
                    Text(venue!)
                        .truncationMode(.tail)
                    Text("·")
                        .foregroundStyle(WidgetTheme.dim)
                }
                Text(openingText)
                    .monospacedDigit()
                    .layoutPriority(1)
            }

            // 阶梯 4: 极端极限兜底（仅时间数字）
            Text(endText ?? openingText)
                .monospacedDigit()
        }
        .font(.system(size: fontSize))
        .foregroundStyle(WidgetTheme.muted)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Dynamic Island expanded bottom
// 封面 3:4 在左;右侧状态行(右端时段或计时)+ 主角 + 舞台;其下进度条与下一场。

private struct LiveActivityExpandedDetails: View {
    let state: ShowLiveActivityAttributes.ContentState
    let isLive: Bool

    var body: some View {
        let content = LiveActivityContent(state: state, isLive: isLive)
        Group {
            if let lineup = content.lineup {
                LiveActivityLineup(content: content, lineup: lineup, heroSize: 54)
            } else {
                standard(content)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func standard(_ content: LiveActivityContent) -> some View {
        let openingText = "\(LiveActivityCopy.clockText(state.startDate, calendar: state.startCalendar)) 开场"
        let endText: String? = state.endDate.map { "\(LiveActivityCopy.clockText($0, calendar: state.endCalendar)) 散场" }

        HStack(alignment: .top, spacing: 11) {
            LiveActivityExpandedArtwork(
                filename: state.coverImageFilename,
                size: CGSize(width: 54, height: 72),
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 0) {
                // 1. 巡演标题（最多 2 行）
                Text(content.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                // 2. 第二行：地点与时间锚点（自适应阶梯降级，防超长）
                LiveActivityMetadataLine(
                    venue: state.venueName,
                    openingText: openingText,
                    endText: endText,
                    fontSize: 12
                )

                Spacer(minLength: 4)

                // 3. 第三行：声波 + 正在现场 · 走表 (散场时为：已散场)
                HStack(spacing: 5) {
                    if content.showsWave {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WidgetTheme.live)
                    }
                    Text(content.kicker)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(content.kickerColor)
                        .lineLimit(1)

                    if content.mode != .ended {
                        Text("·")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WidgetTheme.dim)

                        LiveActivityTimerText(
                            content: content,
                            fontSize: 14,
                            prefix: nil,
                            alignment: .leading
                        )
                        .fontWeight(.bold)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
        }
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
        Group {
            if let lineup = content.lineup {
                LiveActivityLineup(content: content, lineup: lineup)
            } else {
                standard(content)
            }
        }
        .padding(16)
        .background(alignment: .topLeading) {
            // 现场模式阵容按稿子用中性底，只靠头像与进度环表达状态；散场态亦无光晕。
            if content.lineup == nil && content.mode != .ended {
                RadialGradient(
                    colors: [content.glowColor.opacity(0.22), content.glowColor.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        }
        .activityBackgroundTint(Color.black.opacity(0.72))
        .activitySystemActionForegroundColor(WidgetTheme.foreground)
    }

    @ViewBuilder
    private func standard(_ content: LiveActivityContent) -> some View {
        let openingText = "\(LiveActivityCopy.clockText(state.startDate, calendar: state.startCalendar)) 开场"
        let endText: String? = state.endDate.map { "\(LiveActivityCopy.clockText($0, calendar: state.endCalendar)) 散场" }

        HStack(alignment: .top, spacing: 14) {
            LiveActivityExpandedArtwork(
                filename: state.coverImageFilename,
                size: CGSize(width: 72, height: 96),
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 0) {
                // 1. 标题：最多两行，字号 17pt bold
                Text(content.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(2)

                Spacer(minLength: 4)

                // 2. 第二行信息：地点与时间锚点（自适应阶梯降级，防超长）
                LiveActivityMetadataLine(
                    venue: state.venueName,
                    openingText: openingText,
                    endText: endText,
                    fontSize: 13
                )

                Spacer(minLength: 4)

                // 3. 状态行：声波 + 正在现场 · 实时走表 (散场时为：已散场)
                HStack(spacing: 5) {
                    if content.showsWave {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WidgetTheme.live)
                    }
                    Text(content.kicker)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(content.kickerColor)
                        .lineLimit(1)

                    if content.mode != .ended {
                        Text("·")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WidgetTheme.dim)

                        LiveActivityTimerText(
                            content: content,
                            fontSize: 16,
                            prefix: nil,
                            alignment: .leading
                        )
                        .fontWeight(.bold)
                    }
                }
            }
            .frame(height: 96)
        }
    }
}
