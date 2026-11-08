import Foundation
import SwiftData
import SwiftUI
import UIKit

/// What the hero cover opens: the cover image itself, or the memory video it came from.
private enum FootprintCoverViewer: Identifiable {
    case showCover(String)
    case image(BSFullscreenImageSource)

    var id: String {
        switch self {
        case .showCover(let url): "cover:\(url)"
        case .image(.cover(let url)), .image(.file(let url)): "image:\(url.absoluteString)"
        case .image(.image): "image"
        }
    }
}

private struct FootprintMemoryTarget: Identifiable {
    let id: UUID
}

struct FootprintDetailView: View {
    let show: Show
    let archive: FootprintArchiveSnapshot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
    @State private var isShowingCompanionEditor = false
    @State private var isShowingMemoryPage = false
    @State private var memoryCreate: MemoryCreateSourceOption?
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var toast: BSToastPayload?
    @State private var coverViewer: FootprintCoverViewer?
    @Namespace private var coverTransition

    private let formatter = ShowDisplayFormatter()
    private let session = CurrentShowSession()

    init(
        show: Show,
        archive: FootprintArchiveSnapshot
    ) {
        self.show = show
        self.archive = archive
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
        GeometryReader { proxy in
            content(topInset: proxy.safeAreaInsets.top)
        }
    }

    @ViewBuilder
    private func content(topInset: CGFloat) -> some View {
        ZStack {
            footprintBackground
                .task(id: show.id) { markFootprintRecommendationHandled() }
            if isDeleting {
                ProgressView()
                    .tint(BSColor.Stage.foreground)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: BSSpacing.lg) {
                    FootprintStageHero(
                        show: show,
                        cover: detailCover,
                        archive: archive,
                        identity: identity,
                        canOpenCover: hasViewableCover,
                        coverTransition: coverTransition,
                        onOpenCover: openCover,
                            topExtension: topInset
                    )
                    FootprintDispersalRitualSection(
                        rating: show.rating,
                        note: show.closingNote,
                        onEdit: { isShowingCeremonyEditor = true },
                        onShare: { isShowingDispersalShare = true },
                        onClear: { Task { await clearCeremonyData() } }
                    )
                    FootprintListeningMemorySection(show: show)
                    MemoryContactSheet(
                        fragments: fragments,
                        currentPhase: .after,
                        fragmentLabel: { fragment, ordinal in
                            FootprintAccessibilityPolicy.memoryLabel(
                                ordinal: ordinal,
                                kind: fragment.orderedMediaItems.first.map { $0.kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片") } ?? BSLocalization.text("文字"),
                                recordedAt: fragment.createdAt,
                                text: fragment.text
                            )
                        },
                        onOpen: openMemoryFragment,
                        onOpenList: {
                            memoryCreate = nil
                            isShowingMemoryPage = true
                        },
                        onCreate: { option in
                            memoryCreate = option
                            isShowingMemoryPage = true
                        }
                    )
                    FootprintKeepsakeShelf(
                        show: show,
                        entries: ShowAssetManagementPolicy.entries(for: show, assets: assets),
                        assetFor: asset(for:),
                        onSelect: { showingAssetKind = $0 }
                    )
                    FootprintCompanionSection(show: show, archive: archive) {
                        isShowingCompanionEditor = true
                    }
                    BSProgrammeInfo(rows: infoRows)
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
                .bsStageNavigationChrome()
            }
        }
        // The stage carries the page; the bar keeps only its buttons. The title still names the page for Back.
        .navigationTitle(BSLocalization.text("足迹详情"))
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
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
        .fullScreenCover(item: $coverViewer) { viewer in
            Group {
                switch viewer {
                case .showCover(let urlString):
                    ShowCoverFullscreenPreview(urlString: urlString)
                case .image(let source):
                    FootprintCoverImageViewer(source: source)
                }
            }
            .bsNavigationZoom(sourceID: "cover", in: coverTransition)
        }
        .fullScreenCover(item: $memoryTarget) { target in
            MemoryMomentViewer(show: show, startID: target.id)
        }
        .sheet(item: $showingAssetKind) { kind in
            ShowAssetSheet(
                showID: show.id,
                showName: show.name,
                kind: kind
            )
        }
        .sheet(isPresented: $isShowingMemoryPage) {
            MemoryFragmentsSheet(show: show, pendingCreate: memoryCreate)
        }
        .sheet(isPresented: $isShowingCompanionEditor) {
            CompanionEditorSheet(show: show)
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
                note: show.closingNote ?? ""
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(BSColor.Stage.background)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingCeremonyEditor) {
            DispersalCeremonySheet(
                show: show,
                identity: identity,
                initialStep: .combined,
                headerTitle: BSLocalization.text("散场评价"),
                presentsShareAfterCommit: false,
                onCommit: { rating, note, _ in
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
        .bsToastOverlay(toast, bottomPadding: BSSpacing.md)
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

    private var hasViewableCover: Bool {
        guard let detailCover else { return false }
        return detailCover.source != .archive
    }

    /// Show covers and tickets open fullscreen; a memory cover opens its original photo,
    /// or plays the video it was taken from.
    private func openCover() {
        guard let detailCover else { return }
        switch (detailCover.badge, detailCover.source) {
        case (_, .archive):
            return
        case (.memory, _):
            guard let item = FootprintCoverResolver.coverMemoryItem(in: fragments) else { return }
            if item.kind == .video {
                memoryTarget = FootprintMemoryTarget(id: item.id)
            } else {
                let url = MemoryMediaLocation.applicationSupport().url(for: item.relativePath)
                coverViewer = .image(.file(url))
            }
        case (.archive, .remote(let url)), (.archive, .local(let url)):
            coverViewer = .showCover(url.absoluteString)
        case (.keepsake, .remote(let url)):
            coverViewer = .image(.cover(url))
        case (.keepsake, .local(let url)):
            coverViewer = .image(.file(url))
        }
    }

    private var infoRows: [BSProgrammeInfo.Row] {
        var rows = [BSProgrammeInfo.Row(label: BSLocalization.text("时间"), value: formatter.dateText(for: show))]
        if let durationText {
            rows.append(.init(label: BSLocalization.text("时长"), value: durationText))
        }
        rows.append(.init(label: BSLocalization.text("场馆"), value: FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? BSLocalization.text("未填写场馆")))
        if let address = FootprintTextNormalizer.nonEmptyTrimmed(show.venueAddress) {
            rows.append(.init(label: BSLocalization.text("地址"), value: address))
        }
        rows.append(.init(label: BSLocalization.text("城市"), value: FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? BSLocalization.text("未填写城市")))
        if show.artists.isEmpty {
            rows.append(.init(label: BSLocalization.text("艺人"), value: BSLocalization.text("未填写艺人")))
        }
        return rows
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

    private func openMemoryFragment(_ fragment: MemoryFragment) {
        memoryTarget = FootprintMemoryTarget(id: fragment.orderedMediaItems.first?.id ?? fragment.id)
    }

    private func beginDelete() {
        guard !isDeleting else { return }
        memoryTarget = nil
        coverViewer = nil
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

    private func asset(for kind: ShowAssetKind) -> ShowAsset? {
        assets.first { $0.kind == kind }
    }

}

/// A single cover image (ticket or memory photo), fullscreen and zoomable.
private struct FootprintCoverImageViewer: View {
    let source: BSFullscreenImageSource

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        BSFullscreenImageViewer(pageCount: 1, currentIndex: $page) { _ in
            BSZoomableImagePage(source: source, onSingleTap: { dismiss() }).bsMaskUserContent()
        }
    }
}
