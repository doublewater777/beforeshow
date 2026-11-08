import Foundation

/// 「今天这张」: the widget's disc while nothing is seated. One per show and local day, drawn from
/// the 「帮我挑一张」 pool; a listening reminder for that day wins. It keeps its own memory, so the
/// pick feed's draws, the rack's daily heads and the reminder queue never move.
enum ListeningTodayDiscPolicy {
    private struct Memory: Codable {
        var days: [String: String]
    }

    private static let keyPrefix = "listening.todayDisc."

    static func clearSelections(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    static func disc(
        showID: UUID,
        candidates: [ListeningDisc],
        heardSongIDs: Set<String>,
        reminderDiscID: String?,
        on date: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> ListeningDisc? {
        var seen = Set<String>()
        let pool = candidates.filter { !$0.tracks.isEmpty && seen.insert($0.id).inserted }
        guard !pool.isEmpty else { return nil }

        let key = keyPrefix + showID.uuidString
        let day = dayKey(date, calendar: calendar)
        var memory = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Memory.self, from: $0) } ?? Memory(days: [:])

        let chosen: ListeningDisc
        if let id = reminderDiscID, let reminded = pool.first(where: { $0.id == id }) {
            chosen = reminded
        } else if let id = memory.days[day], let kept = pool.first(where: { $0.id == id }) {
            return kept
        } else {
            let previous = memory.days[dayKey(date, offset: -1, calendar: calendar)]
            let fresh = pool.filter { !Set($0.tracks.map(\.id)).isSubset(of: heardSongIDs) }
            var options = fresh.isEmpty ? pool : fresh
            if options.count > 1 { options.removeAll { $0.id == previous } }
            guard let drawn = options.min(by: { hash("\(showID)|\(day)|\($0.id)") < hash("\(showID)|\(day)|\($1.id)") })
            else { return nil }
            chosen = drawn
        }

        if memory.days[day] != chosen.id {
            memory.days[day] = chosen.id
            let kept = Set((-1...1).map { dayKey(date, offset: $0, calendar: calendar) })
            memory.days = memory.days.filter { kept.contains($0.key) }
            if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: key) }
        }
        return chosen
    }

    private static func dayKey(_ date: Date, offset: Int = 0, calendar: Calendar) -> String {
        let shifted = calendar.date(byAdding: .day, value: offset, to: date) ?? date
        return ListeningDailyFeaturedDiscPolicy.dayKey(for: shifted, calendar: calendar)
    }

    /// FNV-1a: unlike Hasher, stable across launches.
    private static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
