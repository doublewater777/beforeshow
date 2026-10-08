import Foundation

/// One shelf section: the live-preview compilation or one artist. The head disc
/// stands on the first-level rack; the full list unfolds in place.
struct ListeningRackGroup: Identifiable, Equatable {
    enum Kind: Equatable {
        case live
        case artist(id: String, slotIndex: Int, isConnected: Bool)
    }

    let id: String
    let kind: Kind
    let name: String
    let artworkURL: URL?
    let discs: [ListeningDisc]

    var head: ListeningDisc? { discs.first }
    var canExpand: Bool { discs.count > 1 }
    var scope: ListeningBrowseState.Scope {
        switch kind {
        case .live: .all
        case let .artist(id, _, _): .artist(id)
        }
    }
}

/// Wanted artists first, then stage order; artists missing from the timetable keep lineup order.
enum ListeningRackOrdering {
    struct Performance {
        let artistName: String
        let startsAt: Date
        let isInterested: Bool
    }

    static func order(names: [String], performances: [Performance]) -> [Int] {
        func key(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var byName: [String: Performance] = [:]
        for performance in performances {
            let name = key(performance.artistName)
            if let existing = byName[name], existing.startsAt <= performance.startsAt,
               existing.isInterested || !performance.isInterested { continue }
            byName[name] = performance
        }
        return names.indices.sorted { lhs, rhs in
            let a = byName[key(names[lhs])], b = byName[key(names[rhs])]
            let wantA = a?.isInterested == true, wantB = b?.isInterested == true
            if wantA != wantB { return wantA }
            switch (a?.startsAt, b?.startsAt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs < rhs
            }
        }
    }
}

@MainActor extension ListeningRoomCoordinator {
    var rackGroups: [ListeningRackGroup] {
        var groups: [ListeningRackGroup] = []
        if !compilationDiscs.isEmpty {
            groups.append(ListeningRackGroup(
                id: "live",
                kind: .live,
                name: ListeningCopy.text("现场预习"),
                artworkURL: nil,
                discs: compilationDiscs
            ))
        }
        let performances = (show?.timetable?.orderedDays ?? []).flatMap(\.performances).map {
            ListeningRackOrdering.Performance(artistName: $0.artistName, startsAt: $0.startsAt, isInterested: $0.isInterested)
        }
        let order = ListeningRackOrdering.order(names: browseArtists.map(\.name), performances: performances)
        for artist in order.map({ browseArtists[$0] }) {
            groups.append(ListeningRackGroup(
                id: artist.id,
                kind: .artist(id: artist.id, slotIndex: artist.slotIndex, isConnected: artist.isConnected),
                name: artist.name,
                artworkURL: artist.artworkURL,
                discs: artist.albums.filter { $0.isSingle != true }
            ))
        }
        return groups
    }
}
