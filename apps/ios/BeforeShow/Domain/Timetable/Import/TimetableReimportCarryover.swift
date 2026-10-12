import Foundation

/// Carries personal choices from the saved timetable onto a re-imported one.
/// Only a set that matches exactly one saved set by date, stage, artist and
/// start keeps its "想看" mark and artist link; anything ambiguous starts fresh.
enum TimetableReimportCarryover {
    private struct Key: Hashable {
        let date: Date
        let stage: String
        let artist: String
        let startsAt: Date
    }

    static func apply(from previous: TimetableDraft, to draft: inout TimetableDraft) {
        let previousByKey = Dictionary(grouping: performances(in: previous), by: \.key)
        let currentCounts = Dictionary(grouping: performances(in: draft), by: \.key).mapValues(\.count)

        for day in draft.days.indices {
            for stage in draft.days[day].stages.indices {
                for index in draft.days[day].stages[stage].performances.indices {
                    let current = draft.days[day].stages[stage].performances[index]
                    let key = key(date: draft.days[day].date, stage: draft.days[day].stages[stage].name, performance: current)
                    guard currentCounts[key] == 1, let matches = previousByKey[key], matches.count == 1 else { continue }
                    let old = matches[0].performance
                    draft.days[day].stages[stage].performances[index].isInterested = old.isInterested
                    draft.days[day].stages[stage].performances[index].inheritArtistLink(from: old)
                }
            }
        }
    }

    private static func performances(in draft: TimetableDraft) -> [(key: Key, performance: TimetableDraftPerformance)] {
        draft.days.flatMap { day in
            day.stages.flatMap { stage in
                stage.performances.map { (key(date: day.date, stage: stage.name, performance: $0), $0) }
            }
        }
    }

    private static func key(date: Date, stage: String, performance: TimetableDraftPerformance) -> Key {
        Key(
            date: date,
            stage: stage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            artist: ArtistNameMatching.normalized(performance.artistName),
            startsAt: performance.startsAt
        )
    }
}
