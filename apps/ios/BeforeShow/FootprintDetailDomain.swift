import Foundation

struct FootprintCompanionIdentity: Equatable {
    let name: String
    let ordinal: Int
}

struct FootprintDetailIdentity: Equatable {
    let showOrdinal: Int
    let cityOrdinal: Int?
    let companions: [FootprintCompanionIdentity]

    var companionName: String? {
        if companions.count == 1 { return companions[0].name }
        return CompanionNameList.joined(companions.map(\.name))
    }

    var companionOrdinal: Int? {
        companions.count == 1 ? companions[0].ordinal : nil
    }
}

@MainActor
enum FootprintDetailIdentityBuilder {
    static func make(
        show: Show,
        archive: FootprintArchiveSnapshot,
        calendar: Calendar = .current
    ) -> FootprintDetailIdentity {
        let orderedShows = archive.shows.sorted {
            compare($0, $1, calendar: calendar)
        }
        let showOrdinal = orderedShows.firstIndex { $0.id == show.id }.map { $0 + 1 } ?? 1

        let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city)
        let cityShows = city.map { city in
            orderedShows.filter { FootprintTextNormalizer.nonEmptyTrimmed($0.city) == city }
        } ?? []
        let cityOrdinal = cityShows.firstIndex { $0.id == show.id }.map { $0 + 1 }

        let companions = CompanionNameList.normalized(show.companionNames).compactMap { name -> FootprintCompanionIdentity? in
            let companionShows = orderedShows.filter {
                $0.companionStatus == .confirmed
                    && $0.endedAt != nil
                    && CompanionNameList.normalized($0.companionNames).contains(name)
            }
            guard let index = companionShows.firstIndex(where: { $0.id == show.id }) else {
                return nil
            }
            return FootprintCompanionIdentity(name: name, ordinal: index + 1)
        }

        return FootprintDetailIdentity(
            showOrdinal: showOrdinal,
            cityOrdinal: cityOrdinal,
            companions: companions
        )
    }

    private static func compare(_ lhs: Show, _ rhs: Show, calendar: Calendar) -> Bool {
        let lhsStart = effectiveStart(for: lhs, calendar: calendar)
        let rhsStart = effectiveStart(for: rhs, calendar: calendar)
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func effectiveStart(for show: Show, calendar: Calendar) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        let time = calendar.dateComponents([.hour, .minute, .second], from: show.startTime)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components) ?? show.effectiveDate
    }

}

enum FootprintTextNormalizer {
    static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum FootprintAccessibilityPolicy {
    static func memoryLabel(
        ordinal: Int,
        kind: String,
        recordedAt: Date,
        text: String? = nil
    ) -> String {
        let kindAndTime = BSLocalization.format("第 %lld 条，%@，%@", ordinal, kind, timeText(recordedAt))
        if let summary = summary(from: text) {
            return BSLocalization.format("打开记忆碎片，%@，内容：%@", kindAndTime, summary)
        }
        return BSLocalization.format("打开记忆碎片，%@", kindAndTime)
    }

    static func shareMaterialLabel(
        title: String,
        ordinal: Int,
        recordedAt: Date,
        isSelected: Bool
    ) -> String {
        let selection = isSelected ? BSLocalization.text("已选择") : BSLocalization.text("未选择")
        return BSLocalization.format("%@，第 %lld 项，%@，%@", title, ordinal, timeText(recordedAt), selection)
    }

    private static func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static func summary(from text: String?) -> String? {
        guard let text = FootprintTextNormalizer.nonEmptyTrimmed(text) else { return nil }
        let summary = String(text.prefix(24))
        return summary.count < text.count ? "\(summary)…" : summary
    }
}

enum FootprintShareMaterialKind: Equatable {
    case photo
    case videoCover
    case ticket
    case timetable
}

struct FootprintShareCandidate: Identifiable, Equatable {
    let id: UUID
    let kind: FootprintShareMaterialKind
    let recordedAt: Date
}

enum FootprintShareSelectionPolicy {
    static let maximumSelectionCount = 3

    static func defaultSelection(from candidates: [FootprintShareCandidate]) -> [UUID] {
        let photos = chronological(candidates.filter { $0.kind == .photo })
        let videos = chronological(candidates.filter { $0.kind == .videoCover })
        return (photos + videos).prefix(maximumSelectionCount).map(\.id)
    }

    static func selectionByAdding(_ id: UUID, to selected: Set<UUID>) -> Set<UUID>? {
        if selected.contains(id) { return selected }
        guard selected.count < maximumSelectionCount else { return nil }
        var next = selected
        next.insert(id)
        return next
    }

    static func outputOrder(
        selected: Set<UUID>,
        from candidates: [FootprintShareCandidate]
    ) -> [UUID] {
        let included = candidates.filter { selected.contains($0.id) }
        let memories = chronological(included.filter {
            $0.kind == .photo || $0.kind == .videoCover
        })
        let ticket = chronological(included.filter { $0.kind == .ticket })
        let timetable = chronological(included.filter { $0.kind == .timetable })
        return (memories + ticket + timetable).map(\.id)
    }

    private static func chronological(_ candidates: [FootprintShareCandidate]) -> [FootprintShareCandidate] {
        candidates.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

struct FootprintShareMaterial: Identifiable, Equatable {
    let candidate: FootprintShareCandidate
    let title: String
    let imageURL: URL

    var id: UUID { candidate.id }
    var kind: FootprintShareMaterialKind { candidate.kind }
}

enum FootprintShareSourceKind: Equatable {
    case text
    case photo
    case videoCover
    case ticket
    case timetable
}

struct FootprintShareSource: Identifiable, Equatable {
    let id: UUID
    let kind: FootprintShareSourceKind
    let recordedAt: Date
    let imageURL: URL?
}

enum FootprintShareMaterialBuilder {
    static func make(from sources: [FootprintShareSource]) -> [FootprintShareMaterial] {
        sources.compactMap { source in
            guard let mapping = mapping(for: source.kind),
                  let imageURL = source.imageURL else { return nil }
            return FootprintShareMaterial(
                candidate: FootprintShareCandidate(
                    id: source.id,
                    kind: mapping.kind,
                    recordedAt: source.recordedAt
                ),
                title: mapping.title,
                imageURL: imageURL
            )
        }
    }

    private static func mapping(
        for kind: FootprintShareSourceKind
    ) -> (kind: FootprintShareMaterialKind, title: String)? {
        switch kind {
        case .text:
            return nil
        case .photo:
            return (.photo, BSLocalization.text("照片"))
        case .videoCover:
            return (.videoCover, BSLocalization.text("视频封面"))
        case .ticket:
            return (.ticket, BSLocalization.text("票根"))
        case .timetable:
            return (.timetable, BSLocalization.text("时刻表"))
        }
    }
}

enum FootprintExportContentPolicy {
    static let timelineShowLimit = 12
    static let memoryCardLimit = 4
    static let yearShowLimit = 12
    static let memoriesPageLimit = 12

    enum RemainingStyle {
        case shows
        case memories
    }

    static func prefix<T>(_ items: [T], limit: Int) -> [T] {
        Array(items.prefix(limit))
    }

    static func remainingCount(total: Int, limit: Int) -> Int {
        max(0, total - limit)
    }

    static func remainingText(total: Int, limit: Int, style: RemainingStyle) -> String? {
        let remaining = remainingCount(total: total, limit: limit)
        guard remaining > 0 else { return nil }
        switch style {
        case .shows:
            return BSLocalization.format("还有 %lld 场现场", Int64(remaining))
        case .memories:
            return BSLocalization.format("还有 %lld 个画面", Int64(remaining))
        }
    }

    static func cappedYearGroups(_ years: [FootprintYearGroup], limit: Int) -> [FootprintYearGroup] {
        var remaining = limit
        var result: [FootprintYearGroup] = []
        for group in years {
            guard remaining > 0 else { break }
            let shows = Array(group.shows.prefix(remaining))
            remaining -= shows.count
            result.append(FootprintYearGroup(year: group.year, shows: shows))
        }
        return result
    }
}

enum FootprintDetailShareRoute: Equatable {
    case composer
    case dispersalCard
    case none

    static func resolve(hasShareMaterials: Bool, rating: Int?, note: String?) -> Self {
        if hasShareMaterials { return .composer }
        if rating != nil { return .dispersalCard }
        if FootprintTextNormalizer.nonEmptyTrimmed(note) != nil { return .dispersalCard }
        return .none
    }
}

enum FootprintMemoryShareCopy {
    static func identities(from identity: FootprintDetailIdentity) -> [String] {
        var result = [BSLocalization.format("第 %lld 场现场", identity.showOrdinal)]
        if identity.companions.count == 1, let companion = identity.companions.first {
            result.append(BSLocalization.format("与%@第 %lld 次见面", companion.name, companion.ordinal))
        } else if let names = CompanionNameList.joined(identity.companions.map(\.name)) {
            result.append(BSLocalization.format("与%@同行", names))
        } else if let cityOrdinal = identity.cityOrdinal {
            result.append(BSLocalization.format("城市第 %lld 场", cityOrdinal))
        }
        return Array(result.prefix(2))
    }
}
