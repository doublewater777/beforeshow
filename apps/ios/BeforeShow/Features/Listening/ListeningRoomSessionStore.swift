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

    private(set) var room: ListeningRoomCoordinator?
    private(set) var isChromePublished = false

    var chromeRoom: ListeningRoomCoordinator? {
        isChromePublished ? room : nil
    }

    private init() {}

    func adopt(_ room: ListeningRoomCoordinator?) {
        if room == nil {
            self.room?.releaseShow()
            self.room = nil
            isChromePublished = false
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
        room?.stopHardwareMotion()
        room?.releaseShow()
        room = nil
        isChromePublished = false
    }

    func clear(stoppingTransport: Bool) {
        let current = room
        let published = chromeRoom
        if stoppingTransport {
            current?.stop()
        }
        current?.stopHardwareMotion()
        current?.releaseShow()
        if let published, published !== current {
            if stoppingTransport {
                published.stop()
            }
            published.stopHardwareMotion()
            published.releaseShow()
        }
        room = nil
        isChromePublished = false
    }
}
