import Foundation
import SwiftData

/// Who an artist tap is about, from any surface: a show's lineup, a timetable set, the listening room.
struct ArtistReference: Identifiable, Hashable {
    let name: String
    let appleMusicArtistID: String?
    let avatarURL: URL?
    let appleMusicURL: URL?

    var id: String { appleMusicArtistID ?? "name:\(name)" }

    init(name: String, appleMusicArtistID: String?, avatarURL: URL? = nil, appleMusicURL: URL? = nil) {
        self.name = name
        self.appleMusicArtistID = appleMusicArtistID
        self.avatarURL = avatarURL
        self.appleMusicURL = appleMusicURL
    }

    init(browseArtist artist: ListeningBrowseArtist, show: Show?) {
        let slot = show?.artists.indices.contains(artist.slotIndex) == true ? show?.artists[artist.slotIndex] : nil
        self.init(
            name: artist.name,
            appleMusicArtistID: artist.appleMusicArtistID,
            avatarURL: artist.artworkURL,
            appleMusicURL: slot?.appleMusicURL.flatMap(URL.init(string:))
        )
    }

    @MainActor init(slot: ArtistSlot) {
        self.init(
            name: slot.name,
            appleMusicArtistID: slot.appleMusicArtistID,
            avatarURL: ArtistAvatarResolver.shared.displayURL(for: slot),
            appleMusicURL: slot.appleMusicURL.flatMap(URL.init(string:))
        )
    }
}

/// Loads one artist's releases from the shared catalog cache, independent of which show is current.
@MainActor
@Observable
final class ArtistProfileModel {
    enum Status: Equatable { case loading, ready, unmatched, needsAccess, failed }

    let reference: ArtistReference
    private(set) var status: Status = .loading
    private(set) var releases: [ListeningDisc] = []
    private(set) var playlists: [ListeningDisc] = []
    private(set) var artworkURL: URL?
    private(set) var genres: [String] = []

    @ObservationIgnored private let service: any ListeningMusicCatalogServicing
    @ObservationIgnored private var store: ListeningCatalogStore?
    @ObservationIgnored private var projection: ListeningCatalogProjection?

    init(reference: ArtistReference, service: any ListeningMusicCatalogServicing = MusicKitListeningCatalogService()) {
        self.reference = reference
        self.service = service
        artworkURL = reference.avatarURL
    }

    func load(in context: ModelContext) async {
        guard let artistID = reference.appleMusicArtistID else {
            status = .unmatched
            return
        }
        guard service.currentAuthorizationStatus() == .authorized else {
            status = .needsAccess
            return
        }
        let store = store ?? ListeningCatalogStore(modelContext: context, service: service)
        let projection = projection ?? ListeningCatalogProjection(context: context, catalogStore: store)
        self.store = store
        self.projection = projection
        if releases.isEmpty && playlists.isEmpty { status = .loading }
        do {
            _ = try await store.loadArtistCatalog(artistID: artistID)
            try projection.refresh(artistIDs: [artistID])
            guard let artist = projection.artists[artistID] else {
                status = .failed
                return
            }
            applyArtistPresentation(artist)
            status = .ready

            do {
                let playlistPayload = try await service.fetchFeaturedPlaylists(artistID: artistID, fetchedAt: Date())
                if !playlistPayload.playlists.isEmpty {
                    let persisted = try await store.persistFeaturedPlaylists(playlistPayload)
                    if persisted {
                        try projection.refresh(artistIDs: [artistID])
                        if let updatedArtist = projection.artists[artistID] {
                            applyArtistPresentation(updatedArtist)
                        }
                    }
                }
            } catch {
                // Browse-only failures never fail the profile view.
            }
        } catch {
            if releases.isEmpty && playlists.isEmpty { status = .failed }
        }
    }

    private func applyArtistPresentation(_ artist: ListeningArtistPresentation) {
        releases = ListeningArtistReleases.newestFirst(artist.albums)
        playlists = artist.albums.filter {
            if case .featuredPlaylist = $0.origin { return true }
            return false
        }
        artworkURL = reference.avatarURL ?? artist.artworkURL
        genres = artist.genres
    }

    func requestAccess(in context: ModelContext) async {
        _ = await service.requestAuthorization()
        await load(in: context)
    }
}
