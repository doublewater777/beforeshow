import Foundation

/// One thing kept from the night: a photo, a video or a line of text.
/// Old fragments that grouped several items show each item as its own moment.
struct MemoryMoment: Identifiable {
    let fragment: MemoryFragment
    let item: MemoryMediaItem?

    var id: UUID { item?.id ?? fragment.id }
    var date: Date { fragment.createdAt }
    var isText: Bool { item == nil }
    /// The line written for this moment; a legacy group's caption sits on its first item only.
    var caption: String? {
        guard let text = fragment.text else { return nil }
        guard let item else { return text }
        return fragment.orderedMediaItems.first?.id == item.id ? text : nil
    }
}

struct MemoryMomentSection: Identifiable {
    let phase: MemoryFragmentPhase
    let moments: [MemoryMoment]
    var id: MemoryFragmentPhase { phase }
}

enum MemoryMomentTimeline {
    /// The count every memory surface shows, so the unit never changes between pages.
    static func countText(_ count: Int) -> String {
        BSLocalization.format("%lld 段", count)
    }

    /// Oldest first, the order the night happened.
    static func moments(from fragments: [MemoryFragment]) -> [MemoryMoment] {
        fragments
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
            .flatMap { fragment -> [MemoryMoment] in
                let items = fragment.orderedMediaItems
                guard !items.isEmpty else { return [MemoryMoment(fragment: fragment, item: nil)] }
                return items.map { MemoryMoment(fragment: fragment, item: $0) }
            }
    }

    static func sections(_ moments: [MemoryMoment], timing: ShowTimingFields) -> [MemoryMomentSection] {
        let grouped = Dictionary(grouping: moments) { MemoryFragmentPhase.resolved(at: $0.date, timing: timing) }
        return [MemoryFragmentPhase.before, .live, .after].map { phase in
            MemoryMomentSection(phase: phase, moments: grouped[phase] ?? [])
        }
    }

    /// How many moments fall in each equal slice of the evening, first to last.
    static func density(_ moments: [MemoryMoment], buckets: Int) -> [Int] {
        guard buckets > 0, let first = moments.first?.date, let last = moments.last?.date else { return [] }
        var counts = Array(repeating: 0, count: buckets)
        let span = last.timeIntervalSince(first)
        for moment in moments {
            let offset = span > 0 ? moment.date.timeIntervalSince(first) / span : 0
            counts[min(buckets - 1, Int(offset * Double(buckets)))] += 1
        }
        return counts
    }
}
