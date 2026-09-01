import Foundation

struct FootprintVisibility: Equatable {
    let showCount: Int
    let yearCount: Int
    let artistCount: Int
    let cityCount: Int
    let venueCount: Int
    let hasRevisitedVenue: Bool

    var isSeed: Bool { showCount == 1 }
    var showsTrend: Bool { showCount >= 1 }
    var showsYearComparison: Bool { yearCount >= 2 }
    var showsTopThree: Bool { showCount >= 3 }
}

@MainActor
extension FootprintArchiveSnapshot {
    var visibility: FootprintVisibility {
        FootprintVisibility(
            showCount: shows.count,
            yearCount: years.count,
            artistCount: artistArchiveItems.count,
            cityCount: cityArchiveItems.count,
            venueCount: venueArchiveItems.count,
            hasRevisitedVenue: venueArchiveItems.contains(where: \.isRevisited)
        )
    }
}
