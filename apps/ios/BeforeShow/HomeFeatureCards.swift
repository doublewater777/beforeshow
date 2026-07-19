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

struct HomeRecChip: Identifiable, Equatable {
    let kind: HomeFeatureKind
    let title: String
    let isPrimary: Bool
    var id: HomeFeatureKind { kind }
}

struct HomeFeatureCopy {
    let badge: String
    let title: String
    let note: String
    let cta: String
    let filledTitle: String?
    let filledNote: String?

    init(badge: String, title: String, note: String, cta: String, filledTitle: String? = nil, filledNote: String? = nil) {
        self.badge = badge
        self.title = title
        self.note = note
        self.cta = cta
        self.filledTitle = filledTitle
        self.filledNote = filledNote
    }
}

enum HomeFeatureCopySource {
    static func recsLabel(for phase: HomeShowPhase) -> String? {
        switch phase {
        case .pre: return "开场前 · 建议先做这些"
        case .live: return "开场中 · 现场可以这样用"
        case .ended: return "谢幕后 · 把今晚留下来"
        case .inactive: return nil
        }
    }

    static func chips(for phase: HomeShowPhase) -> [HomeRecChip] {
        switch phase {
        case .pre:
            return [
                HomeRecChip(kind: .setlist, title: "生成歌单", isPrimary: true),
                HomeRecChip(kind: .route, title: "算路线", isPrimary: false),
                HomeRecChip(kind: .prepare, title: "出门清单", isPrimary: false),
            ]
        case .live:
            return [
                HomeRecChip(kind: .setlist, title: "看歌单", isPrimary: true),
                HomeRecChip(kind: .fragment, title: "记碎片", isPrimary: true),
                HomeRecChip(kind: .prepare, title: "清单", isPrimary: false),
            ]
        case .ended:
            return [
                HomeRecChip(kind: .fragment, title: "回看碎片", isPrimary: true),
                HomeRecChip(kind: .setlist, title: "回顾歌单", isPrimary: false),
                HomeRecChip(kind: .prepare, title: "出门清单", isPrimary: false),
            ]
        case .inactive:
            return []
        }
    }

    static func order(for phase: HomeShowPhase) -> [HomeFeatureKind] {
        switch phase {
        case .pre, .inactive:
            return [.setlist, .route, .prepare, .fragment]
        case .live:
            return [.setlist, .fragment, .prepare, .route]
        case .ended:
            return [.fragment, .setlist, .prepare, .route]
        }
    }

    static func recommended(for phase: HomeShowPhase) -> Set<HomeFeatureKind> {
        switch phase {
        case .pre: return [.setlist]
        case .live: return [.setlist, .fragment]
        case .ended: return [.fragment]
        case .inactive: return []
        }
    }

    static func dimmed(for phase: HomeShowPhase) -> Set<HomeFeatureKind> {
        switch phase {
        case .pre: return [.fragment]
        case .live: return [.prepare, .route]
        case .ended: return [.route]
        case .inactive: return []
        }
    }

    static func copy(for kind: HomeFeatureKind, phase: HomeShowPhase) -> HomeFeatureCopy {
        switch phase {
        case .pre, .inactive:
            switch kind {
            case .setlist:
                return HomeFeatureCopy(badge: "歌单猜想", title: "这场可能会唱什么", note: "按本场信息猜想 · 可手动调整", cta: "猜一份歌单")
            case .route:
                return HomeFeatureCopy(badge: "怎么去", title: "几点出发比较合适", note: "按出发地算到场时间", cta: "快速生成")
            case .prepare:
                return HomeFeatureCopy(badge: "出门清单", title: "出门前勾一遍", note: "票证、充电和随身物品", cta: "快速生成")
            case .fragment:
                return HomeFeatureCopy(
                    badge: "现场碎片", title: "开场后再记", note: "独立入口 · 现场随手记瞬间", cta: "开场后再用",
                    filledTitle: "碎片本已备好", filledNote: "灯亮后随手记，谢幕可回看"
                )
            }
        case .live:
            switch kind {
            case .setlist:
                return HomeFeatureCopy(
                    badge: "本场歌单", title: "现在对照着听", note: "打开歌单猜想，对照现场听", cta: "打开歌单",
                    filledTitle: "歌单猜想 · 对照听", filledNote: "对照现场，别只顾着拍"
                )
            case .fragment:
                return HomeFeatureCopy(
                    badge: "现场碎片", title: "记下这一刻", note: "歌词、偶遇、舞美，随手记一条", cta: "记一条碎片",
                    filledTitle: "现场碎片本", filledNote: "安可前再扫一眼，别漏掉想记的"
                )
            case .prepare:
                return HomeFeatureCopy(
                    badge: "出门清单", title: "清单先收好", note: "入场已勾完的可收起，现场用碎片", cta: "看清单",
                    filledTitle: "出门清单", filledNote: "票证与充电还在这，需要再勾"
                )
            case .route:
                return HomeFeatureCopy(
                    badge: "散场再说", title: "路线先放一放", note: "现在先沉浸现场，散场再看返程", cta: "稍后再看",
                    filledTitle: "返程路线已备好", filledNote: "散场再点开，先把手机收一收"
                )
            }
        case .ended:
            switch kind {
            case .setlist:
                return HomeFeatureCopy(
                    badge: "本场回顾", title: "今晚唱了什么", note: "回看今晚的歌单猜想", cta: "回顾歌单",
                    filledTitle: "今晚的曲目回顾", filledNote: "对照猜想回味，下次更好猜"
                )
            case .fragment:
                return HomeFeatureCopy(
                    badge: "本场碎片", title: "今晚记下的瞬间", note: "把碎片收进回忆，或再补一条", cta: "回看碎片",
                    filledTitle: "今晚的碎片本", filledNote: "高光瞬间都在这，可随时回看"
                )
            case .prepare:
                return HomeFeatureCopy(badge: "出门清单", title: "今晚的出门清单", note: "勾过的清单还在这，下次更顺手", cta: "看清单")
            case .route:
                return HomeFeatureCopy(badge: "怎么去", title: "几点出发比较合适", note: "按出发地算到场时间", cta: "快速生成")
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
    var onOpenSetlistEdit: (() -> Void)? = nil
    var onOpenSetlistShare: (() -> Void)? = nil
    let onOpenMap: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // index.html `main` gap: var(--space-4) = 16
        VStack(spacing: 16) {
            if let label = HomeFeatureCopySource.recsLabel(for: phase) {
                HomeRecsSection(label: label, chips: HomeFeatureCopySource.chips(for: phase), onOpen: onOpen)
            }

            ForEach(HomeFeatureCopySource.order(for: phase)) { kind in
                HomeFeatureCard(
                    kind: kind,
                    copy: HomeFeatureCopySource.copy(for: kind, phase: phase),
                    isFilled: isFilled(kind),
                    isRecommended: HomeFeatureCopySource.recommended(for: phase).contains(kind),
                    isDimmed: HomeFeatureCopySource.dimmed(for: phase).contains(kind),
                    onOpen: { onOpen(kind) },
                    onEdit: kind == .setlist ? onOpenSetlistEdit : nil,
                    onShare: kind == .setlist ? onOpenSetlistShare : nil
                ) {
                    preview(for: kind)
                }
            }
        }
    }

    private func isFilled(_ kind: HomeFeatureKind) -> Bool {
        switch kind {
        case .setlist: return summary.hasCandidateSongs
        case .route: return summary.hasOutboundPlan
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
            HomeRoutePreview(plan: roundTripPlan, onOpenMap: onOpenMap)
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

// MARK: - Rec Chips

private struct HomeRecsSection: View {
    let label: String
    let chips: [HomeRecChip]
    let onOpen: (HomeFeatureKind) -> Void

    var body: some View {
        // index.html `.phase-recs` gap 10; chips gap 8
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.48)
                .foregroundColor(BSColor.Home.muted)
                .padding(.horizontal, 2)

            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onOpen(chip.kind)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(chip.isPrimary ? BSColor.Home.accent : BSColor.Home.foreground.opacity(0.85))
                                .frame(width: 6, height: 6)
                            Text(chip.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(chip.isPrimary ? BSColor.Home.accent : BSColor.Home.foreground)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(
                            Capsule()
                                .fill(chip.isPrimary ? BSColor.Home.accent.opacity(0.14) : BSColor.Home.foreground.opacity(0.04))
                        )
                        .overlay(
                            Capsule()
                                .stroke(chip.isPrimary ? BSColor.Home.accent.opacity(0.38) : BSColor.Home.foreground.opacity(0.10), lineWidth: 1)
                        )
                    }
                    .buttonStyle(HomeChipButtonStyle())
                    .accessibilityLabel(chip.title)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
    var onEdit: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    @ViewBuilder var content: Content

    /// Prototype `--white-soft` on circular entry/tool icons.
    private var iconSoft: Color { Color.white.opacity(0.72) }

    var body: some View {
        // index.html `.feature-card` padding 18 18 16 + `.section-head` margin-bottom 14
        VStack(alignment: .leading, spacing: 0) {
            sectionHead
                .padding(.bottom, 14)

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
                SetlistProtoPrimaryCTA(title: copy.cta, action: onOpen)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .background(cardSurface)
        .opacity(isDimmed ? 0.72 : 1)
        .accessibilityElement(children: .contain)
    }

    /// `.section-head` = top row + title + note
    private var sectionHead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    badgePill
                    if isRecommended {
                        recPill
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailingChrome
            }
            .frame(minHeight: 28, alignment: .center)
            .padding(.bottom, 10)

            Text(isFilled ? (copy.filledTitle ?? copy.title) : copy.title)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.27) // ~-0.015em at 18px
                .foregroundColor(BSColor.Home.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(isFilled ? (copy.filledNote ?? copy.note) : copy.note)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Home.muted)
                .lineSpacing(1.5)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var trailingChrome: some View {
        // Prototype: empty setlist has no top-right control; filled shows edit + share tools.
        if kind == .setlist {
            if isFilled, onEdit != nil || onShare != nil {
                setlistTools
            }
        } else {
            entryButton
        }
    }

    private var badgePill: some View {
        Text(copy.badge)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.44)
            .foregroundColor(badgeTextColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(badgeFill))
            .overlay(Capsule().stroke(badgeStroke, lineWidth: 1))
    }

    private var recPill: some View {
        Text("此刻推荐")
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(BSColor.Home.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(BSColor.Home.accent.opacity(0.12)))
            .overlay(Capsule().stroke(BSColor.Home.accent.opacity(0.34), lineWidth: 1))
    }

    /// `.section-entry` — 32pt circle, 15pt icon (sliders / plus).
    private var entryButton: some View {
        Button(action: onOpen) {
            Image(systemName: kind == .fragment ? "plus" : "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(iconSoft)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .shadow(color: Color.white.opacity(0.06), radius: 0, y: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(HomeChipButtonStyle())
        .padding(.trailing, -2) // prototype `.section-entry { margin-right: -2px }`
        .accessibilityLabel("打开\(copy.badge)")
    }

    /// Prototype setlist tools: pencil + share-up, 32pt, gap 8, icon 14.
    private var setlistTools: some View {
        HStack(spacing: 8) {
            if let onEdit {
                toolButton(systemName: "pencil", label: "编辑歌单猜想", action: onEdit)
            }
            if let onShare {
                toolButton(systemName: "square.and.arrow.up", label: "分享歌单猜想", action: onShare)
            }
        }
    }

    private func toolButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(iconSoft)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .shadow(color: Color.white.opacity(0.06), radius: 0, y: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(HomeChipButtonStyle())
        .accessibilityLabel(label)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(BSColor.Home.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [tone.opacity(toneTopOpacity), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.40)
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isRecommended ? BSColor.Home.accent.opacity(0.34) : tone.opacity(borderOpacity),
                        lineWidth: 1
                    )
            )
            // Inset top highlight + depth shadow (prototype box-shadow)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .blur(radius: 0.5)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.15)
                        )
                    )
            )
            .shadow(color: .black.opacity(0.34), radius: 18, y: 7)
    }

    private var tone: Color {
        switch kind {
        case .setlist: return BSColor.Home.accent
        case .route: return BSColor.Home.route
        case .prepare: return BSColor.Home.prepare
        case .fragment: return BSColor.Home.fragment
        }
    }

    private var badgeTextColor: Color {
        switch kind {
        case .setlist: return BSColor.Home.accent
        case .route: return BSColor.Home.routeBadge
        case .prepare: return BSColor.Home.prepareBadge
        case .fragment: return BSColor.Home.fragmentBadge
        }
    }

    private var badgeFill: Color {
        switch kind {
        case .setlist: return BSColor.Home.accent.opacity(0.10)
        case .route: return BSColor.Home.route.opacity(0.12)
        case .prepare: return BSColor.Home.prepare.opacity(0.14)
        case .fragment: return BSColor.Home.fragment.opacity(0.14)
        }
    }

    private var badgeStroke: Color {
        switch kind {
        case .setlist: return BSColor.Home.accent.opacity(0.22)
        case .route: return BSColor.Home.route.opacity(0.28)
        case .prepare: return BSColor.Home.prepare.opacity(0.32)
        case .fragment: return BSColor.Home.fragment.opacity(0.34)
        }
    }

    private var toneTopOpacity: Double {
        switch kind {
        case .setlist: return 0.05
        case .route: return 0.07
        case .prepare: return 0.08
        case .fragment: return 0.09
        }
    }

    private var borderOpacity: Double {
        switch kind {
        case .setlist: return 0.16
        case .route: return 0.18
        case .prepare: return 0.20
        case .fragment: return 0.22
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
    let plan: RoundTripPlan?
    let onOpenMap: () -> Void

    var body: some View {
        if let plan, plan.hasSavedDeparturePlan {
            structuredPlan(plan)
        } else if let plan, let content = plan.outboundContent, !content.isEmpty {
            Text(content)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(BSColor.Home.muted)
                .lineSpacing(2)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func structuredPlan(_ plan: RoundTripPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                summaryCell(label: "预计用时", value: plan.departureDurationMinutes.map { "\($0) 分" } ?? "—")
                summaryCell(label: "出行方式", value: plan.savedDepartureMode?.displayName ?? "—")
                summaryCell(label: "预计抵达", value: plan.departureArriveAt.map(Self.timeText) ?? "—")
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                BSColor.Home.foreground.opacity(0.08).frame(height: 1)
            }

            if let leaveAt = plan.departureLeaveAt {
                Text(departureLine(plan: plan, leaveAt: leaveAt))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(BSColor.Home.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let tag = plan.departureExperienceTag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(BSColor.Home.dim)
                }
                Spacer(minLength: 0)
                if plan.savedDepartureNavigationURL != nil {
                    Button("打开地图", action: onOpenMap)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Home.routeBadge)
                        .frame(minHeight: 32)
                        .buttonStyle(HomeChipButtonStyle())
                }
            }
        }
    }

    private func summaryCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(BSColor.Home.dim)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.2)
                .foregroundColor(BSColor.Home.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func departureLine(plan: RoundTripPlan, leaveAt: Date) -> String {
        let origin = plan.departureOrigin ?? "出发地"
        let destination = plan.departureDestination ?? "场馆"
        return "\(Self.timeText(leaveAt)) 出门 · \(origin) → \(destination)"
    }

    private static func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
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
                    .foregroundColor(BSColor.Home.muted)
                Spacer(minLength: 0)
                Capsule()
                    .fill(BSColor.Home.surfaceRaised)
                    .frame(width: 112, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(BSColor.Home.accent)
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
                                .fill(checked ? BSColor.Home.accent : BSColor.Home.surfaceRaised)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(checked ? .clear : BSColor.Home.border, lineWidth: 1)
                                )
                            if checked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BSColor.Home.background)
                            }
                        }
                        .padding(.top, 1)

                        Text(suggestion.text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(checked ? BSColor.Home.muted : BSColor.Home.foreground)
                            .strikethrough(checked, color: BSColor.Home.muted)
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
                    .foregroundColor(BSColor.Home.dim)
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
                    .foregroundColor(BSColor.Home.dim)
                Spacer(minLength: 0)
                Text("\(totalCount) 条")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(BSColor.Home.accent)
            }
            .padding(.bottom, 6)

            ForEach(fragments, id: \.id) { fragment in
                HStack(alignment: .top, spacing: 12) {
                    Text(Self.timeFormatter.string(from: fragment.createdAt))
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundColor(BSColor.Home.dim)
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 2)

                    Text(displayText(for: fragment))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(BSColor.Home.foreground)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let kind = mediaKind(for: fragment) {
                        Text(kind)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BSColor.Home.fragmentBadge)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BSColor.Home.fragment.opacity(0.14)))
                            .overlay(Capsule().stroke(BSColor.Home.fragment.opacity(0.30), lineWidth: 1))
                    }
                }
                .padding(.vertical, 9)
            }

            Button(action: onAdd) {
                Text("再记一条")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(BSColor.Home.background)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(BSColor.Home.accent))
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
