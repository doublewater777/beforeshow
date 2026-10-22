import Foundation

/// Cached, event-scoped inputs. No catalog access or durable scheduling history.
struct ListeningReminderRoster: Equatable {
    struct Disc: Equatable {
        let id: String
        let title: String
    }
    struct Artist: Equatable {
        let id: String
        let name: String
        var isConnected = true
        var albums: [Disc] = []
        var featuredPlaylist: Disc?
    }
    var artists: [Artist] = []
    var isMultiArtist = false
    var singalong: Disc?
    var latest: Disc?
    var deepCuts: Disc?
    var wanted: Disc?
    var rehearsal: Disc?
    var completedDiscIDs: Set<String> = []
    var lastListenedAt: Date?

    static func uncached(artists: [ArtistSlot]) -> Self {
        Self(artists: artists.enumerated().map {
            Artist(id: $0.element.appleMusicArtistID ?? "unconnected-\($0.offset)",
                   name: $0.element.name, isConnected: $0.element.appleMusicArtistID != nil)
        }, isMultiArtist: artists.count > 1)
    }
}
