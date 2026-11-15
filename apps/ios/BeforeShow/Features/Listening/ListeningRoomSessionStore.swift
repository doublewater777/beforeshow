import Foundation

/// Single registry for the live Listening room and whether root chrome may bind to it.
///
/// `room` is the coordinator Listen can adopt. `chromeRoom` is published only after
/// cold-start hydration (or once the Listen room appears), so compact playback never
/// binds a not-yet-hydrated transport.
@MainActor
@Observable
final class ListeningRoomSessionStore {
    static let shared = ListeningRoomSessionStore()

    struct ArtistMatchRequest: Equatable {
        let showID: UUID
        let slotIndex: Int
        var resumePlaybackOnSuccess = false
    }

    private(set) var room: ListeningRoomCoordinator?
    private(set) var isChromePublished = false
    private(set) var pendingArtistMatchRequest: ArtistMatchRequest?
    /// The root mini player can send Listen back to either surface or open the full player.
    var surface: ListeningSurface = .listen
    var isNowPlayingPresented = false

    /// Cold start waits for hydration; a record the user plays in this session shows at once.
    var chromeRoom: ListeningRoomCoordinator? {
        guard let room else { return nil }
        let isUserLoaded = room.accessResolved && room.hasLoadedDisc
        return isChromePublished || isUserLoaded ? room : nil
    }

    private init() {}

    func adopt(_ room: ListeningRoomCoordinator?) {
        if room == nil {
            self.room?.releaseShow()
            self.room = nil
            isChromePublished = false
            clearPendingArtistMatchRequest()
            return
        }
        if self.room !== room {
            isChromePublished = false
        }
        self.room = room
    }

    func publishChrome(_ room: ListeningRoomCoordinator) {
        self.room = room
        isChromePublished = true
    }

    func unpublishChrome() {
        isChromePublished = false
    }

    func discardLocalState() {
        room?.discardLoadedDiscState()
        room?.releaseShow()
        room = nil
        isChromePublished = false
        clearPendingArtistMatchRequest()
    }

    func clear(stoppingTransport: Bool) {
        let current = room
        let published = chromeRoom
        if stoppingTransport {
            current?.stop()
        }
        current?.releaseShow()
        if let published, published !== current {
            if stoppingTransport {
                published.stop()
            }
            published.releaseShow()
        }
        room = nil
        isChromePublished = false
        clearPendingArtistMatchRequest()
    }

    func requestArtistMatch(showID: UUID, slotIndex: Int, resumePlaybackOnSuccess: Bool = false) {
        pendingArtistMatchRequest = ArtistMatchRequest(
            showID: showID,
            slotIndex: slotIndex,
            resumePlaybackOnSuccess: resumePlaybackOnSuccess
        )
    }

    /// Leaves a request in place when it belongs to a different show, so a
    /// stale room cannot drop a home-initiated match handoff.
    func consumeArtistMatchRequest(for showID: UUID) -> ArtistMatchRequest? {
        guard let request = pendingArtistMatchRequest, request.showID == showID else { return nil }
        pendingArtistMatchRequest = nil
        return request
    }

    func clearPendingArtistMatchRequest() {
        pendingArtistMatchRequest = nil
    }
}
