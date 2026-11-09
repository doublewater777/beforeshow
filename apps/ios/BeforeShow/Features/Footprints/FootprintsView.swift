import SwiftData
import SwiftUI

// MARK: - Footprints Root Presentation

struct FootprintsView: View {
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var isAddingShow = false
    @State private var detailTarget: FootprintDetailDestination?
    @State private var activeSheet: FootprintSheet?
    private let currentShowSession = CurrentShowSession()

    var body: some View {
        let archive = FootprintArchiveBuilder.make(shows: shows)
        let covers = FootprintCoverResolver.resolve(
            shows: archive.shows,
            fragments: fragments,
            assets: assets
        )
        let prepared = PreparedFootprint(archive: archive, covers: covers)
        let currentShow = currentShowSession.selectCurrentShow(from: shows, manualSelection: selections.first)
        return Group {
            if archive.shows.isEmpty, currentShow == nil {
                FootprintDemoView(onAdd: { isAddingShow = true })
            } else {
                NavigationStack {
                    timelineContent(prepared, currentShow: currentShow)
                }
            }
        }
        .sheet(isPresented: $isAddingShow) {
            AddShowCoordinatorSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
        }
    }

    private func timelineContent(
        _ prepared: PreparedFootprint,
        currentShow: Show?
    ) -> some View {
        let archive = prepared.archive
        let covers = prepared.covers
        return Group {
            if archive.shows.isEmpty {
                FootprintEmptyView(
                    content: FootprintEmptyStateCopy.content(hasCurrentShow: currentShow != nil),
                    currentShow: currentShow,
                    onAdd: { isAddingShow = true }
                )
                .bsAdaptiveContentWidth()
            } else {
                content(prepared)
            }
        }
        .background { FootprintBackground().ignoresSafeArea() }
        .bsRootBottomChrome()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailTarget) { target in
                FootprintDetailView(
                    show: target.show,
                    archive: archive
                )
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .search:
                    FootprintSearchSheet(archive: archive, covers: covers)
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                }
            }
    }

    private func content(_ prepared: PreparedFootprint) -> some View {
        return FootprintDashboardView(
            archive: prepared.archive,
            covers: prepared.covers,
            allShows: shows,
            onShowSelected: { detailTarget = FootprintDetailDestination(show: $0) },
            onAdd: { isAddingShow = true },
            onSearch: { activeSheet = .search }
        )
    }

}

private enum FootprintSheet: String, Identifiable {
    case search
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

struct FootprintEmptyView: View {
    let content: FootprintEmptyStateCopy.Content
    let currentShow: Show?
    let onAdd: () -> Void

    var body: some View {
        BSRootEmptyState(
            iconSystemName: "flag",
            title: content.title,
            message: content.message,
            actionTitle: content.actionTitle ?? BSLocalization.text("添加现场"),
            action: onAdd
        ) {
            if let currentShow {
                FootprintFirstUnlockPreview(show: currentShow)
            }
        }
        .overlay(alignment: .top) {
            Text(BSLocalization.text("足迹"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, BSLayout.pageHeaderTopPadding)
        }
    }
}
