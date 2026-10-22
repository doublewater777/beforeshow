import Foundation

@MainActor
enum ListeningNotificationEntry {
    /// Hydrate through the normal cache/access path, which never requests authorization.
    static func open(_ link: NotificationDeepLink, show: Show, room: ListeningRoomCoordinator) async {
        let unconnectedPrefix = "unconnected-"
        let originalSlot: Int? = link.artistID.flatMap { id in
            guard link.showID == show.id, id.hasPrefix(unconnectedPrefix),
                  let index = Int(id.dropFirst(unconnectedPrefix.count)), show.artists.indices.contains(index),
                  show.artists[index].name == link.artistName else { return nil }
            return index
        }
        await room.load(show: show)
        guard !Task.isCancelled, room.show?.id == show.id else { return }
        guard link.showID == show.id else {
            room.selectScope(.all)
            return
        }
        if link.requestsPlayback {
            await room.settlePendingOperation()
            guard !Task.isCancelled, room.show?.id == show.id else { return }
        }
        if let id = link.discID, let disc = room.discs.first(where: { $0.id == id }), !disc.tracks.isEmpty {
            if link.requestsPlayback, let songID = room.discPresentation(for: disc).defaultPlayableTrackID {
                room.playFromSleeve(disc, songID: songID)
            } else {
                room.browser.open(disc)
            }
        } else {
            let artistID = link.artistID?.hasPrefix(unconnectedPrefix) == true
                ? originalSlot.flatMap { index in
                    guard show.artists.indices.contains(index), show.artists[index].name == link.artistName else { return nil }
                    return room.browseArtists.first { $0.slotIndex == index }?.id
                }
                : link.artistID
            room.selectScope(artistID.map(ListeningBrowseState.Scope.artist) ?? .all)
        }
    }
}
