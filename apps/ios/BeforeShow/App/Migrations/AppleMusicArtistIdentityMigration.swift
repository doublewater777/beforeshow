import Foundation
import SwiftData

@MainActor
enum AppleMusicArtistIdentityMigration {
    static func migrateIfNeeded(in modelContext: ModelContext) {
        guard let shows = try? modelContext.fetch(FetchDescriptor<Show>()) else { return }
        var didChange = false

        for show in shows {
            var artists = show.artists
            var showChanged = false
            for index in artists.indices where artists[index].appleMusicArtistID == nil {
                guard let artistID = AppleMusicArtistIdentity.artistID(
                    from: artists[index].appleMusicURL
                ) else {
                    continue
                }
                artists[index].appleMusicArtistID = artistID
                showChanged = true
            }
            if showChanged {
                show.artists = artists
                didChange = true
            }
        }

        if didChange {
            try? modelContext.save()
        }
    }

    static func artistID(from rawURL: String) -> String? {
        AppleMusicArtistIdentity.artistID(from: rawURL)
    }
}
