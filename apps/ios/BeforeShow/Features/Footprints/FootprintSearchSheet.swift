import SwiftUI

// MARK: - Footprint Search Filter

enum FootprintSearchFilter: Hashable, Identifiable {
    case all
    case year(Int)
    case city(String)

    var id: String {
        switch self {
        case .all: return "all"
        case let .year(year): return "year:\(year)"
        case let .city(city): return "city:\(city)"
        }
    }

    var label: String {
        switch self {
        case .all: return BSLocalization.text("全部")
        case let .year(year): return String(year)
        case let .city(city): return city
        }
    }
}

// MARK: - Footprint Search Matcher

enum FootprintSearchMatcher {
    static func filterChips(for archive: FootprintArchiveSnapshot) -> [FootprintSearchFilter] {
        var values: [FootprintSearchFilter] = [.all]
        values += archive.years.prefix(2).map { .year($0.year) }
        values += archive.cities.prefix(2).map { .city($0.name) }
        return values
    }

    static func matches(show: Show, query: String, filter: FootprintSearchFilter) -> Bool {
        let year = show.timingCalendar().component(.year, from: show.effectiveDate)
        let searchable = ([show.name] + show.artistNames
            + [show.city, show.venueName, String(year)]
                .compactMap { $0 })
            .joined(separator: " ")
        let matchesQuery = ArtistNameMatching.contains(searchable, query: query)
        let matchesFilter: Bool
        switch filter {
        case .all:
            matchesFilter = true
        case let .year(selected):
            matchesFilter = year == selected
        case let .city(city):
            matchesFilter = show.city?.trimmingCharacters(in: .whitespacesAndNewlines) == city
        }
        return matchesQuery && matchesFilter
    }

    static func filterShows(_ shows: [Show], query: String, filter: FootprintSearchFilter) -> [Show] {
        shows.filter { matches(show: $0, query: query, filter: filter) }
    }

    static func subtitle(for show: Show) -> String {
        let location = [show.city, show.venueName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let day = footprintDayText(show.effectiveDate, calendar: show.timingCalendar())
        if location.isEmpty {
            return day
        }
        return "\(location) · \(day)"
    }
}

// MARK: - Footprint Search Sheet

struct FootprintSearchSheet: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: FootprintSearchFilter = .all
    @FocusState private var isSearchFocused: Bool

    private var chips: [FootprintSearchFilter] {
        FootprintSearchMatcher.filterChips(for: archive)
    }

    private var results: [Show] {
        FootprintSearchMatcher.filterShows(archive.shows, query: query, filter: filter)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BSColor.Stage.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !archive.shows.isEmpty {
                        chipFilterBar
                    }
                    contentView
                }
            }
            .navigationTitle(BSLocalization.text("搜索足迹"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭")) {
                    dismiss()
                }
            }
            .searchable(
                text: $query,
                prompt: Text(BSLocalization.text("搜索足迹"))
            )
            .bsSearchFocused($isSearchFocused)
            .onAppear { isSearchFocused = true }
            // 结果 push 进足迹详情，返回时保留关键词（系统搜索模式）。
            .navigationDestination(for: Show.self) { show in
                FootprintDetailView(show: show, archive: archive)
            }
        }
        .tint(BSColor.Stage.foreground)
    }

    @ViewBuilder
    private var contentView: some View {
        if archive.shows.isEmpty {
            emptyArchiveView
        } else if results.isEmpty {
            emptyResultsView
        } else {
            resultsListView
        }
    }

    private var chipFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(chips) { chip in
                    Button {
                        filter = chip
                    } label: {
                        Text(chip.label)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(filter == chip ? BSColor.Stage.accent : BSColor.Stage.muted)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                filter == chip ? BSColor.Stage.accent.opacity(0.07) : Color.white.opacity(0.03),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    filter == chip ? BSColor.Stage.accent.opacity(0.28) : BSColor.Stage.border,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { show in
                    NavigationLink(value: show) {
                        HStack(spacing: 10) {
                            FootprintResolvedCoverImage(show: show, cover: covers[show.id])
                                .frame(width: 40, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 9))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(show.name)
                                    .font(BSFont.caption)
                                    .foregroundStyle(BSColor.Stage.foreground)
                                    .lineLimit(1)
                                Text(FootprintSearchMatcher.subtitle(for: show))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(BSColor.Stage.muted)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("footprint.search.result")

                    Divider()
                        .overlay(BSColor.Stage.border)
                        .padding(.leading, 66)
                }
            }
            .padding(.top, 4)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var emptyResultsView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(BSColor.Stage.dim)
                Text(BSLocalization.text("未找到匹配的现场"))
                    .font(BSFont.body)
                    .foregroundStyle(BSColor.Stage.muted)
                Text(BSLocalization.text("尝试更换关键词或年份、城市筛选"))
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var emptyArchiveView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(BSColor.Stage.dim)
            Text(BSLocalization.text("这里会长出你的足迹"))
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.muted)
            Text(BSLocalization.text("补进第一场看过的现场，\n场次、城市和回忆都会慢慢累积。"))
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
