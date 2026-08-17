import Foundation

struct FootprintDetailIdentity: Equatable {
    let showOrdinal: Int
    let cityOrdinal: Int?
    let companionName: String?
    let companionOrdinal: Int?
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

        let companionName = FootprintTextNormalizer.nonEmptyTrimmed(show.companionName)
        let companionShows = companionName.map { companionName in
            orderedShows.filter {
                $0.companionStatus == .confirmed
                    && $0.endedAt != nil
                    && FootprintTextNormalizer.nonEmptyTrimmed($0.companionName) == companionName
            }
        } ?? []
        let companionOrdinal = companionShows.firstIndex { $0.id == show.id }.map { $0 + 1 }

        return FootprintDetailIdentity(
            showOrdinal: showOrdinal,
            cityOrdinal: cityOrdinal,
            companionName: companionOrdinal == nil ? nil : companionName,
            companionOrdinal: companionOrdinal
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
