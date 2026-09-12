import Foundation
import MusicKit

/// A single artist candidate returned by an [`ArtistSearchServicing`].
/// `id` is the Apple Music catalog artist id (string-encoded) so the same artist reappears
/// the same way across searches.
struct RecognizedArtist: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let canonicalName: String
    let avatarURL: URL?
    /// Apple Music 艺人页链接,详情页点阵容头像直接跳转。
    let appleMusicURL: URL?
}

enum ArtistSearchAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

enum ArtistSearchError: Error, Equatable, Sendable {
    case network
    case rateLimited
    case server(statusCode: Int)
    case invalidResponse(statusCode: Int?)
    case decoding
}

/// Boundary so the form / picker never has to know about the search backend directly.
/// Implementations must never throw on denial or empty results — return `[]` instead
/// so the picker can hide gracefully without blocking manual entry.
protocol ArtistSearchServicing: Sendable {
    func searchArtists(query: String) async throws -> [RecognizedArtist]
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus
}

typealias ArtistSearchOperation = @Sendable (_ query: String, _ limit: Int) async throws -> [RecognizedArtist]

/// Production artist search.
///
/// MusicKit's Apple Music catalog is the primary source so artist identity matches the
/// same catalog used by the listening experience. The public iTunes Search API remains
/// as a no-auth fallback for add/edit-show flows and transient MusicKit failures. If its
/// `musicArtist` index misses a long-tail artist, a song search can still recover the
/// artist identity from track metadata.
struct AppleMusicArtistSearchService: ArtistSearchServicing {
    let limit: Int
    let country: String
    let session: URLSession

    private let catalogSearch: ArtistSearchOperation
    private let fallbackSearch: ArtistSearchOperation

    init(limit: Int = 8, country: String = "CN", session: URLSession = .shared) {
        self.limit = limit
        self.country = country
        self.session = session
        self.catalogSearch = Self.searchMusicKitCatalog
        self.fallbackSearch = { query, limit in
            try await Self.searchITunesFallback(
                query: query,
                limit: limit,
                country: country,
                session: session
            )
        }
    }

    /// Test seam for the source-selection policy without live Apple services.
    init(
        limit: Int = 8,
        catalogSearch: @escaping ArtistSearchOperation,
        fallbackSearch: @escaping ArtistSearchOperation
    ) {
        self.limit = limit
        self.country = "CN"
        self.session = .shared
        self.catalogSearch = catalogSearch
        self.fallbackSearch = fallbackSearch
    }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus {
        // Searching must remain usable while adding/editing a show without presenting an
        // Apple Music permission prompt. MusicKit is attempted opportunistically and the
        // public iTunes endpoint remains available when MusicKit cannot serve the request.
        .authorized
    }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var catalogResults: [RecognizedArtist] = []
        var catalogSucceeded = false
        do {
            catalogResults = try await catalogSearch(trimmed, limit)
            catalogSucceeded = true
            if Self.containsExactName(catalogResults, query: trimmed) {
                return Self.mergedCandidates(
                    primary: catalogResults,
                    secondary: [],
                    query: trimmed,
                    limit: limit
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fall through to the public no-auth source. If it also fails, that concrete
            // failure is surfaced so the UI can distinguish service failure from no result.
        }

        do {
            let fallbackResults = try await fallbackSearch(trimmed, limit)
            return Self.mergedCandidates(
                primary: catalogResults,
                secondary: fallbackResults,
                query: trimmed,
                limit: limit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if catalogSucceeded { return catalogResults }
            throw error
        }
    }

    private static func searchMusicKitCatalog(query: String, limit: Int) async throws -> [RecognizedArtist] {
        var request = MusicCatalogSearchRequest(term: query, types: [Artist.self])
        request.limit = limit
        let response = try await request.response()
        return response.artists.map { artist in
            RecognizedArtist(
                id: artist.id.rawValue,
                canonicalName: artist.name,
                avatarURL: artist.artwork?.url(width: 240, height: 240),
                appleMusicURL: artist.url
            )
        }
    }

    private static func searchITunesFallback(
        query: String,
        limit: Int,
        country: String,
        session: URLSession
    ) async throws -> [RecognizedArtist] {
        let direct = try await searchITunesArtists(
            query: query,
            limit: limit,
            country: country,
            session: session
        )
        if containsExactName(direct, query: query) {
            return mergedCandidates(primary: direct, secondary: [], query: query, limit: limit)
        }

        do {
            let inferred = try await inferITunesArtistsFromSongs(
                query: query,
                limit: limit,
                country: country,
                session: session
            )
            return mergedCandidates(primary: direct, secondary: inferred, query: query, limit: limit)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if !direct.isEmpty { return direct }
            throw error
        }
    }

    private static func searchITunesArtists(
        query: String,
        limit: Int,
        country: String,
        session: URLSession
    ) async throws -> [RecognizedArtist] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url else { throw ArtistSearchError.invalidResponse(statusCode: nil) }
        let decoded: ITunesSearchResponse = try await decodeITunesResponse(from: url, session: session)
        return decoded.results.map(toRecognized)
    }

    private static func inferITunesArtistsFromSongs(
        query: String,
        limit: Int,
        country: String,
        session: URLSession
    ) async throws -> [RecognizedArtist] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(max(limit * 4, 24))),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url else { throw ArtistSearchError.invalidResponse(statusCode: nil) }
        let decoded: ITunesSongSearchResponse = try await decodeITunesResponse(from: url, session: session)

        var seenArtistIDs = Set<Int>()
        var artists: [RecognizedArtist] = []
        for song in decoded.results where seenArtistIDs.insert(song.artistId).inserted {
            artists.append(RecognizedArtist(
                id: String(song.artistId),
                canonicalName: song.artistName,
                avatarURL: upgradedArtworkURL(song.artworkUrl100, size: 240),
                appleMusicURL: song.artistViewUrl.flatMap(URL.init(string:))
            ))
            if artists.count == limit { break }
        }
        return artists
    }

    private static func decodeITunesResponse<Response: Decodable>(
        from url: URL,
        session: URLSession
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ArtistSearchError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw ArtistSearchError.invalidResponse(statusCode: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 { throw ArtistSearchError.rateLimited }
            if (500..<600).contains(http.statusCode) {
                throw ArtistSearchError.server(statusCode: http.statusCode)
            }
            throw ArtistSearchError.invalidResponse(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ArtistSearchError.decoding
        }
    }

    private static func toRecognized(_ result: ITunesArtist) -> RecognizedArtist {
        RecognizedArtist(
            id: String(result.artistId),
            canonicalName: result.artistName,
            avatarURL: upgradedArtworkURL(result.artworkUrl100, size: 240),
            appleMusicURL: result.artistLinkUrl.flatMap(URL.init(string:))
        )
    }

    private static func containsExactName(_ candidates: [RecognizedArtist], query: String) -> Bool {
        let normalizedQuery = normalizedName(query)
        return candidates.contains { normalizedName($0.canonicalName) == normalizedQuery }
    }

    private static func mergedCandidates(
        primary: [RecognizedArtist],
        secondary: [RecognizedArtist],
        query: String,
        limit: Int
    ) -> [RecognizedArtist] {
        let normalizedQuery = normalizedName(query)
        let combined = primary + secondary
        let ordered = combined.filter { normalizedName($0.canonicalName) == normalizedQuery }
            + combined.filter { normalizedName($0.canonicalName) != normalizedQuery }

        var seenIDs = Set<String>()
        var result: [RecognizedArtist] = []
        for candidate in ordered where seenIDs.insert(candidate.id).inserted {
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split { $0.isWhitespace || $0.isNewline }
        .joined(separator: " ")
    }

    private static func upgradedArtworkURL(_ rawValue: String?, size: Int) -> URL? {
        rawValue?
            .replacingOccurrences(of: "100x100", with: "\(size)x\(size)")
            .flatMap(URL.init(string:))
    }
}

private struct ITunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesArtist]
}

private struct ITunesArtist: Decodable {
    let artistId: Int
    let artistName: String
    let artistLinkUrl: String?
    let artworkUrl100: String?
}

private struct ITunesSongSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesSong]
}

private struct ITunesSong: Decodable {
    let artistId: Int
    let artistName: String
    let artistViewUrl: String?
    let artworkUrl100: String?
}

/// 给足迹 #01 卡片背景找"代表专辑封面"：iTunes search 拿 artistId，再 lookup
/// 该艺人的专辑列表，取发行日期最新的一张封面（升到 600×600）。
/// 与艺人搜索一样全是公开端点；结果按艺名内存缓存，单次启动内只查一次。
actor ArtistAlbumArtworkResolver {
    static let shared = ArtistAlbumArtworkResolver()

    private let session: any URLSessionProtocol
    private var cache: [String: URL?] = [:]

    init(session: any URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func artworkURL(forArtistName name: String, country: String = "CN") async -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = "\(country)|\(trimmed)"
        if cache.keys.contains(key) { return cache[key] ?? nil }
        let resolved = await resolve(artistName: trimmed, country: country)
        cache.updateValue(resolved, forKey: key)
        return resolved
    }

    private func resolve(artistName: String, country: String) async -> URL? {
        guard let artistID = await searchArtistID(name: artistName, country: country) else { return nil }
        return await latestAlbumArtworkURL(artistID: artistID, country: country)
    }

    private func searchArtistID(name: String, country: String) async -> Int? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url,
              let data = await fetch(url),
              let decoded = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data) else {
            return nil
        }
        return decoded.results.first?.artistId
    }

    private func latestAlbumArtworkURL(artistID: Int, country: String) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(artistID)),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url,
              let data = await fetch(url),
              let decoded = try? JSONDecoder().decode(ITunesLookupResponse.self, from: data) else {
            return nil
        }
        return Self.bestArtworkURL(from: decoded.results, artistID: artistID)
    }

    /// 取该艺人自己（`artistId` 匹配,排除 feat. 合作发行）发行日期最新的封面;
    /// 匹配不到就退而求其次用任意 collection。`artworkUrl100` 升到 600×600 让背景不糊。
    static func bestArtworkURL(from collections: [ITunesCollection], artistID: Int) -> URL? {
        let usable = collections.filter { $0.wrapperType == "collection" && $0.artworkUrl100 != nil }
        let own = usable.filter { $0.artistId == artistID }
        let artwork = (own.isEmpty ? usable : own)
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            .first?
            .artworkUrl100?
            .replacingOccurrences(of: "100x100", with: "600x600")
        return artwork.flatMap { URL(string: $0) }
    }

    private func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(for: URLRequest(url: url)),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return data
    }
}

struct ITunesCollection: Decodable, Equatable {
    let wrapperType: String
    let artistId: Int?
    let releaseDate: String?
    let artworkUrl100: String?
}

private struct ITunesLookupResponse: Decodable {
    let results: [ITunesCollection]
}
