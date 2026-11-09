import Foundation

/// The record that was playing when another in-app sound took over (a preview, an audition,
/// a memory video). It comes back only if nothing else touched the deck meanwhile.
@MainActor
struct InterruptedListening {
    weak var room: ListeningRoomCoordinator?
    let songID: String
    let discID: String

    /// The deck as it is now, when it is playing; nil when there is nothing to come back to.
    static func capture() -> InterruptedListening? {
        guard let room = ListeningRoomSessionStore.shared.room,
              room.deck.wantsPlayback,
              let songID = room.deck.cursorSongID,
              let discID = room.deck.currentDisc?.id else { return nil }
        return InterruptedListening(room: room, songID: songID, discID: discID)
    }

    /// Picks the record up again where the interruption paused it.
    func resume() {
        guard let room,
              ListeningRoomSessionStore.shared.room === room,
              ListeningResumePolicy.shouldResume(
                originalSongID: songID,
                originalDiscID: discID,
                currentSongID: room.deck.cursorSongID,
                currentDiscID: room.deck.currentDisc?.id,
                phase: room.deck.phase
              ),
              room.playPauseAction == .play else { return }
        room.playPause()
    }
}

enum ListeningResumePolicy {
    static func shouldResume(
        originalSongID: String,
        originalDiscID: String,
        currentSongID: String?,
        currentDiscID: String?,
        phase: ListeningPlayerPhase
    ) -> Bool {
        originalSongID == currentSongID
            && originalDiscID == currentDiscID
            && phase == .paused
    }
}

/// A one-song record played over the seated one (a footprint number song). When it plays
/// through, the record it replaced goes back on at the same track and time, playing if it was.
@MainActor
enum ListeningCutIn {
    struct Seated: Equatable {
        let cutInDiscID: String
        let disc: ListeningDisc
        let songID: String?
        let time: TimeInterval
        let wasPlaying: Bool
    }

    private(set) static var seated: Seated?

    /// What to put back after `cutIn`: the record under an earlier cut-in stays the one to return to.
    static func remembering(
        _ previous: Seated?,
        cutIn cutInDiscID: String,
        loadedDisc: ListeningDisc?,
        songID: String?,
        time: TimeInterval,
        wasPlaying: Bool
    ) -> Seated? {
        guard let loadedDisc, loadedDisc.id != cutInDiscID else { return previous }
        if let previous, previous.cutInDiscID == loadedDisc.id {
            return Seated(cutInDiscID: cutInDiscID, disc: previous.disc, songID: previous.songID,
                          time: previous.time, wasPlaying: previous.wasPlaying)
        }
        return Seated(cutInDiscID: cutInDiscID, disc: loadedDisc, songID: songID, time: time, wasPlaying: wasPlaying)
    }

    static func play(_ disc: ListeningDisc, over room: ListeningRoomCoordinator) {
        seated = remembering(seated, cutIn: disc.id, loadedDisc: room.loadedDisc,
                             songID: room.deck.cursorSongID, time: room.elapsed, wasPlaying: room.wantsPlayback)
        room.loadDisc(disc)
    }

    /// The deck played `finishedDiscID` through. Returns whether a record went back on.
    static func returnSeatedDisc(afterFinishing finishedDiscID: String?, in room: ListeningRoomCoordinator) -> Bool {
        defer { seated = nil }
        guard let seated, seated.cutInDiscID == finishedDiscID else { return false }
        room.loadDisc(seated.disc, songID: seated.songID, autoplay: seated.wasPlaying, resumeAt: seated.time)
        return true
    }

    /// 用户在插播中途换了其他唱片，丢弃此前暂存的底色唱片，避免未来误恢复。
    static func discardIfUnrelated(currentDiscID: String?) {
        guard let s = seated, s.cutInDiscID != currentDiscID else { return }
        seated = nil
    }
}
