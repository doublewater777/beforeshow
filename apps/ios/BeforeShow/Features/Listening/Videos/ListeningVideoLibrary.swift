import Observation

/// The 看 lineup's Bilibili results, fetched a few artists at a time.
@MainActor
@Observable
final class ListeningVideoLibrary {
    /// A festival lineup can run to dozens of artists; a few searches at a time keep Bilibili from throttling.
    private static let concurrentSearches = 4

    private(set) var results: [String: Result<[ArtistVideo], Error>] = [:]
    @ObservationIgnored private let search: any ArtistVideoSearching

    init(search: any ArtistVideoSearching = BilibiliVideoSearchService.shared) {
        self.search = search
    }

    func loadAll(_ artists: [String]) async {
        let pending = artists.filter { results[$0] == nil }
        await withTaskGroup(of: Void.self) { group in
            var queue = pending.makeIterator()
            for _ in 0..<Self.concurrentSearches {
                guard let name = queue.next() else { break }
                group.addTask { await self.load(name) }
            }
            for await _ in group {
                guard let name = queue.next() else { continue }
                group.addTask { await self.load(name) }
            }
        }
    }

    func load(_ name: String) async {
        do {
            results[name] = .success(try await search.videos(for: name))
        } catch {
            results[name] = .failure(error)
        }
    }
}
