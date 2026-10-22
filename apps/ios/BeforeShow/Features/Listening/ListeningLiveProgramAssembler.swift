import Foundation

extension ListeningCompilationAssembler {
    /// Timetable: 想看 per day first, then one disc per day and stage. Single-artist show: one 彩排 disc, using the estimated end when none is set.
    @MainActor static func livePrograms(
        for show: Show,
        topTracks: (String) -> [ListeningDiscTrack]
    ) -> [ListeningCompilationAssembler.LiveProgram] {
        typealias Program = ListeningCompilationAssembler.LiveProgram
        func liveSet(_ performance: TimetablePerformance) -> ListeningCompilationAssembler.LiveSet? {
            performance.appleMusicArtistID.map {
                .init(tracks: topTracks($0), duration: performance.endsAt.timeIntervalSince(performance.startsAt))
            }
        }
        if let timetable = show.timetable {
            let days = timetable.orderedDays
            var programs = days.enumerated().map { index, day in
                let wanted = day.performances.filter(\.isInterested)
                    .sorted(by: TimetablePerformance.chronologicalOrder)
                    .compactMap { performance in
                        performance.appleMusicArtistID.map { (tracks: topTracks($0), startsAt: performance.startsAt, endsAt: performance.endsAt) }
                    }
                return Program(
                    key: "wanted-\(day.id)",
                    title: days.count == 1 ? ListeningCopy.text("想看") : ListeningCopy.format("想看 · Day %d", index + 1),
                    sets: ListeningCompilationAssembler.route(wanted)
                )
            }
            let stageCount = days.reduce(0) { $0 + $1.orderedStages.count }
            for (index, day) in days.enumerated() {
                for stage in day.orderedStages {
                    let title = stageCount == 1 ? ListeningCopy.text("彩排")
                        : days.count == 1 ? stage.name
                        : ListeningCopy.format("Day %d · %@", index + 1, stage.name)
                    programs.append(Program(key: "stage-\(stage.id)", title: title, sets: stage.orderedPerformances.compactMap(liveSet)))
                }
            }
            return programs
        }
        guard show.artists.count == 1, let artistID = show.artists.first?.appleMusicArtistID else { return [] }
        let timeState = CurrentShowTimeState(show: show, calendar: show.timingCalendar(), now: .distantPast)
        let start = timeState.effectiveStartTime
            ?? CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar())
        guard let end = timeState.effectiveEndTime ?? timeState.endBoundary, end > start else { return [] }
        return [Program(key: "rehearsal", title: ListeningCopy.text("彩排"), sets: [.init(tracks: topTracks(artistID), duration: end.timeIntervalSince(start))])]
    }

}
