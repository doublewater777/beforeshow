import SwiftUI
import UIKit

struct WidgetSettingsView: View {
    @State private var snapshot: WidgetShowSnapshot?
    @State private var listening: WidgetListeningSnapshot?
    @State private var showAmbient: WidgetAmbientRGB?
    @State private var listeningCover: UIImage?
    @State private var previewTab: WidgetPreviewTab = .homeScreen

    enum WidgetPreviewTab: String, CaseIterable, Identifiable {
        case homeScreen
        case lockScreen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .homeScreen: return BSLocalization.text("主屏幕")
            case .lockScreen: return BSLocalization.text("锁定屏幕")
            }
        }
    }

    private struct AddStep {
        /// nil 时显示 App 图标，对应「在列表里找开场前」这一步
        let symbol: String?
        let title: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: BSSpacing.md) {
                Picker("", selection: $previewTab) {
                    ForEach(WidgetPreviewTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch previewTab {
                case .homeScreen:
                    homeScreenPreview
                    addSteps([
                        AddStep(symbol: "hand.tap.fill", title: BSLocalization.text("长按空白处")),
                        AddStep(symbol: "widget.small.badge.plus", title: BSLocalization.text("编辑 › 添加小组件")),
                        AddStep(symbol: nil, title: BSLocalization.text("搜索「开场前」"))
                    ])
                case .lockScreen:
                    lockScreenPreview
                    addSteps([
                        AddStep(symbol: "hand.tap.fill", title: BSLocalization.text("长按锁屏")),
                        AddStep(symbol: "widget.small.badge.plus", title: BSLocalization.text("自定义 › 添加小组件")),
                        AddStep(symbol: nil, title: BSLocalization.text("选择「开场前」"))
                    ])
                }
            }
            .padding(.horizontal, BSSpacing.md)
            .padding(.vertical, BSSpacing.sm)
        }
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("小组件"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshSnapshot()
        }
    }

    // MARK: - Home Screen Preview

    private var homeScreenPreview: some View {
        HStack(spacing: BSSpacing.md) {
            countdownWidget
                .smallWidgetTile {
                    CoverAmbientBloom(ambient: showAmbient)
                }

            listeningWidget
                .smallWidgetTile {
                    ZStack {
                        BSColor.Stage.background
                        coverImage(listeningCover)
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0), location: 0.3),
                                .init(color: .black.opacity(0.82), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
        }
        .accessibilityHidden(true)
    }

    private var countdownWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BSLocalization.text("距离开场还有"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(BSColor.Stage.muted)

            Spacer(minLength: BSSpacing.xs)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(countdownDays)")
                    .font(.system(size: 56, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(BSColor.Stage.heroIvory)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(BSLocalization.format("天（按天数）", countdownDays))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(BSColor.Stage.muted)
            }
            .lineLimit(1)

            Spacer(minLength: BSSpacing.sm)

            VStack(alignment: .leading, spacing: 1) {
                Text(showTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(2)
                Text(showDateLine)
                    .font(.system(size: 10))
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(1)
            }
        }
    }

    private var listeningWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: BSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(listeningTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(2)
                    if let listeningSubtitle {
                        Text(listeningSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(BSColor.Stage.foreground.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: listening?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Stage.heroWarmGold, in: Circle())
            }
        }
    }

    // MARK: - Lock Screen Preview

    private var lockScreenPreview: some View {
        VStack(spacing: BSSpacing.sm) {
            Text("9:41")
                .font(.system(size: 60, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: BSSpacing.md) {
                Gauge(value: lockGaugeProgress) {
                    EmptyView()
                } currentValueLabel: {
                    VStack(spacing: 1) {
                        Text("\(countdownDays)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.78)
                        Text(BSLocalization.format("天（按天数）", countdownDays))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .gaugeStyle(.accessoryCircular)

                VStack(alignment: .leading, spacing: 1) {
                    Text(BSLocalization.format("还有 %lld 天", countdownDays))
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                    Text(showTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            }
            .foregroundStyle(.white)
            .tint(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSSpacing.roomy)
        .background {
            ZStack {
                CoverAmbientBloom(ambient: showAmbient)
                Color.black.opacity(0.25)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    // MARK: - Add Steps

    private func addSteps(_ steps: [AddStep]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BSColor.Stage.dim)
                        .frame(height: 40)
                }

                VStack(spacing: BSSpacing.sm) {
                    stepIcon(step.symbol)
                    Text(step.title)
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, BSSpacing.md)
        .padding(.horizontal, BSSpacing.xs)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stepIcon(_ symbol: String?) -> some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 40, height: 40)
                .background(BSColor.Stage.accent.opacity(0.12), in: Circle())
        } else {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func coverImage(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Image("default_cover")
                    .resizable()
            }
        }
        .scaledToFill()
    }

    // MARK: - Helpers

    /// 与真实组件一致：按演出时区的自然日差计天。
    private var countdownDays: Int {
        guard let timing = snapshot?.timing else { return 56 }
        return max(0, CurrentShowTimeState(timing: timing).dayDistance)
    }

    /// 与锁屏圆形组件一致：14 天窗口内随临近填满。
    private var lockGaugeProgress: Double {
        let window: Double = 14 * 86_400
        let remaining = snapshot.map { $0.timing.startTime.timeIntervalSinceNow } ?? Double(countdownDays) * 86_400
        return 1 - min(max(remaining, 0), window) / window
    }

    private var showTitle: String {
        snapshot?.name ?? BSLocalization.text("「夜航」巡演 · 上海站")
    }

    private var showDateLine: String {
        guard let snapshot else {
            return BSLocalization.text("10月14日 19:30 · 回声剧场")
        }
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: snapshot.timing.startTime)
        return String(
            format: BSLocalization.text("%d月%d日 %02d:%02d"),
            components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0
        )
    }

    /// 与听歌组件一致：曲目 > 唱片 > 演出名
    private var listeningNowPlaying: String? {
        guard let listening else { return nil }
        return [listening.trackTitle, listening.discTitle].compactMap { $0 }.first { !$0.isEmpty }
    }

    private var listeningTitle: String {
        listeningNowPlaying ?? listening?.showName ?? showTitle
    }

    private var listeningSubtitle: String? {
        guard listeningNowPlaying != nil, let artist = listening?.artistName, !artist.isEmpty else { return nil }
        return artist
    }

    private func refreshSnapshot() {
        snapshot = WidgetSnapshotStore.read()
        listening = WidgetListeningStore.read()
        showAmbient = CoverAmbientColor
            .uiColor(fromCoverAt: WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL))
            .flatMap(WidgetAmbientRGB.init)
        listeningCover = WidgetCoverCache.cachedCoverPath(matching: listening?.coverImageURL)
            .flatMap(UIImage.init(contentsOfFile:))
    }
}

private extension View {
    /// 主屏小号组件外形：正方形、内边距与圆角对齐系统小组件。
    func smallWidgetTile<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        self
            .padding(BSSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .aspectRatio(1, contentMode: .fit)
            .background(background())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
    }
}
