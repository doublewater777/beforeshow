import SwiftData
import SwiftUI

// MARK: - Footprints Root Presentation

struct FootprintsView: View {
    var onArchiveVisibilityChange: (Bool) -> Void = { _ in }
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var isAddingShow = false
    @State private var detailTarget: FootprintDetailDestination?
    @State private var activeSheet: FootprintSheet?
    @State private var toast: BSToastPayload?
    private let currentShowSession = CurrentShowSession()

    var body: some View {
        let archive = FootprintArchiveBuilder.make(shows: shows)
        let covers = FootprintCoverResolver.resolve(
            shows: archive.shows,
            fragments: fragments,
            assets: assets
        )
        let prepared = PreparedFootprint(archive: archive, covers: covers)
        return NavigationStack {
            timelineContent(
                prepared,
                hasCurrentShow: currentShowSession.selectCurrentShow(
                    from: shows,
                    manualSelection: selections.first
                ) != nil
            )
        }
    }

    private func timelineContent(
        _ prepared: PreparedFootprint,
        hasCurrentShow: Bool
    ) -> some View {
        let archive = prepared.archive
        let covers = prepared.covers
        return Group {
            if archive.shows.isEmpty {
                FootprintEmptyView(
                    content: FootprintEmptyStateCopy.content(hasCurrentShow: hasCurrentShow),
                    onAdd: { isAddingShow = true }
                )
            } else {
                content(prepared)
            }
        }
        .background { FootprintBackground().ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailTarget) { target in
                FootprintDetailView(
                    show: target.show,
                    archive: archive,
                    onDetailVisibilityChange: onArchiveVisibilityChange
                )
            }
            .sheet(isPresented: $isAddingShow) {
                AddShowCoordinatorSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .search:
                    FootprintSearchSheet(archive: archive, covers: covers) { show in
                        activeSheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            detailTarget = .init(show: show)
                        }
                    }
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                case .share:
                    FootprintShareSheet(
                        archive: archive,
                        covers: covers,
                        onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) }
                    )
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                }
            }
            .bsToastOverlay(toast, bottomPadding: 100)
    }

    private func content(_ prepared: PreparedFootprint) -> some View {
        return FootprintDashboardView(
            archive: prepared.archive,
            covers: prepared.covers,
            onShowSelected: { detailTarget = FootprintDetailDestination(show: $0) },
            onAdd: { isAddingShow = true },
            onSearch: { activeSheet = .search },
            onShare: {
                activeSheet = .share
            },
            onArchiveVisibilityChange: onArchiveVisibilityChange
        )
    }

    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

}

private enum FootprintSheet: String, Identifiable {
    case search
    case share
    var id: String { rawValue }
}

struct FootprintBackground: View {
    var body: some View {
        ZStack {
            BSColor.Stage.background
            RadialGradient(colors: [BSColor.Stage.glowBlue.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 330)
            RadialGradient(colors: [BSColor.Stage.accent.opacity(0.09), .clear], center: .topTrailing, startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct FootprintEmptyView: View {
    let content: FootprintEmptyStateCopy.Content
    let onAdd: () -> Void

    var body: some View {
        BSRootEmptyState(
            iconSystemName: "flag",
            title: content.title,
            message: content.message,
            actionTitle: content.actionTitle ?? BSLocalization.text("添加现场"),
            action: onAdd
        )
        .overlay(alignment: .top) {
            Text(BSLocalization.text("足迹"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, BSLayout.pageHeaderTopPadding)
        }
    }
}
