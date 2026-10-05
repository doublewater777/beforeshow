import Foundation

struct TimetableClashInfo: Equatable, Hashable, Sendable, Identifiable {
    var id: String { "\(performanceID.uuidString)-\(conflictingPerformanceID.uuidString)" }
    let performanceID: UUID
    let artistName: String
    let stageName: String
    let startsAt: Date
    let endsAt: Date
    let conflictingPerformanceID: UUID
    let conflictingArtistName: String
    let conflictingStageName: String
    let conflictingStartsAt: Date
    let conflictingEndsAt: Date

    var overlapInterval: DateInterval? {
        let start = max(startsAt, conflictingStartsAt)
        let end = min(endsAt, conflictingEndsAt)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }
}

enum TimetableClashPolicy {
    /// Identifies all pairs of interested performances that overlap in time.
    /// Non-interested performances never produce clashes. Adjacency (where one ends exactly
    /// when the next begins) is explicitly not a conflict.
    static func detectClashes(
        performances: [TimetablePerformanceTiming],
        interestedIDs: Set<UUID>,
        artistNames: [UUID: String] = [:],
        stageNames: [UUID: String] = [:]
    ) -> [TimetableClashInfo] {
        let interestedTimings = performances.filter { interestedIDs.contains($0.id) }
        guard interestedTimings.count >= 2 else { return [] }

        var clashes: [TimetableClashInfo] = []
        let count = interestedTimings.count

        for i in 0..<count {
            for j in (i + 1)..<count {
                let first = interestedTimings[i]
                let second = interestedTimings[j]

                if TimetableTimePolicy.overlaps(first, second) {
                    let firstArtist = artistNames[first.id] ?? ""
                    let secondArtist = artistNames[second.id] ?? ""
                    let firstStage = stageNames[first.stageID] ?? ""
                    let secondStage = stageNames[second.stageID] ?? ""

                    clashes.append(TimetableClashInfo(
                        performanceID: first.id,
                        artistName: firstArtist,
                        stageName: firstStage,
                        startsAt: first.startsAt,
                        endsAt: first.endsAt,
                        conflictingPerformanceID: second.id,
                        conflictingArtistName: secondArtist,
                        conflictingStageName: secondStage,
                        conflictingStartsAt: second.startsAt,
                        conflictingEndsAt: second.endsAt
                    ))
                }
            }
        }
        return clashes
    }

    /// Map from performance ID to the list of performances that clash with it.
    static func clashMap(
        from clashes: [TimetableClashInfo]
    ) -> [UUID: [TimetableClashInfo]] {
        var map: [UUID: [TimetableClashInfo]] = [:]
        for clash in clashes {
            // Include bidirectional mapping
            map[clash.performanceID, default: []].append(clash)

            // Inverse entry
            let inverse = TimetableClashInfo(
                performanceID: clash.conflictingPerformanceID,
                artistName: clash.conflictingArtistName,
                stageName: clash.conflictingStageName,
                startsAt: clash.conflictingStartsAt,
                endsAt: clash.conflictingEndsAt,
                conflictingPerformanceID: clash.performanceID,
                conflictingArtistName: clash.artistName,
                conflictingStageName: clash.stageName,
                conflictingStartsAt: clash.startsAt,
                conflictingEndsAt: clash.endsAt
            )
            map[clash.conflictingPerformanceID, default: []].append(inverse)
        }
        return map
    }
}
