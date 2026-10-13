import Foundation

/// Value comparison includes nested timetable edits, which do not touch Show.updatedAt.
struct ListeningShowInputs: Equatable {
    struct ArtistIdentity: Equatable {
        let name: String
        let artistID: String?
        let url: String?
        init(_ slot: ArtistSlot) {
            name = slot.name
            artistID = slot.appleMusicArtistID
            url = slot.appleMusicURL
        }
    }
    struct Stage: Equatable {
        struct Set: Equatable {
            let id: UUID
            let name: String
            let artistID: String?
            let start: Date
            let end: Date
            let interested: Bool
        }
        let dayID: UUID
        let dayDate: Date
        let id: UUID
        let name: String
        let sets: [Set]
    }
    let showID: UUID
    let artists: [ArtistSlot]
    let start: Date
    let end: Date?
    let stages: [Stage]

    init(_ show: Show) {
        showID = show.id
        artists = show.artists
        let time = CurrentShowTimeState(show: show, calendar: show.timingCalendar(), now: .distantPast)
        start = time.effectiveStartTime
            ?? CurrentShowTimeState.effectiveStartTime(for: show, calendar: show.timingCalendar())
        end = time.effectiveEndTime ?? time.endBoundary
        stages = (show.timetable?.orderedDays ?? []).flatMap { day in
            day.orderedStages.map { stage in
                Stage(dayID: day.id, dayDate: day.date, id: stage.id, name: stage.name,
                      sets: stage.orderedPerformances.map {
                    Stage.Set(id: $0.id, name: $0.artistName, artistID: $0.appleMusicArtistID,
                              start: $0.startsAt, end: $0.endsAt, interested: $0.isInterested)
                })
            }
        }
    }
}
