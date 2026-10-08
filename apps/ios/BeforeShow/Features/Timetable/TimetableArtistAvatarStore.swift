import Foundation
import Observation

/// Avatars for timetable performers. Reuses the show's lineup first, then the
/// project's shared `ArtistIdentityMatcher` (same exact-name rule as lineups).
@MainActor
@Observable
final class TimetableArtistAvatarStore {
    private(set) var urls: [String: URL] = [:]
    @ObservationIgnored private let search: any ArtistSearchServicing
    @ObservationIgnored private var loadedKey: Set<String> = []

    init(search: any ArtistSearchServicing = AppleMusicArtistSearchService()) {
        self.search = search
    }

    func url(for artistName: String) -> URL? {
        urls[ArtistNameMatching.normalized(artistName)]
    }

    func load(artistNames: [String], lineup: [ArtistSlot]) async {
        let names = Set(artistNames.map(ArtistNameMatching.normalized).filter { !$0.isEmpty })
        guard names != loadedKey else { return }

        var found = urls
        var lineupAvatars: [String: URL] = [:]
        for slot in lineup {
            if let url = slot.avatarURL.flatMap(URL.init(string:)) {
                lineupAvatars[ArtistNameMatching.normalized(slot.name)] = url
            }
        }
        for name in artistNames {
            let match = Self.candidateQueries(for: name).lazy.compactMap { lineupAvatars[ArtistNameMatching.normalized($0)] }.first
            if let match { found[ArtistNameMatching.normalized(name)] = match }
        }
        urls = found
        // Names change on every keystroke while correcting OCR; wait for a pause.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        // Timetables often print "中文名 English Name"; try the whole name, then each half,
        // still under the matcher's exact-name rule.
        var queries: [(name: String, query: String)] = []
        var seen = Set(found.keys)
        for name in artistNames where seen.insert(ArtistNameMatching.normalized(name)).inserted {
            for query in Self.candidateQueries(for: name) { queries.append((name, query)) }
        }
        let slots = queries.map { ArtistSlot(name: $0.query, avatarURL: nil) }
        let matches = (try? await ArtistIdentityMatcher(search: search).matches(for: slots)) ?? [:]
        guard !Task.isCancelled else { return }
        for (index, query) in queries.enumerated() {
            let key = ArtistNameMatching.normalized(query.name)
            if found[key] == nil, let avatar = matches[index]?.avatarURL {
                found[key] = avatar
            }
        }
        urls = found
        loadedKey = names
    }

    static func candidateQueries(for name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCJK: (Character) -> Bool = { $0.unicodeScalars.allSatisfy { $0.value > 0x2E7F } }
        let cjk = String(trimmed.filter(isCJK)).trimmingCharacters(in: .whitespaces)
        let latin = String(trimmed.filter { !isCJK($0) }).trimmingCharacters(in: .whitespaces)
        guard !cjk.isEmpty, !latin.isEmpty else { return trimmed.isEmpty ? [] : [trimmed] }
        return [trimmed, cjk, latin]
    }
}
