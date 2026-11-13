import PostHog
import SwiftUI
import UIKit
import WidgetKit

struct WidgetSettingsView: View {
    @State private var snapshot: WidgetShowSnapshot?
    @State private var listening: WidgetListeningSnapshot?
    @State private var showAmbient: WidgetAmbientRGB?
    @State private var cachedCoverPath: String?
    @State private var cachedListeningCoverPath: String?
    @State private var previewTab: WidgetPreviewTab = .homeScreen
    @State private var homeWidgetSize: HomeWidgetSize = .small

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

    enum HomeWidgetSize: String, CaseIterable, Identifiable {
        case small
        case medium

        var id: String { rawValue }

        var title: String {
            switch self {
            case .small: return BSLocalization.text("小号")
            case .medium: return BSLocalization.text("中号")
            }
        }

        var widgetFamily: WidgetFamily {
            switch self {
            case .small: return .systemSmall
            case .medium: return .systemMedium
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
                    Picker("", selection: $homeWidgetSize) {
                        ForEach(HomeWidgetSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, BSSpacing.xs)

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
        .postHogScreenView("widget_settings")
        .onAppear {
            refreshSnapshot()
        }
    }

    // MARK: - Home Screen Preview

    @ViewBuilder
    private var homeScreenPreview: some View {
        switch homeWidgetSize {
        case .small:
            HStack(spacing: BSSpacing.md) {
                CountdownWidgetCard(
                    presentation: countdownPresentation,
                    family: .systemSmall,
                    coverImagePath: cachedCoverPath,
                    ambientColor: showAmbient
                )

                ListeningWidgetCard(
                    entry: listeningEntry,
                    family: .systemSmall
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        case .medium:
            VStack(spacing: BSSpacing.md) {
                CountdownWidgetCard(
                    presentation: countdownPresentation,
                    family: .systemMedium,
                    coverImagePath: cachedCoverPath,
                    ambientColor: showAmbient
                )

                ListeningWidgetCard(
                    entry: listeningEntry,
                    family: .systemMedium
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Lock Screen Preview

    private var lockScreenPreview: some View {
        VStack(spacing: BSSpacing.sm) {
            Text("9:41")
                .font(.system(size: 60, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: BSSpacing.md) {
                CircularCountdownView(presentation: countdownPresentation)
                    .frame(width: 70, height: 70)

                RectangularCountdownView(presentation: countdownPresentation)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, BSSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSSpacing.roomy)
        .background {
            ZStack {
                WidgetPhaseBloom(tone: countdownPresentation.bloomTone, ambient: showAmbient)
                Color.black.opacity(0.3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Add Steps

    private func addSteps(_ steps: [AddStep]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.dim)
                        .frame(height: 40)
                }

                VStack(spacing: BSSpacing.sm) {
                    stepIcon(step.symbol)
                    Text(step.title)
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.foreground)
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
                .foregroundStyle(BSColor.Stage.accent)
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

    // MARK: - Presentation & Data Providers

    private var countdownPresentation: CountdownPresentation {
        if let snapshot {
            let entry = CountdownEntry(
                date: .now,
                snapshot: snapshot,
                coverImagePath: cachedCoverPath,
                ambientColor: showAmbient
            )
            return CountdownPresentation(entry: entry)
        }
        // 占位示范数据：夜航上海站，56 天倒计时
        let demoTiming = ShowTimingFields(
            date: Calendar.current.date(byAdding: .day, value: 56, to: .now) ?? .now,
            startTime: Calendar.current.date(byAdding: .day, value: 56, to: .now) ?? .now,
            endDate: nil,
            endTime: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        let demoSnapshot = WidgetShowSnapshot(
            showID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: BSLocalization.text("「夜航」巡演 · 上海站"),
            city: BSLocalization.text("上海"),
            venueName: BSLocalization.text("回声剧场"),
            coverImageURL: nil,
            timing: demoTiming,
            generatedAt: .now
        )
        return CountdownPresentation(entry: CountdownEntry(
            date: .now,
            snapshot: demoSnapshot,
            coverImagePath: nil,
            ambientColor: showAmbient
        ))
    }

    private var listeningEntry: ListeningEntry {
        if let listening {
            return ListeningEntry(
                date: .now,
                snapshot: listening,
                coverImagePath: cachedListeningCoverPath
            )
        }
        // 占位示范数据：回春丹热门合辑
        let demoListening = WidgetListeningSnapshot(
            showID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            showName: BSLocalization.text("「夜航」巡演 · 上海站"),
            artistName: BSLocalization.text("回春丹"),
            discTitle: BSLocalization.text("热门合辑 01"),
            trackTitle: BSLocalization.text("艾蜜莉"),
            coverImageURL: nil,
            trackCount: 12,
            phase: .playing,
            control: .play,
            hasSession: true,
            generatedAt: .now
        )
        return ListeningEntry(
            date: .now,
            snapshot: demoListening,
            coverImagePath: nil
        )
    }

    private func refreshSnapshot() {
        snapshot = WidgetSnapshotStore.read()
        listening = WidgetListeningStore.read()
        cachedCoverPath = WidgetCoverCache.cachedCoverPath(matching: snapshot?.coverImageURL)
        cachedListeningCoverPath = WidgetCoverCache.cachedCoverPath(matching: listening?.coverImageURL)
        showAmbient = CoverAmbientColor
            .uiColor(fromCoverAt: cachedCoverPath)
            .flatMap(WidgetAmbientRGB.init)
    }
}
