import Foundation
import Observation

/// Avatars for timetable performers. Reuses the show's lineup first, then the
/// project's shared ranked `ArtistIdentityMatcher`.
@MainActor
@Observable
final class TimetableArtistAvatarStore {
    private(set) var urls: [String: URL] = [:]
    @ObservationIgnored private let search: any ArtistSearchServicing
    @ObservationIgnored private var loadedKey: Set<String> = []
    @ObservationIgnored private var loadedLineup: [ArtistSlot] = []

    init(search: any ArtistSearchServicing = AppleMusicArtistSearchService()) {
        self.search = search
    }

    func url(for artistName: String) -> URL? {
        urls[ArtistNameMatching.searchKey(artistName)]
    }

    func load(artistNames: [String], lineup: [ArtistSlot]) async {
        let names = Set(artistNames.map(ArtistNameMatching.searchKey).filter { !$0.isEmpty })
        guard names != loadedKey || lineup != loadedLineup else { return }

        var found = urls
        var lineupAvatars: [String: URL] = [:]
        for slot in lineup {
            if let url = slot.avatarURL.flatMap(URL.init(string:)) {
                lineupAvatars[ArtistNameMatching.normalized(slot.name)] = url
            }
        }
        for name in artistNames {
            let match = ArtistNameMatching.nameVariants(for: name).lazy.compactMap { lineupAvatars[ArtistNameMatching.normalized($0)] }.first
            if let match { found[ArtistNameMatching.searchKey(name)] = match }
        }
        urls = found
        // Names change on every keystroke while correcting OCR; wait for a pause.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        var unresolved: [String] = []
        var seen = Set(found.keys)
        for name in artistNames where seen.insert(ArtistNameMatching.searchKey(name)).inserted {
            unresolved.append(name)
        }
        let slots = unresolved.map { ArtistSlot(name: $0, avatarURL: nil) }
        let matches = (try? await ArtistIdentityMatcher(search: search).matches(for: slots)) ?? [:]
        guard !Task.isCancelled else { return }
        for (index, name) in unresolved.enumerated() {
            let key = ArtistNameMatching.searchKey(name)
            if found[key] == nil, let avatar = matches[index]?.avatarURL {
                found[key] = avatar
            }
        }
        urls = found
        loadedKey = names
        loadedLineup = lineup
    }

}
