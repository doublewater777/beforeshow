import Foundation

struct SongPreview: Equatable, Sendable {
    let trackID: Int
    let title: String
    let artist: String
    let previewURL: URL
    let artworkURL: URL?
    let storeURL: URL?
}

/// Finds a known song's 30-second preview through the public iTunes search,
/// so it plays without asking for Apple Music access.
actor SongPreviewLookup {
    struct Result: Decodable, Equatable, Sendable {
        let trackId: Int
        let trackName: String
        let artistName: String
        let previewUrl: String?
        let artworkUrl100: String?
        let trackViewUrl: String?
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    static let shared = SongPreviewLookup()

    private let session: URLSession
    private var found: [String: SongPreview] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func preview(title: String, artist: String) async -> SongPreview? {
        let key = title + "|" + artist
        if let hit = found[key] { return hit }
        let country = await AppleMusicArtistSearchService.currentFallbackCountry(preferred: nil)
        for market in country == "US" ? ["US"] : [country, "US"] {
            let results = (try? await search(term: "\(title) \(artist)", country: market)) ?? []
            if let match = Self.bestMatch(in: results, title: title, artist: artist), let preview = Self.preview(from: match) {
                found[key] = preview
                return preview
            }
        }
        return nil
    }

    /// The same song by the same artist; an exact title beats "Title (Remastered)".
    static func bestMatch(in results: [Result], title: String, artist: String) -> Result? {
        let wantedTitle = normalized(title), wantedArtist = normalized(artist)
        let candidates = results.filter {
            $0.previewUrl != nil
                && normalized($0.artistName).contains(wantedArtist)
                && normalized($0.trackName).hasPrefix(wantedTitle)
        }
        return candidates.first { normalized($0.trackName) == wantedTitle } ?? candidates.first
    }

    private static func preview(from result: Result) -> SongPreview? {
        guard let link = result.previewUrl, let previewURL = URL(string: link) else { return nil }
        return SongPreview(
            trackID: result.trackId,
            title: result.trackName,
            artist: result.artistName,
            previewURL: previewURL,
            artworkURL: result.artworkUrl100.flatMap(URL.init(string:)),
            storeURL: result.trackViewUrl.flatMap(URL.init(string:))
        )
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func search(term: String, country: String) async throws -> [Result] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url else { return [] }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(Response.self, from: data).results
    }
}
