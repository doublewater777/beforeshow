import SwiftData
import SwiftUI

// MARK: - Home Feature Kinds & Phase Copy
// 设计稿 phaseFeatures 的 Phase 1 落地：四张功能卡 = 已有四个工具入口，
// 卡片直接内嵌真实数据预览；空态给「快速生成」回到对应工具 sheet。
// ended 阶段设计稿的「回忆清单 / 下一场」属 Phase 2 仪式流程，
// 此阶段 prepare/route 卡保留真实工具文案（见 DESIGN.md 与改版计划）。

enum HomeFeatureKind: String, CaseIterable, Identifiable {
    case setlist, route, prepare, fragment
    var id: Self { self }
}

struct HomeFeatureCopy {
    let badge: String
    let note: String
    let cta: String
}

enum HomeFeatureCopySource {
    static func order(for phase: HomeShowPhase) -> [HomeFeatureKind] {
        switch phase {
        case .pre, .inactive:
            return [.setlist, .route, .prepare, .fragment]
        case .live:
            return [.setlist, .fragment, .prepare, .route]
        case .ended:
            return [.route, .fragment, .setlist, .prepare]
        }
    }

    static func recommended(for phase: HomeShowPhase) -> Set<HomeFeatureKind> {
        switch phase {
        case .pre: return [.setlist]
        case .live: return [.setlist, .fragment]
        case .ended: return [.route]
        case .inactive: return []
        }
    }

    static func dimmed(for phase: HomeShowPhase) -> Set<HomeFeatureKind> {
        switch phase {
        case .pre: return [.fragment]
        case .live: return [.prepare, .route]
        case .ended: return []
        case .inactive: return []
        }
    }

    static func routeDirection(for phase: HomeShowPhase) -> RoundTripDirection {
        phase == .pre || phase == .inactive ? .outbound : .return
    }

    static func hasRoutePlan(_ plan: RoundTripPlan?, for phase: HomeShowPhase) -> Bool {
        plan?.hasPlan(for: routeDirection(for: phase)) == true
    }

    static func copy(for kind: HomeFeatureKind, phase: HomeShowPhase) -> HomeFeatureCopy {
        switch phase {
        case .pre, .inactive:
            switch kind {
            case .setlist:
                return HomeFeatureCopy(badge: "歌单猜想", note: "按本场信息猜想 · 可手动调整", cta: "猜一份歌单")
            case .route:
                return HomeFeatureCopy(badge: "怎么去", note: "按出发地算到场时间", cta: "快速生成")
            case .prepare:
                return HomeFeatureCopy(badge: "出门清单", note: "票证、充电和随身物品", cta: "快速生成")
            case .fragment:
                return HomeFeatureCopy(badge: "现场碎片", note: "独立入口 · 现场随手记瞬间", cta: "开场后再用")
            }
        case .live:
            switch kind {
            case .setlist:
                return HomeFeatureCopy(badge: "本场歌单", note: "打开歌单猜想，对照现场听", cta: "打开歌单")
            case .fragment:
                return HomeFeatureCopy(badge: "现场碎片", note: "歌词、偶遇、舞美，随手记一条", cta: "记一条碎片")
            case .prepare:
                return HomeFeatureCopy(badge: "出门清单", note: "入场已勾完的可收起，现场用碎片", cta: "看清单")
            case .route:
                return HomeFeatureCopy(badge: "怎么去", note: "填好目的地和离开时间", cta: "备好返程")
            }
        case .ended:
            switch kind {
            case .setlist:
                return HomeFeatureCopy(badge: "歌单猜想", note: "回看开场前的猜想", cta: "回看猜想")
            case .fragment:
                return HomeFeatureCopy(badge: "本场碎片", note: "把碎片收进回忆，或再补一条", cta: "回看碎片")
            case .prepare:
                return HomeFeatureCopy(badge: "出门清单", note: "勾过的清单还在这，下次更顺手", cta: "看清单")
            case .route:
                return HomeFeatureCopy(badge: "怎么去", note: "填好目的地和离开时间", cta: "备好返程")
            }
        }
    }
}

// MARK: - Section

struct HomeFeatureCardsSection: View {
    let show: Show
    let phase: HomeShowPhase
    let summary: ShowToolSummary
    /// 已按本场过滤、按 order 排序的歌单猜想曲目。
    let candidateSongs: [CandidateSong]
    let roundTripPlan: RoundTripPlan?
    let preparationPlan: ShowPreparationPlan?
    let onOpen: (HomeFeatureKind) -> Void
    let onOpenMap: (RoundTripDirection) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealsCards = false

    var body: some View {
        // index.html `main` gap: var(--space-4) = 16
        VStack(spacing: 16) {
            ForEach(Array(HomeFeatureCopySource.order(for: phase).enumerated()), id: \.element) { index, kind in
                HomeFeatureCard(
                    kind: kind,
                    copy: HomeFeatureCopySource.copy(for: kind, phase: phase),
                    isFilled: isFilled(kind),
                    isRecommended: HomeFeatureCopySource.recommended(for: phase).contains(kind),
                    isDimmed: HomeFeatureCopySource.dimmed(for: phase).contains(kind),
                    onOpen: { onOpen(kind) }
                ) {
                    preview(for: kind)
                }
                .id("homeCard-\(kind)")
                .opacity(revealsCards || reduceMotion ? 1 : 0)
                .offset(y: revealsCards || reduceMotion ? 0 : 14)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeOut(duration: BSMotion.emphasis).delay(Double(index) * 0.07),
                    value: revealsCards
                )
            }
        }
        .onAppear { revealsCards = true }
        .task(id: DeparturePlanSession(show: show).showFingerprint) {
            guard let roundTripPlan else { return }
            let didInvalidate = roundTripPlan.invalidatePlans(
                ifShowFingerprintChangedTo: DeparturePlanSession(show: show).showFingerprint
            )
            if didInvalidate { try? modelContext.save() }
        }
    }

    private func isFilled(_ kind: HomeFeatureKind) -> Bool {
        switch kind {
        case .setlist: return summary.hasCandidateSongs
        case .route:
            return show.changeStatus == .canceled || HomeFeatureCopySource.hasRoutePlan(roundTripPlan, for: phase)
        case .prepare: return true // 建议项常驻，卡片总是展示可勾清单
        case .fragment: return summary.hasFragments
        }
    }

    @ViewBuilder
    private func preview(for kind: HomeFeatureKind) -> some View {
        switch kind {
        case .setlist:
            HomeSetlistPreview(songs: candidateSongs, showType: show.type, onOpenAll: { onOpen(.setlist) })
        case .route:
            HomeRoutePreview(
                show: show,
                plan: roundTripPlan,
                phase: phase,
                onOpenMap: { onOpenMap(HomeFeatureCopySource.routeDirection(for: phase)) }
            )
        case .prepare:
            HomePreparePreview(
                suggestions: ShowPreparationGuide().sections(for: show).flatMap(\.suggestions),
                plan: preparationPlan,
                onToggle: togglePreparation
            )
        case .fragment:
            HomeFragmentPreview(
                fragments: ShowFragment.sortedByCreationTime(show.fragments).suffix(3).reversed(),
                totalCount: summary.showFragmentsCount,
                onAdd: { onOpen(.fragment) }
            )
        }
    }

    private func togglePreparation(_ text: String) {
        let plan = preparationPlan ?? ShowPreparationPlan(showID: show.id)
        if preparationPlan == nil {
            modelContext.insert(plan)
        }
        plan.setChecked(!plan.isChecked(text), suggestionText: text)
        try? modelContext.save()
    }
}

private struct HomeChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// 卡片空态 CTA：主流程金色实心，次要流程描边 ghost，避免多张卡互相抢视觉权重。
private struct HomeCardCTA: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isPrimary ? .semibold : .medium))
                .foregroundColor(isPrimary ? BSColor.Stage.background : BSColor.Stage.foreground.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background {
                    if isPrimary {
                        Capsule().fill(BSColor.Stage.accent)
                    }
                }
                .overlay {
                    if !isPrimary {
                        Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(HomeChipButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Feature Card Chrome

struct HomeFeatureCard<Content: View>: View {
    let kind: HomeFeatureKind
    let copy: HomeFeatureCopy
    let isFilled: Bool
    let isRecommended: Bool
    let isDimmed: Bool
    let onOpen: () -> Void
    @ViewBuilder var content: Content

    /// Quieter chrome: borderless icon buttons, color only on press.
    private var iconSoft: Color { Color.white.opacity(0.55) }

    var body: some View {
        FeatureCard(
            tone: tone,
            toneOpacity: toneTopOpacity,
            borderOpacity: borderOpacity,
            isRecommended: isRecommended
        ) {
            VStack(alignment: .leading, spacing: 0) {
                // 卡头：分类标签 + 填充态统一入口（与「查看全部」同开 sheet）
                HStack(spacing: 12) {
                    kindLabel
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isFilled {
                        entryButton
                    }
                }
                .frame(minHeight: 36, alignment: .center)

                if isFilled {
                    content
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                        }
                } else {
                    Text(copy.note)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(BSColor.Stage.muted)
                        .lineSpacing(1.5)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)

                    HomeCardCTA(title: copy.cta, isPrimary: isRecommended, action: onOpen)
                        .padding(.top, 14)
                }
            }
        }
        .opacity(isDimmed ? 0.72 : 1)
        .accessibilityElement(children: .contain)
    }

    /// 分类标签：色调小字（无装饰圆点）。
    private var kindLabel: some View {
        Text(copy.badge)
            .font(.system(size: 14, weight: .semibold))
            .tracking(0.56)
            .foregroundColor(badgeTextColor)
    }

    /// 无框圆形入口（仅填充态出现）。歌单与怎么去/出门清单同 icon；点按 = 打开模块（歌单同「查看全部」）。
    private var entryButton: some View {
        Button(action: onOpen) {
            Image(systemName: kind == .fragment ? "plus" : "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconSoft)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeChipButtonStyle())
        .padding(.trailing, -4)
        .accessibilityLabel(kind == .setlist ? "查看全部歌单猜想" : "打开\(copy.badge)")
    }

    private var tone: Color {
        switch kind {
        case .setlist: return BSColor.Stage.accent
        case .route: return BSColor.Stage.route
        case .prepare: return BSColor.Stage.prepare
        case .fragment: return BSColor.Stage.fragment
        }
    }

    private var badgeTextColor: Color {
        switch kind {
        case .setlist: return BSColor.Stage.accent
        case .route: return BSColor.Stage.routeBadge
        case .prepare: return BSColor.Stage.prepareBadge
        case .fragment: return BSColor.Stage.fragmentBadge
        }
    }

    private var toneTopOpacity: Double {
        switch kind {
        case .setlist: return 0.08
        case .route: return 0.10
        case .prepare: return 0.12
        case .fragment: return 0.14
        }
    }

    private var borderOpacity: Double {
        switch kind {
        case .setlist: return 0.24
        case .route: return 0.28
        case .prepare: return 0.30
        case .fragment: return 0.32
        }
    }
}

// MARK: - Setlist Preview

private struct HomeSetlistPreview: View {
    let songs: [CandidateSong]
    let showType: ShowType
    let onOpenAll: () -> Void

    private static let maxRows = 5

    private var mostWantedCount: Int { songs.filter(\.isMostWanted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(songs.prefix(Self.maxRows).enumerated()), id: \.element.id) { _, song in
                SetlistProtoTrackRow(
                    song: song,
                    bare: true,
                    preferArtistSide: showType == .musicFestival
                )
            }

            SetlistProtoOpenAllRow(label: openAllLabel, action: onOpenAll)
        }
    }

    private var openAllLabel: String {
        var label = "查看全部 \(songs.count) 首"
        if mostWantedCount > 0 {
            label += " · 最想看 \(mostWantedCount)"
        }
        return label
    }
}

// MARK: - Route Preview

private struct HomeRoutePreview: View {
    let show: Show
    let plan: RoundTripPlan?
    let phase: HomeShowPhase
    let onOpenMap: () -> Void

    private var direction: RoundTripDirection {
        (phase == .pre || phase == .inactive) ? .outbound : .return
    }

    private var travel: TravelPlan? {
        plan?.plan(for: direction)
    }

    private var session: DeparturePlanSession { DeparturePlanSession(show: show) }

    var body: some View {
        if show.changeStatus == .canceled {
            InlineStatus(text: "这场已取消，无需安排出行", tone: .neutral)
        } else if let travel {
            structuredPlan(travel)
        }
    }

    @ViewBuilder
    private func structuredPlan(_ travel: TravelPlan) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            if travel.validity == .needsRegeneration {
                InlineStatus(text: "现场信息有变，待重新生成方案", tone: .error)
            } else {
                MetricSummaryGrid(metrics: [
                    MetricSummary(label: "预计用时", value: "\(travel.durationMinutes) 分"),
                    MetricSummary(label: "出行方式", value: travel.mode.displayName),
                    MetricSummary(
                        label: direction == .outbound ? "建议出发" : "预计到达",
                        value: direction == .outbound
                            ? session.timeText(travel.leaveAt)
                            : session.timeText(travel.arriveAt, relativeTo: travel.leaveAt)
                    ),
                ])

                TravelTimeline(
                    items: timelineItems(from: travel),
                    interstitialText: travel.mode == .custom ? travel.summary : nil
                )
            }

            HStack(spacing: BSSpacing.sm) {
                Text("更新于 \(capturedText(travel.capturedAt))")
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.dim)
                Spacer(minLength: 0)
                if travel.mode != .custom, travel.navigationURL != nil {
                    Button("在地图中查看", action: onOpenMap)
                        .font(BSFont.V3.caption.weight(.semibold))
                        .foregroundStyle(BSColor.Stage.route)
                }
            }
        }
    }

    private func timelineItems(from travel: TravelPlan) -> [TimelineDisplayItem] {
        travel.timeline.map { node in
            TimelineDisplayItem(
                id: node.id,
                title: node.title,
                detail: node.detail,
                time: node.date.map { session.timeText($0, relativeTo: travel.leaveAt) }
            )
        }
    }

    private func capturedText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Prepare Preview

private struct HomePreparePreview: View {
    let suggestions: [ShowPreparationSuggestion]
    let plan: ShowPreparationPlan?
    let onToggle: (String) -> Void

    private static let maxRows = 4

    private var checkedCount: Int {
        guard let plan else { return 0 }
        return suggestions.filter { plan.isChecked($0.text) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("已完成 \(checkedCount) / \(suggestions.count)")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(BSColor.Stage.muted)
                Spacer(minLength: 0)
                Capsule()
                    .fill(BSColor.Stage.surfaceRaised)
                    .frame(width: 112, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(BSColor.Stage.accent)
                            .frame(width: progressWidth, height: 3)
                    }
            }
            .padding(.bottom, 12)

            ForEach(suggestions.prefix(Self.maxRows)) { suggestion in
                let checked = plan?.isChecked(suggestion.text) == true
                Button {
                    onToggle(suggestion.text)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(checked ? BSColor.Stage.accent : BSColor.Stage.surfaceRaised)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(checked ? .clear : BSColor.Stage.border, lineWidth: 1)
                                )
                            if checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BSColor.Stage.background)
                            }
                        }
                        .padding(.top, 1)

                        Text(suggestion.text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(checked ? BSColor.Stage.muted : BSColor.Stage.foreground)
                            .strikethrough(checked, color: BSColor.Stage.muted)
                            .opacity(checked ? 0.55 : 1)
                            .lineSpacing(2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(suggestion.text)
                .accessibilityValue(checked ? "已完成" : "待准备")
            }

            if suggestions.count > Self.maxRows {
                Text("共 \(suggestions.count) 项 · 点右上角查看全部")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
                    .padding(.top, 4)
            }
        }
    }

    private var progressWidth: CGFloat {
        guard !suggestions.isEmpty else { return 0 }
        return 112 * CGFloat(checkedCount) / CGFloat(suggestions.count)
    }
}

// MARK: - Fragment Preview

private struct HomeFragmentPreview: View {
    let fragments: [ShowFragment]
    let totalCount: Int
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本场已记")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(BSColor.Stage.dim)
                Spacer(minLength: 0)
                Text("\(totalCount) 条")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(.bottom, 6)

            ForEach(fragments, id: \.id) { fragment in
                HStack(alignment: .top, spacing: 12) {
                    Text(Self.timeFormatter.string(from: fragment.createdAt))
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundColor(BSColor.Stage.dim)
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 2)

                    Text(displayText(for: fragment))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let kind = mediaKind(for: fragment) {
                        Text(kind)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BSColor.Stage.fragmentBadge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BSColor.Stage.fragment.opacity(0.14)))
                            .overlay(Capsule().stroke(BSColor.Stage.fragment.opacity(0.30), lineWidth: 1))
                    }
                }
                .padding(.vertical, 9)
            }

            Button(action: onAdd) {
                Text("再记一条")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(BSColor.Stage.background)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(BSColor.Stage.accent))
            }
            .buttonStyle(HomeChipButtonStyle())
            .padding(.top, 8)
        }
    }

    private func displayText(for fragment: ShowFragment) -> String {
        if let text = fragment.text, !text.isEmpty {
            return text
        }
        if fragment.audioReference != nil {
            return "语音碎片"
        }
        if !fragment.galleryMediaReferences.isEmpty {
            return "图片碎片"
        }
        return "未命名瞬间"
    }

    private func mediaKind(for fragment: ShowFragment) -> String? {
        if fragment.audioReference != nil {
            return "语音"
        }
        if fragment.galleryMediaReferences.contains(where: { $0.kind == .video }) {
            return "视频"
        }
        if !fragment.galleryMediaReferences.isEmpty {
            return "图片"
        }
        return nil
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
