import SwiftUI

// MARK: - Footprint Search

struct FootprintSearchSheet: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onSelect: (Show) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: FootprintSearchFilter = .all

    private var chips: [FootprintSearchFilter] {
        var values: [FootprintSearchFilter] = [.all]
        values += archive.years.prefix(2).map { .year($0.year) }
        values += archive.cities.prefix(2).map { .city($0.name) }
        return values
    }

    private var results: [Show] {
        archive.shows.filter { show in
            let searchable = ([show.name] + show.artistNames
                + [show.city, show.venueName, String(show.timingCalendar().component(.year, from: show.effectiveDate))]
                    .compactMap { $0 })
                .joined(separator: " ")
            let matchesQuery = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case let .year(year):
                matchesFilter = show.timingCalendar().component(.year, from: show.effectiveDate) == year
            case let .city(city):
                matchesFilter = show.city?.trimmingCharacters(in: .whitespacesAndNewlines) == city
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BSLocalization.text("搜索与筛选")).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("从历史记录中快速找到某位艺人、城市、场馆或年份。"))
                .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).padding(.top, 6)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(BSColor.Stage.muted)
                TextField(BSLocalization.text("搜索足迹"), text: $query).foregroundColor(BSColor.Stage.foreground)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
            .padding(.top, 15)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip.label) { filter = chip }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(filter == chip ? BSColor.Stage.accent : BSColor.Stage.muted)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(filter == chip ? BSColor.Stage.accent.opacity(0.07) : Color.white.opacity(0.03), in: Capsule())
                            .overlay(Capsule().stroke(filter == chip ? BSColor.Stage.accent.opacity(0.28) : BSColor.Stage.border))
                    }
                }
            }
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { show in
                        Button { onSelect(show) } label: {
                            HStack(spacing: 10) {
                                FootprintMiniPoster(show: show, cover: covers[show.id]).frame(width: 40, height: 52).clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(show.name).font(BSFont.caption).foregroundColor(BSColor.Stage.foreground).lineLimit(1)
                                    Text("\([show.city, show.venueName].compactMap { $0 }.joined(separator: " · ")) · \(footprintDayText(show.effectiveDate, calendar: show.timingCalendar()))")
                                        .font(.system(size: 11.5)).foregroundColor(BSColor.Stage.muted).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(BSColor.Stage.border)
                    }
                    if results.isEmpty {
                        Text(BSLocalization.text("没有找到匹配的现场")).font(BSFont.body).foregroundColor(BSColor.Stage.muted).padding(.top, 28)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .padding(.top, 8)

            Button(BSLocalization.text("完成")) { dismiss() }
                .font(BSFont.caption).foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity).frame(height: 45)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 33).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BSColor.Stage.background.ignoresSafeArea())
    }
}

private enum FootprintSearchFilter: Hashable {
    case all
    case year(Int)
    case city(String)

    var label: String {
        switch self {
        case .all: return BSLocalization.text("全部")
        case let .year(year): return String(year)
        case let .city(city): return city
        }
    }
}
