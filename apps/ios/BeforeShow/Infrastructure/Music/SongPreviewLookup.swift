import Foundation

struct SongPreview: Codable, Equatable, Sendable {
    let trackID: Int
    let title: String
    let artist: String
    let album: String?
    let releaseYear: Int?
    let genre: String?
    let duration: TimeInterval?
    let previewURL: URL
    let artworkURL: URL?
    let storeURL: URL?
}

/// Known songs looked up by iTunes track id through the public lookup API: one request
/// for many, kept on disk, and playable as 30-second previews without Apple Music access.
actor SongPreviewLookup {
    struct Result: Decodable, Equatable, Sendable {
        let trackId: Int
        let trackName: String
        let artistName: String
        var collectionName: String?
        var releaseDate: String?
        var primaryGenreName: String?
        var trackTimeMillis: Double?
        var previewUrl: String?
        var artworkUrl100: String?
        var trackViewUrl: String?
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    static let shared = SongPreviewLookup()

    private let session: URLSession
    private let fileURL: URL?
    private var cache: [Int: SongPreview]

    init(session: URLSession = .shared, fileURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("SongPreviewLookup.v1.json")) {
        self.session = session
        self.fileURL = fileURL
        cache = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([Int: SongPreview].self, from: $0) } ?? [:]
    }

    func preview(for id: Int) async -> SongPreview? {
        await previews(for: [id])[id]
    }

    /// Track id → preview, for the ids the store has; the rest are left out.
    func previews(for ids: [Int]) async -> [Int: SongPreview] {
        var missing = ids.filter { cache[$0] == nil }
        if !missing.isEmpty {
            let country = await AppleMusicArtistSearchService.currentFallbackCountry(preferred: nil)
            // Stores carry different catalogs; the account's own store first, then the widest ones.
            let markets = [country, "TW", "US", "JP"].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            for market in markets where !missing.isEmpty {
                let results = (try? await lookup(ids: missing, country: market)) ?? []
                for preview in results.compactMap(Self.preview(from:)) {
                    cache[preview.trackID] = preview
                }
                missing = missing.filter { cache[$0] == nil }
            }
            persist()
        }
        return ids.reduce(into: [:]) { result, id in result[id] = cache[id] }
    }

    static func preview(from result: Result) -> SongPreview? {
        guard let link = result.previewUrl, let previewURL = URL(string: link) else { return nil }
        // The 100px artwork URL serves any square size by name.
        let artwork = result.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return SongPreview(
            trackID: result.trackId,
            title: result.trackName,
            artist: result.artistName,
            album: result.collectionName,
            releaseYear: result.releaseDate.flatMap { Int($0.prefix(4)) },
            genre: result.primaryGenreName,
            duration: result.trackTimeMillis.map { $0 / 1000 },
            previewURL: previewURL,
            artworkURL: artwork.flatMap(URL.init(string:)),
            storeURL: result.trackViewUrl.flatMap(URL.init(string:))
        )
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func lookup(ids: [Int], country: String) async throws -> [Result] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url else { return [] }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(Response.self, from: data).results
    }
}
