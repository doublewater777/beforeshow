import SwiftUI

/// The Footprints entrance: a marquee, one door per room, then every poster.
struct FootprintDashboardView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let allShows: [Show]
    let onShowSelected: (Show) -> Void
    let onAdd: () -> Void
    let onSearch: () -> Void
    let onShare: () -> Void

    var body: some View {
        let marquee = FootprintStagePolicy.marquee(archived: archive.shows, allShows: allShows)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                NavigationLink {
                    FootprintBackstagePassView(archive: archive, covers: covers)
                } label: {
                    FootprintMarqueeView(status: marquee)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 18)

                FootprintEntryTiles(archive: archive, covers: covers, allShows: allShows)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                posterWallHeader
                ForEach(archive.years) { group in
                    FootprintPosterWallYear(group: group, covers: covers, onShowSelected: onShowSelected)
                }
            }
            .bsAdaptiveContentWidth()
            .padding(.bottom, BSLayout.tabBarContentInset)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack {
            Text(BSLocalization.text("足迹"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                headerIcon("plus", label: BSLocalization.text("添加现场"), action: onAdd)
                headerIcon("magnifyingglass", label: BSLocalization.text("搜索足迹"), action: onSearch)
                headerIcon("square.and.arrow.up", label: BSLocalization.text("分享足迹"), action: onShare)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, BSLayout.pageHeaderTopPadding)
    }

    private func headerIcon(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var posterWallHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(BSLocalization.text("全部现场"))
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Spacer(minLength: 0)
            Text(BSLocalization.format("%lld 场", archive.shows.count))
                .font(.system(size: 13))
                .foregroundStyle(BSColor.Stage.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
    }
}

/// One year of posters with its month strip; posters open the show.
private struct FootprintPosterWallYear: View {
    let group: FootprintYearGroup
    let covers: [UUID: FootprintCover]
    let onShowSelected: (Show) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        let months = Set(group.shows.map { $0.timingCalendar().component(.month, from: $0.effectiveDate) })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(group.year))
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .foregroundStyle(BSColor.Stage.heroIvory)
                    Text(BSLocalization.format("%lld 场", group.shows.count))
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.Stage.muted)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    ForEach(1...12, id: \.self) { month in
                        Circle()
                            .fill(months.contains(month) ? BSColor.Stage.accent : Color.white.opacity(0.10))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(group.shows) { show in
                    Button { onShowSelected(show) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            FootprintCoverView(show: show, cover: covers[show.id], showsMetadata: false)
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .shadow(color: .black.opacity(0.5), radius: 10, y: 8)
                            HStack {
                                Text(footprintDayText(show.effectiveDate, calendar: show.timingCalendar()))
                                Spacer(minLength: 4)
                                Text(FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? "")
                                    .lineLimit(1)
                            }
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(BSColor.Stage.muted)
                        }
                    }
                    .buttonStyle(BSPressStyle())
                    .accessibilityLabel(show.name)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }
}
