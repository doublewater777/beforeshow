import Foundation

// MARK: - Footprint Archive Domain

enum FootprintCategory: String, CaseIterable, Identifiable {
    case overview = "总览"
    case artist = "艺人"
    case city = "城市"
    case venue = "场馆"

    var id: String { rawValue }

    /// 展示用本地化标题(rawValue 是稳定标识,不直接上屏)。
    var title: String { BSLocalization.text(rawValue) }
}

struct FootprintRankItem: Identifiable, Equatable, Hashable {
    /// 默认用 name;同名不同实体的排行项(如不同城市的同名场馆)必须显式传 id。
    let id: String
    let name: String
    let count: Int

    init(name: String, count: Int, id: String? = nil) {
        self.id = id ?? name
        self.name = name
        self.count = count
    }
}

struct FootprintYearGroup: Identifiable {
    let year: Int
    let shows: [Show]
    var id: Int { year }
}

struct PreparedFootprint {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
}

struct FootprintArchiveSnapshot {
    let shows: [Show]
    let artists: [FootprintRankItem]
    let cities: [FootprintRankItem]
    let venues: [FootprintRankItem]
    let years: [FootprintYearGroup]
    let currentYearCount: Int
    /// 全部归档现场的观看时长合计(分钟),动态计算不持久化。
    let totalDurationMinutes: Int

    var firstShow: Show? { shows.last }

    func ranking(for category: FootprintCategory) -> [FootprintRankItem] {
        switch category {
        case .overview: return []
        case .artist: return artists
        case .city: return cities
        case .venue: return venues
        }
    }
}

enum FootprintEmptyStateCopy {
    struct Content: Equatable {
        let title: String
        let message: String
        let actionTitle: String?
    }

    static func content(hasCurrentShow: Bool) -> Content {
        if hasCurrentShow {
            return Content(
                title: BSLocalization.text("这场结束后，会来到足迹"),
                message: BSLocalization.text("当前现场散场后会自动收进这里，\n场次、城市和回忆都会慢慢累积。"),
                actionTitle: BSLocalization.text("添加现场")
            )
        }

        return Content(
            title: BSLocalization.text("这里会长出你的足迹"),
            message: BSLocalization.text("补进第一场看过的现场，\n场次、城市和回忆都会慢慢累积。"),
            actionTitle: BSLocalization.text("添加现场")
        )
    }
}

struct FootprintDetailDestination: Identifiable, Hashable {
    let show: Show

    var id: UUID { show.id }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum FootprintArchiveBuilder {
    static func make(
        shows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FootprintArchiveSnapshot {
        let archived = shows
            .filter {
                guard $0.changeStatus != .canceled else { return false }
                let kind = CurrentShowTimeState(show: $0, calendar: calendar, now: now).kind
                return kind == .postShow || kind == .ended
            }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        let grouped = Dictionary(grouping: archived) {
            $0.timingCalendar(fallback: calendar).component(.year, from: $0.effectiveDate)
        }
        let totalDurationMinutes = archived.reduce(0) { partial, show in
            let timeState = CurrentShowTimeState(show: show, calendar: calendar, now: now)
            guard let minutes = ShowDurationFormatter.minutes(for: show, timeState: timeState) else { return partial }
            return partial + minutes
        }

        return FootprintArchiveSnapshot(
            shows: archived,
            artists: FootprintArchiveRankingBuilder.artists(in: archived).map(\.rankItem),
            cities: rank(archived.compactMap { normalized($0.city) }),
            venues: FootprintArchiveRankingBuilder.venues(in: archived).map(\.rankItem),
            years: grouped.keys.sorted(by: >).map {
                FootprintYearGroup(year: $0, shows: grouped[$0] ?? [])
            },
            currentYearCount: grouped[calendar.component(.year, from: now)]?.count ?? 0,
            totalDurationMinutes: totalDurationMinutes
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rank(_ values: [String]) -> [FootprintRankItem] {
        Dictionary(grouping: values, by: { $0 })
            .map { FootprintRankItem(name: $0.key, count: $0.value.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.count > $1.count
            }
    }
}
