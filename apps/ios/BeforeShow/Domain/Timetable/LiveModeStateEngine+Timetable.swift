import Foundation

extension LiveModeStateEngine {
    /// Adapts SwiftData Timetable into pure LiveDayInput models for the App target.
    static func buildInputs(from timetable: Timetable) -> [LiveDayInput] {
        timetable.orderedDays.map { day in
            let perfs = day.stages.flatMap { stage in
                stage.performances.map { p in
                    LivePerformanceInput(
                        id: p.id,
                        artistName: p.artistName,
                        stageID: stage.id,
                        stageName: stage.name,
                        startsAt: p.startsAt,
                        endsAt: p.endsAt,
                        isInterested: p.isInterested
                    )
                }
            }
            return LiveDayInput(
                id: day.id,
                date: day.date,
                performances: perfs
            )
        }
    }
}
