import Foundation

struct ListeningBrowseState {
    enum Scope: Equatable { case all, artist(String) }
    private(set) var scope: Scope = .all
    var detail: ListeningDisc?

    mutating func select(_ scope: Scope, validArtistIDs: Set<String>) {
        if case let .artist(id) = scope, !validArtistIDs.contains(id) {
            self.scope = .all
        } else {
            self.scope = scope
        }
    }
    mutating func reconcile(validArtistIDs: Set<String>) {
        select(scope, validArtistIDs: validArtistIDs)
    }
    mutating func open(_ disc: ListeningDisc) { detail = disc }
}

struct ListeningBrowseArtist: Identifiable, Equatable {
    let slotIndex: Int
    let id: String
    let name: String
    let artworkURL: URL?
    let appleMusicArtistID: String?
    let albums: [ListeningDisc]

    var isConnected: Bool { appleMusicArtistID != nil }
}
