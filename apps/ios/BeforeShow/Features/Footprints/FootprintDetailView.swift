import Foundation
import SwiftData
import SwiftUI
import UIKit

private struct FootprintMemoryTarget: Identifiable {
    let fragment: MemoryFragment
    let initialIndex: Int

    var id: UUID { fragment.id }
}

struct FootprintDetailView: View {
    let show: Show
    let archive: FootprintArchiveSnapshot
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var notificationStates: [NotificationSchedulingState]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var memoryTarget: FootprintMemoryTarget?
    @State private var showingAssetKind: ShowAssetKind?
    @State private var isShowingShareComposer = false
    @State private var isShowingDispersalShare = false
    @State private var isShowingCeremonyEditor = false
    @State private var isShowingEditor = false
    @State private var isShowingMemoryPage = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var toast: BSToastPayload?

    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    init(
        show: Show,
        archive: FootprintArchiveSnapshot,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.show = show
        self.archive = archive
        self.onDetailVisibilityChange = onDetailVisibilityChange
        let showID = show.id
        _fragments = Query(
            filter: #Predicate<MemoryFragment> { $0.showID == showID },
            sort: [
                SortDescriptor(\MemoryFragment.createdAt, order: .forward),
                SortDescriptor(\MemoryFragment.id, order: .forward)
            ]
        )
        _assets = Query(
            filter: #Predicate<ShowAsset> { $0.showID == showID },
            sort: [SortDescriptor(\ShowAsset.createdAt, order: .forward)]
        )
    }

    /// 打开过这场的足迹详情，「足迹」这个推荐就算用过了（ADR 0037）。
    private func markFootprintRecommendationHandled() {
        do {
            if try FeatureRecommendationLedger.markHandled(showID: show.id, feature: .footprint, in: modelContext) {
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
        }
    }

    private var identity: FootprintDetailIdentity {
        FootprintDetailIdentityBuilder.make(show: show, archive: archive)
    }

    private var detailCover: FootprintCover? {
        FootprintCoverResolver.resolve(
            shows: archive.shows,
            fragments: fragments,
            assets: assets
        )[show.id]
    }

    /// 单场观看时长:已确认散场用真实时刻,否则用录入结束时间或默认估算。
    private var durationText: String? {
        let calendar = show.timingCalendar()
        let timeState = CurrentShowTimeState(show: show, calendar: calendar)
        guard let minutes = ShowDurationFormatter.minutes(for: show, timeState: timeState) else { return nil }
        return ShowDurationFormatter.single(totalMinutes: minutes)
    }

    private var isDynamicCoverPlaybackActive: Bool {
        FootprintPlaybackPolicy.isActive(
            sceneIsActive: scenePhase == .active,
            hasMemoryOverlay: memoryTarget != nil || isShowingMemoryPage,
            hasAssetOverlay: showingAssetKind != nil,
            hasShareOverlay: isShowingShareComposer || isShowingDispersalShare,
            hasEditorOverlay: isShowingEditor || isShowingCeremonyEditor
        )
    }

    private var shareRoute: FootprintDetailShareRoute {
        FootprintDetailShareRoute.resolve(
            hasShareMaterials: !shareMaterials.isEmpty,
            rating: show.rating,
            note: show.closingNote
        )
    }

    private var shareMaterials: [FootprintShareMaterial] {
        var sources = fragments.flatMap { fragment -> [FootprintShareSource] in
            let mediaSources = fragment.orderedMediaItems.map { item in
                FootprintShareSource(
                    id: item.id,
                    kind: item.kind == .photo ? .photo : .videoCover,
                    recordedAt: item.createdAt,
                    imageURL: MemoryMediaLocation.applicationSupport().url(
                        for: item.thumbnailRelativePath ?? item.relativePath
                    )
                )
            }
            guard mediaSources.isEmpty else { return mediaSources }
            return [FootprintShareSource(
                id: fragment.id,
                kind: .text,
                recordedAt: fragment.createdAt,
                imageURL: nil
            )]
        }
        if let location = try? ShowAssetMediaLocation.applicationSupport() {
            sources += assets.map { asset in
                FootprintShareSource(
                    id: asset.id,
                    kind: asset.kind == .ticket ? .ticket : .timetable,
                    recordedAt: asset.createdAt,
                    imageURL: location.rootDirectory.appendingPathComponent(asset.relativePath)
                )
            }
        }
        return FootprintShareMaterialBuilder.make(from: sources)
    }

    var body: some View {
        ZStack {
            footprintBackground
                .task(id: show.id) { markFootprintRecommendationHandled() }
            if isDeleting {
                ProgressView()
                    .tint(BSColor.Stage.foreground)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: BSSpacing.lg) {
                    hero
                    FootprintDynamicCoverSection(
                        show: show,
                        isPlaybackActive: isDynamicCoverPlaybackActive
                    )
                    dispersalRitualSection
                    FootprintListeningMemorySection(show: show)
                    memorySection
                    keepsakesSection
                    if show.companionStatus == .confirmed {
                        companionSection
                    }
                    informationSection
                    if !show.artists.isEmpty {
                        lineupSection
                    }
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
                .bsNavigationScrollEdge()
            }
        }
        .navigationTitle(BSLocalization.text("足迹详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !isDeleting {
                ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(BSLocalization.text("编辑现场"), systemImage: "square.and.pencil") {
                        isShowingEditor = true
                    }
                    if shareRoute != .none {
                        Button(BSLocalization.text("分享现场"), systemImage: "square.and.arrow.up") {
                            openShare()
                        }
                    }
                    Button(BSLocalization.text("删除现场"), systemImage: "trash", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                    .accessibilityLabel(BSLocalization.text("更多操作"))
                }
            }
        }
        .fullScreenCover(item: $memoryTarget) { target in
            MemoryFragmentReviewView(
                showID: show.id,
                fragment: target.fragment,
                initialIndex: target.initialIndex
            )
        }
        .sheet(item: $showingAssetKind) { kind in
            ShowAssetSheet(
                showID: show.id,
                showName: show.name,
                kind: kind,
                onDetailVisibilityChange: onDetailVisibilityChange,
                keepsParentDetailHidden: true
            )
        }
        .sheet(isPresented: $isShowingMemoryPage) {
            MemoryFragmentsSheet(show: show)
        }
        .sheet(isPresented: $isShowingEditor) {
            ShowDraftEditorView(
                title: BSLocalization.text("编辑现场"),
                draft: ShowDraft(show: show),
                saveTitle: BSLocalization.text("保存"),
                statusPillText: session.phase(for: show, now: Date()).statusText,
                isPostponed: show.changeStatus == .postponed
            ) { draft in
                try await apply(draft)
            }
        }
        .fullScreenCover(isPresented: $isShowingShareComposer) {
            FootprintShareComposerView(
                show: show,
                identity: identity,
                materials: shareMaterials,
                onClose: { isShowingShareComposer = false }
            )
        }
        .sheet(isPresented: $isShowingDispersalShare) {
            DispersalCeremonyShareSheet(
                show: show,
                identity: identity,
                rating: show.rating,
                note: show.closingNote ?? "",
                onSaved: { presentToast(.success, message: BSLocalization.text("足迹图片已保存")) }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(26)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingCeremonyEditor) {
            DispersalCeremonySheet(
                show: show,
                identity: identity,
                initialStep: .combined,
                headerTitle: BSLocalization.text("散场评价"),
                onCommit: { rating, note in
                    try await commitCeremonyData(rating: rating, note: note)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(BSColor.Stage.background)
            .preferredColorScheme(.dark)
        }
        .alert(
            DangerConfirmation.deleteShow.title,
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button(DangerConfirmation.deleteShow.confirmTitle, role: .destructive) {
                beginDelete()
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.deleteShow.message)
        }
        .bsToastOverlay(toast, bottomPadding: BSLayout.tabBarContentInset)
        .onAppear { onDetailVisibilityChange(true) }
        .onDisappear { onDetailVisibilityChange(false) }
        .preferredColorScheme(.dark)
    }

    private var footprintBackground: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            RadialGradient(
                colors: [FootprintDetailTokens.backgroundGlow, .clear],
                center: .topTrailing,
                startRadius: .zero,
                endRadius: FootprintDetailTokens.backgroundGlowRadius
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [FootprintDetailTokens.backgroundAccent, .clear],
                center: .bottomLeading,
                startRadius: .zero,
                endRadius: FootprintDetailTokens.backgroundAccentRadius
            )
            .ignoresSafeArea()
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: BSSpacing.md) {
            FootprintCoverView(show: show, cover: detailCover, showsMetadata: false)
                .frame(
                    width: FootprintDetailTokens.heroCoverWidth,
                    height: FootprintDetailTokens.heroCoverHeight
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(heroEyebrow)
                    .font(FootprintDetailTokens.eyebrowFont)
                    .tracking(1.4)
                    .foregroundColor(BSColor.Stage.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(show.name)
                    .font(BSFont.V3.title2)
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(3)
                    .minimumScaleFactor(0.88)
                    .padding(.top, BSSpacing.sm)

                Text(FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? BSLocalization.text("未填写场馆"))
                    .font(BSFont.V3.small)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(2)
                    .padding(.top, BSSpacing.sm)

                Spacer(minLength: BSSpacing.sm)

                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                    Text(heroArchiveContext)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .font(FootprintDetailTokens.identityDetailFont.weight(.semibold))
                .foregroundColor(BSColor.Stage.accent.opacity(0.88))
            }
            .frame(
                maxWidth: .infinity,
                minHeight: FootprintDetailTokens.heroCoverHeight,
                alignment: .topLeading
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.md)
        .background(
            LinearGradient(
                colors: [BSColor.Stage.surfaceRaised, FootprintDetailTokens.heroSecondarySurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: FootprintDetailTokens.heroCornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FootprintDetailTokens.heroCornerRadius)
                .stroke(FootprintDetailTokens.heroBorder)
        )
    }

    private var heroEyebrow: String {
        let calendar = show.timingCalendar()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_Hans_CN")
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "yyyy.MM.dd"
        let date = dateFormatter.string(from: show.effectiveDate)
        return [date, FootprintTextNormalizer.nonEmptyTrimmed(show.city)?.uppercased()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var heroArchiveContext: String {
        var values = [BSLocalization.format("第 %lld 场现场", identity.showOrdinal)]
        if let cityOrdinal = identity.cityOrdinal,
           let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city) {
            values.append("\(city) · \(BSLocalization.format("第 %lld 场", cityOrdinal))")
        }
        return values.joined(separator: "  ·  ")
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            Button {
                isShowingMemoryPage = true
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(BSLocalization.text("记忆碎片"))
                        .font(FootprintDetailTokens.sectionFont)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: BSSpacing.xs) {
                        Text(BSLocalization.format("%lld 条", fragments.count))
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.dim)
                        Image(systemName: "chevron.right")
                            .font(BSFont.V3.caption.weight(.semibold))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if fragments.isEmpty {
                Button {
                    isShowingMemoryPage = true
                } label: {
                    VStack(spacing: BSSpacing.compact) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(BSFont.title.weight(.light))
                            .foregroundColor(BSColor.Stage.dim)
                        Text(BSLocalization.text("这一晚还没有留下记忆碎片"))
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: FootprintDetailTokens.emptyMemoryHeight)
                    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: BSSpacing.sm), GridItem(.flexible())],
                    spacing: BSSpacing.sm
                ) {
                    ForEach(Array(fragments.enumerated()), id: \.element.id) { index, fragment in
                        Button {
                            memoryTarget = FootprintMemoryTarget(fragment: fragment, initialIndex: 0)
                        } label: {
                            FootprintMemoryTile(fragment: fragment)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            FootprintAccessibilityPolicy.memoryLabel(
                                ordinal: index + 1,
                                kind: fragment.orderedMediaItems.first.map { $0.kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片") } ?? BSLocalization.text("文字"),
                                recordedAt: fragment.createdAt,
                                text: fragment.text
                            )
                        )
                    }
                }
            }
        }
    }

    private var keepsakesSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader(BSLocalization.text("留下的东西"))
            HStack(spacing: BSSpacing.sm) {
                ForEach(ShowAssetKind.allCases) { kind in
                    Button {
                        showingAssetKind = kind
                    } label: {
                        FootprintKeepsakeTile(kind: kind, asset: asset(for: kind))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.format("管理%@，%@", kind.title, asset(for: kind) == nil ? BSLocalization.text("未添加") : BSLocalization.text("已保存")))
                }
            }
        }
    }

    /// 散场评价区。固定展示，支持直接添加、编辑与卡片分享。
    private var dispersalRitualSection: some View {
        let node = show.rating.flatMap(DispersalRating.from(rawValue:))
        let note = FootprintTextNormalizer.nonEmptyTrimmed(show.closingNote)
        let hasContent = node != nil || note != nil

        return VStack(alignment: .leading, spacing: BSSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("散场评价"))
                    .font(FootprintDetailTokens.sectionFont)
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                if hasContent {
                    Menu {
                        Button {
                            isShowingCeremonyEditor = true
                        } label: {
                            Label(BSLocalization.text("编辑评价"), systemImage: "pencil")
                        }
                        Button {
                            isShowingDispersalShare = true
                        } label: {
                            Label(BSLocalization.text("分享卡片"), systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            Task { await clearCeremonyData() }
                        } label: {
                            Label(BSLocalization.text("清除评价"), systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(BSLocalization.text("编辑"))
                                .font(BSFont.V3.caption.weight(.medium))
                            Image(systemName: "ellipsis")
                                .font(BSFont.V3.caption)
                        }
                        .foregroundColor(BSColor.Stage.dim)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("管理散场评价"))
                }
            }

            if hasContent {
                dispersalContentCard(node: node, note: note)
            } else {
                dispersalEmptyCard
            }
        }
    }

    private func dispersalContentCard(node: DispersalRating?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            if let node {
                HStack(alignment: .center, spacing: BSSpacing.compact) {
                    Text(node.emoji)
                        .font(.system(size: 28))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.label)
                            .font(BSFont.headline.weight(.bold))
                            .foregroundColor(node.tint)
                        Text(node.sub)
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.muted)
                    }

                    Spacer()

                    Button {
                        isShowingDispersalShare = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text(BSLocalization.text("分享"))
                        }
                        .font(BSFont.V3.caption.weight(.medium))
                        .foregroundColor(BSColor.Stage.dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    Label(BSLocalization.text("散场感想"), systemImage: "quote.bubble.fill")
                        .font(BSFont.V3.caption.weight(.semibold))
                        .foregroundColor(BSColor.Stage.muted)
                    Spacer()
                    Button {
                        isShowingDispersalShare = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text(BSLocalization.text("分享"))
                        }
                        .font(BSFont.V3.caption.weight(.medium))
                        .foregroundColor(BSColor.Stage.dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let note {
                if node != nil {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.vertical, 2)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("“")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor((node?.tint ?? BSColor.Stage.accent).opacity(0.5))
                        .offset(y: -4)

                    Text(note)
                        .font(.custom("Songti SC", size: 14, relativeTo: .body))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(BSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Stage.surface,
                    node?.tint.opacity(0.06) ?? FootprintDetailTokens.heroSecondarySurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    node?.tint.opacity(0.24) ?? BSColor.Stage.border,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            isShowingCeremonyEditor = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                node.map(\.accessibilityLabel),
                note
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
        .accessibilityHint(BSLocalization.text("轻点编辑散场评价"))
    }

    private var dispersalEmptyCard: some View {
        Button {
            isShowingCeremonyEditor = true
        } label: {
            HStack(spacing: BSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(BSColor.Stage.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(BSLocalization.text("添加散场评价"))
                        .font(BSFont.body.weight(.medium))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(BSLocalization.text("记录这一场的评分与散场感受"))
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .padding(BSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(BSColor.Stage.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("添加散场评价，记录这一场的评分与散场感受"))
    }

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader(BSLocalization.text("同行"))
            VStack(spacing: 8) {
                ForEach(Array(companionRows.enumerated()), id: \.offset) { _, row in
                    companionRow(name: row.name, count: row.count)
                }
            }
        }
    }

    private func companionRow(name: String, count: Int) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FootprintDetailTokens.companionAccent, FootprintDetailTokens.companionGlow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: FootprintDetailTokens.avatarSize, height: FootprintDetailTokens.avatarSize)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.format("共同留下 %lld 场足迹", count))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
            }
            Spacer()
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private var companionRows: [(name: String, count: Int)] {
        let names = CompanionNameList.normalized(show.companionNames)
        if names.isEmpty {
            return [(BSLocalization.text("同行者"), 1)]
        }
        return names.map { name in
            (name, pairwiseCount(for: name))
        }
    }

    private func pairwiseCount(for name: String) -> Int {
        max(1, archive.shows.filter {
            $0.companionStatus == .confirmed
                && $0.endedAt != nil
                && CompanionNameList.normalized($0.companionNames).contains(name)
        }.count)
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader(BSLocalization.text("现场资料"))
            VStack(spacing: 0) {
                infoRow(icon: "calendar", title: BSLocalization.text("时间"), value: formatter.dateText(for: show))
                if let durationText {
                    Divider().overlay(BSColor.Stage.border)
                    infoRow(icon: "timer", title: BSLocalization.text("时长"), value: durationText)
                }
                Divider().overlay(BSColor.Stage.border)
                infoRow(
                    icon: "mappin.and.ellipse",
                    title: BSLocalization.text("场馆"),
                    value: FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? BSLocalization.text("未填写场馆")
                )
                Divider().overlay(BSColor.Stage.border)
                infoRow(
                    icon: "building.2",
                    title: BSLocalization.text("城市"),
                    value: FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? BSLocalization.text("未填写城市")
                )
                if show.artists.isEmpty {
                    Divider().overlay(BSColor.Stage.border)
                    infoRow(
                        icon: "music.note",
                        title: BSLocalization.text("艺人"),
                        value: BSLocalization.text("未填写艺人")
                    )
                }
            }
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
        }
    }

    /// 阵容区:与现场详情同一形态(`ArtistLineupStrip`),点头像跳 Apple Music。
    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader(BSLocalization.text("阵容"))
            ArtistLineupStrip(artists: show.artists)
        }
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: icon)
                .font(FootprintDetailTokens.iconFont)
                .foregroundColor(BSColor.Stage.muted)
                .frame(width: FootprintDetailTokens.infoIconSize, height: FootprintDetailTokens.infoIconSize)
                .background(FootprintDetailTokens.infoIconFill, in: RoundedRectangle(cornerRadius: BSRadius.sm))
            Text(title)
                .font(BSFont.V3.caption)
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: FootprintDetailTokens.infoTitleWidth, alignment: .leading)
            Text(value)
                .font(BSFont.V3.small.weight(.medium))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BSSpacing.compact)
        .frame(minHeight: FootprintDetailTokens.infoRowHeight)
        .accessibilityElement(children: .combine)
    }

    private func openShare() {
        switch shareRoute {
        case .composer:
            isShowingShareComposer = true
        case .dispersalCard:
            isShowingDispersalShare = true
        case .none:
            break
        }
    }

    @MainActor
    private func apply(_ draft: ShowDraft) async throws {
        let didSync = try await ShowMutationCoordinator.applyDraft(
            draft,
            to: show,
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
        presentToast(
            didSync ? .success : .neutral,
            message: didSync ? BSLocalization.text("现场信息已更新") : BSLocalization.text("信息已保存，同步暂未更新")
        )
    }

    @MainActor
    private func commitCeremonyData(rating: Int?, note: String?) async throws {
        let didSync = try await ShowMutationCoordinator.commitClosingRitual(
            rating: rating,
            note: note,
            show: show,
            shows: shows,
            selections: selections,
            notificationStates: notificationStates,
            in: modelContext,
            session: session
        )
        presentToast(
            didSync ? .success : .neutral,
            message: didSync ? BSLocalization.text("散场评价已更新") : BSLocalization.text("信息已保存，同步暂未更新")
        )
    }

    @MainActor
    private func clearCeremonyData() async {
        do {
            let didSync = try await ShowMutationCoordinator.commitClosingRitual(
                rating: nil,
                note: nil,
                show: show,
                shows: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                session: session
            )
            presentToast(
                didSync ? .success : .neutral,
                message: didSync ? BSLocalization.text("散场评价已清除") : BSLocalization.text("评价已清除，同步暂未更新")
            )
        } catch {
            modelContext.rollback()
            presentToast(.failure, message: BSLocalization.text("清除失败，请重试"))
        }
    }

    private func beginDelete() {
        guard !isDeleting else { return }
        memoryTarget = nil
        showingAssetKind = nil
        isShowingShareComposer = false
        isShowingDispersalShare = false
        isShowingCeremonyEditor = false
        isShowingEditor = false
        isShowingMemoryPage = false
        isDeleting = true
        Task { @MainActor in
            await Task.yield()
            await deleteShow()
        }
    }

    @MainActor
    private func deleteShow() async {
        do {
            _ = try await ShowDeletionCoordinator.delete(
                show,
                from: shows,
                selections: selections,
                notificationStates: notificationStates,
                in: modelContext,
                onRecordDeleted: {
                    isDeleting = true
                }
            )
            dismiss()
        } catch {
            modelContext.rollback()
            isDeleting = false
            presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(FootprintDetailTokens.sectionFont)
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
    }

    private func asset(for kind: ShowAssetKind) -> ShowAsset? {
        assets.first { $0.kind == kind }
    }

}
