import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct WidgetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot: WidgetShowSnapshot?
    @State private var isSyncing = false
    @State private var syncFeedbackMessage: String?
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

    var body: some View {
        List {
            Section {
                VStack(spacing: BSSpacing.sm) {
                    Picker("", selection: $previewTab) {
                        ForEach(WidgetPreviewTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, BSSpacing.xs)

                    switch previewTab {
                    case .homeScreen:
                        homeScreenWidgetCard
                    case .lockScreen:
                        lockScreenWidgetCard
                    }
                }
                .padding(.vertical, BSSpacing.xs)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(header: Text(BSLocalization.text("数据同步"))) {
                Button(action: triggerManualSync) {
                    HStack(spacing: BSSpacing.compact) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(BSColor.Stage.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(BSLocalization.text("立即刷新小组件"))
                                .font(BSFont.V3.body)
                                .foregroundColor(BSColor.Stage.foreground)

                            Text(snapshotStatusText)
                                .font(BSFont.V3.small)
                                .foregroundColor(BSColor.Stage.muted)
                        }

                        Spacer()

                        if isSyncing {
                            ProgressView()
                                .tint(BSColor.Stage.accent)
                        } else if let syncFeedbackMessage {
                            Text(syncFeedbackMessage)
                                .font(BSFont.V3.small.weight(.medium))
                                .foregroundColor(BSColor.Stage.success)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .listRowBackground(BSColor.Stage.surface)
            }

            Section(header: Text(BSLocalization.text("如何添加小组件"))) {
                guideBlock(
                    title: BSLocalization.text("添加至主屏幕"),
                    steps: [
                        BSLocalization.text("长按主屏幕空白处，直到 App 图标开始抖动"),
                        BSLocalization.text("轻点屏幕左上角的「+」号进入小组件库"),
                        BSLocalization.text("搜索并选择「开场前」"),
                        BSLocalization.text("左右滑动挑选小号或中号尺寸，轻点「添加小组件」")
                    ]
                )
                .padding(.vertical, BSSpacing.xs)
                .listRowBackground(BSColor.Stage.surface)

                guideBlock(
                    title: BSLocalization.text("添加至锁定屏幕"),
                    steps: [
                        BSLocalization.text("长按锁定屏幕，轻点底部的「自定」按钮"),
                        BSLocalization.text("选择「锁定屏幕」，轻点时间上方或下方区域"),
                        BSLocalization.text("在小组件列表中选择「开场前」圆形或矩形小组件")
                    ]
                )
                .padding(.vertical, BSSpacing.xs)
                .listRowBackground(BSColor.Stage.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .navigationTitle(BSLocalization.text("小组件"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshSnapshot()
        }
    }

    // MARK: - Preview Cards

    private var homeScreenWidgetCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("距离开场还有"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(BSColor.Stage.muted)

                Spacer(minLength: BSSpacing.xs)

                HStack(alignment: .firstTextBaseline, spacing: BSSpacing.xs) {
                    Text(countdownDaysString)
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(BSColor.Stage.heroIvory)
                        .monospacedDigit()
                    Text(BSLocalization.text("天"))
                        .font(BSFont.V3.body.weight(.medium))
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer(minLength: BSSpacing.sm)

                VStack(alignment: .leading, spacing: 2) {
                    Text(showTitle)
                        .font(BSFont.V3.small.weight(.semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(1)
                    Text(showSubtitle)
                        .font(.system(size: 10))
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            coverView
                .frame(width: 86)
                .clipped()
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [Color(red: 0.018, green: 0.018, blue: 0.025), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                }
                .accessibilityHidden(true)
        }
        .padding(.leading, BSSpacing.md)
        .padding(.vertical, BSSettingsStyle.rowVerticalPadding)
        .frame(height: 154)
        .background {
            backgroundCoverBloom
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private var lockScreenWidgetCard: some View {
        HStack(spacing: BSSpacing.lg) {
            VStack(spacing: BSSpacing.xs) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 4)
                        .frame(width: 58, height: 58)

                    VStack(spacing: 0) {
                        Text(countdownDaysString)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(BSLocalization.text("DAYS"))
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                    }
                }
                Text(BSLocalization.text("圆形小组件"))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
            }

            Spacer(minLength: BSSpacing.xs)

            VStack(spacing: BSSpacing.xs) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(BSLocalization.format("还有 %lld 天", countdownDays))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    Text(showTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)

                    Text(showSubtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .padding(BSSpacing.compact)
                .frame(width: 140, height: 58, alignment: .leading)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(BSLocalization.text("矩形小组件"))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
            }
        }
        .padding(.horizontal, BSSpacing.xl)
        .padding(.vertical, BSSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 154)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var coverView: some View {
        if let imageURLString = snapshot?.coverImageURL,
           let url = URL(string: imageURLString),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image("default_cover")
                .resizable()
                .scaledToFill()
        }
    }

    @ViewBuilder
    private var backgroundCoverBloom: some View {
        if let imageURLString = snapshot?.coverImageURL,
           let url = URL(string: imageURLString),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .overlay(BSColor.Stage.background.opacity(0.82))
        } else {
            Image("default_cover")
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .overlay(BSColor.Stage.background.opacity(0.82))
        }
    }

    // MARK: - Guide View

    private func guideBlock(title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(title)
                .font(BSFont.V3.body.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: BSSpacing.compact) {
                    Text("\(index + 1)")
                        .font(BSFont.V3.caption.weight(.bold))
                        .foregroundColor(BSColor.Stage.accent)
                        .frame(width: 18, height: 18)
                        .background(BSColor.Stage.accent.opacity(0.12))
                        .clipShape(Circle())

                    Text(step)
                        .font(BSFont.V3.small)
                        .foregroundColor(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Helpers

    private var countdownDays: Int {
        guard let timing = snapshot?.timing else { return 56 }
        let now = Date()
        let target = timing.startTime
        let diff = Calendar.current.dateComponents([.day], from: now, to: target).day ?? 0
        return max(0, diff)
    }

    private var countdownDaysString: String {
        "\(countdownDays)"
    }

    private var showTitle: String {
        snapshot?.name ?? BSLocalization.text("「夜航」巡演 · 上海站")
    }

    private var showSubtitle: String {
        guard let snapshot else {
            return BSLocalization.text("10月14日 19:30 · 回声剧场")
        }
        var parts: [String] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        parts.append(formatter.string(from: snapshot.timing.startTime))
        if let venue = snapshot.venueName, !venue.isEmpty {
            parts.append(venue)
        } else if let city = snapshot.city, !city.isEmpty {
            parts.append(city)
        }
        return parts.joined(separator: " · ")
    }

    private var snapshotStatusText: String {
        if let snapshot {
            return BSLocalization.format("当前关联：%@（更新时间 %@）", snapshot.name, formattedDate(snapshot.generatedAt))
        } else {
            return BSLocalization.text("尚未关联现场，添加后将自动展示")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func refreshSnapshot() {
        snapshot = WidgetSnapshotStore.read()
    }

    private func triggerManualSync() {
        isSyncing = true
        syncFeedbackMessage = nil

        Task { @MainActor in
            let shows = (try? modelContext.fetch(FetchDescriptor<Show>())) ?? []
            let selection = (try? modelContext.fetch(FetchDescriptor<CurrentShowSelection>()))?.first

            WidgetDataSync.sync(shows: shows, manualSelection: selection)
            BeforeShowWidgetKind.reloadAllTimelines()

            refreshSnapshot()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSyncing = false
            syncFeedbackMessage = BSLocalization.text("已同步")

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            syncFeedbackMessage = nil
        }
    }
}
