import Foundation
import MusicKit
import OSLog

/// Internal source signal: public artist search does not require MusicKit access.
enum ArtistCatalogSearchError: Error {
    case accessUnavailable
}

enum ArtistSearchError: Error, Equatable, Sendable {
    case network
    case catalogUnavailable
    case rateLimited
    case server(statusCode: Int)
    case invalidResponse(statusCode: Int?)
    case decoding
}

/// Boundary so the form / picker never has to know about the search backend directly.
/// Empty results mean a completed search. Failures retain the reason needed to recover.
protocol ArtistSearchServicing: Sendable {
    func searchArtists(query: String) async throws -> [RecognizedArtist]
    func searchArtists(query: String, exactMatchRequired: Bool) async throws -> [RecognizedArtist]
}

extension ArtistSearchServicing {
    func searchArtists(query: String, exactMatchRequired: Bool) async throws -> [RecognizedArtist] {
        try await searchArtists(query: query)
    }
}

typealias ArtistSearchOperation = @Sendable (_ query: String, _ limit: Int, _ exactMatchRequired: Bool) async throws -> [RecognizedArtist]

/// Production artist search.
///
/// MusicKit's Apple Music catalog is the primary source so artist identity matches the
/// same catalog used by the listening experience. The public iTunes Search API remains
/// as a no-auth fallback for add/edit-show flows and transient MusicKit failures. If its
/// `musicArtist` index misses a long-tail artist, a song search can still recover the
/// artist identity from track metadata.
actor AppleMusicArtistSearchService: ArtistSearchServicing {
    private static let logger = Logger(subsystem: "com.doublewaterapps.beforeshow", category: "ArtistSearch")
    let limit: Int
    let country: String?
    let session: URLSession

    private let catalogSearch: ArtistSearchOperation
    private let fallbackSearch: ArtistSearchOperation
    private var cachedAuthorization: MusicAuthorization.Status?
    private var cache: [String: (expiresAt: ContinuousClock.Instant, candidates: [RecognizedArtist], isComplete: Bool)] = [:]

    init(limit: Int = 8, country: String? = nil, session: URLSession = .shared) {
        self.limit = limit
        self.country = country
        self.session = session
        self.catalogSearch = Self.searchMusicKitCatalog
        self.fallbackSearch = { query, limit, exactMatchRequired in
            let region = await Self.currentFallbackCountry(preferred: country)
            return try await Self.searchITunesFallback(
                query: query,
                limit: limit,
                country: region,
                session: session,
                exactMatchRequired: exactMatchRequired
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
        self.country = nil
        self.session = .shared
        self.catalogSearch = catalogSearch
        self.fallbackSearch = fallbackSearch
    }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        try await searchArtists(query: query, exactMatchRequired: false)
    }

    func searchArtists(query: String, exactMatchRequired: Bool) async throws -> [RecognizedArtist] {
        try Task.checkCancellation()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let authorization = MusicAuthorization.currentStatus
        if cachedAuthorization != authorization {
            cache.removeAll()
            cachedAuthorization = authorization
        }
        let key = ArtistNameMatching.normalized(trimmed) + "|" + (country ?? Locale.autoupdatingCurrent.region?.identifier ?? "US")
        if let cached = cache[key], cached.expiresAt > .now, !exactMatchRequired || cached.isComplete {
            return cached.candidates
        }
        let results = try await searchUncachedArtists(query: trimmed, exactMatchRequired: exactMatchRequired)
        try Task.checkCancellation()
        if !results.isEmpty, MusicAuthorization.currentStatus == authorization {
            let now = ContinuousClock.now
            cache = cache.filter { $0.value.expiresAt > now }
            if cache.count >= 32, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                cache.removeValue(forKey: oldest)
            }
            cache[key] = (now.advanced(by: .seconds(60)), results,
                          exactMatchRequired || Self.containsMatch(results, query: trimmed, exactMatchRequired: true))
        }
        return results
    }

    static func fallbackCountry(preferred: String?, musicStorefront: String?, deviceRegion: String?) -> String {
        for value in [preferred, musicStorefront, deviceRegion] {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  value.count == 2,
                  value.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { continue }
            return value
        }
        return "US"
    }

    private static func currentFallbackCountry(preferred: String?) async -> String {
        if let preferred, !preferred.isEmpty {
            return fallbackCountry(preferred: preferred, musicStorefront: nil, deviceRegion: nil)
        }
        // Prefer the user's storefront; never prompt for Music access just to search.
        let storefront: String?
        if MusicAuthorization.currentStatus == .authorized {
            storefront = try? await MusicDataRequest.currentCountryCode
        } else {
            storefront = nil
        }
        return fallbackCountry(preferred: nil, musicStorefront: storefront,
                               deviceRegion: Locale.autoupdatingCurrent.region?.identifier)
    }

    private func searchUncachedArtists(query trimmed: String, exactMatchRequired: Bool) async throws -> [RecognizedArtist] {
        var catalogResults: [RecognizedArtist] = []
        var catalogFailure: ArtistSearchError?
        do {
            catalogResults = try await catalogSearch(trimmed, limit, exactMatchRequired)
            try Task.checkCancellation()
            if Self.containsMatch(catalogResults, query: trimmed, exactMatchRequired: exactMatchRequired) {
                return Self.mergedCandidates(
                    primary: catalogResults,
                    secondary: [],
                    query: trimmed,
                    limit: limit
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch ArtistCatalogSearchError.accessUnavailable {
            try Task.checkCancellation()
        } catch {
            try Task.checkCancellation()
            catalogFailure = error as? ArtistSearchError ?? (error is URLError ? .network : .catalogUnavailable)
        }

        do {
            try Task.checkCancellation()
            let fallbackResults = try await fallbackSearch(trimmed, limit, exactMatchRequired)
            try Task.checkCancellation()
            if fallbackResults.isEmpty, let catalogFailure { throw catalogFailure }
            return Self.mergedCandidates(
                primary: catalogResults,
                secondary: fallbackResults,
                query: trimmed,
                limit: limit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            if !catalogResults.isEmpty {
                return Self.mergedCandidates(primary: catalogResults, secondary: [], query: trimmed, limit: limit)
            }
            throw error
        }
    }

    private static func searchMusicKitCatalog(query: String, limit: Int, exactMatchRequired: Bool) async throws -> [RecognizedArtist] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ArtistCatalogSearchError.accessUnavailable
        }
        var candidates: [RecognizedArtist] = []
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Artist.self, Song.self])
            request.limit = limit
            let response = try await request.response()
            try Task.checkCancellation()
            candidates = response.artists.map(toRecognized)
            if containsMatch(candidates, query: query, exactMatchRequired: exactMatchRequired) { return candidates }

            // An artist can exist in the catalog while missing from its artist search index.
            // Resolve the songs' artist relationships rather than treating song IDs as artist IDs.
            let songs = response.songs
            if songs.isEmpty { return candidates }
            var artistRelationships = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: songs.map(\.id))
            artistRelationships.properties = [.artists]
            let resolvedSongs = try await artistRelationships.response().items
            try Task.checkCancellation()
            for song in resolvedSongs {
                try Task.checkCancellation()
                let artists = song.artists ?? []
                candidates += artists.filter { ArtistNameMatching.contains($0.name, query: query) }
                    .map(toRecognized)
            }
            return mergedCandidates(primary: candidates, secondary: [], query: query, limit: limit)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let failure = error as NSError
            logger.error("Artist catalog search failed: \(failure.domain, privacy: .public) (\(failure.code))")
            if !candidates.isEmpty {
                return mergedCandidates(primary: candidates, secondary: [], query: query, limit: limit)
            }
            if MusicAuthorization.currentStatus != .authorized {
                throw ArtistCatalogSearchError.accessUnavailable
            }
            throw error
        }
    }

    private static func toRecognized(_ artist: Artist) -> RecognizedArtist {
        RecognizedArtist(
            id: artist.id.rawValue,
            canonicalName: artist.name,
            avatarURL: artist.artwork?.url(width: 240, height: 240),
            appleMusicURL: artist.url
        )
    }

    private static func searchITunesFallback(
        query: String,
        limit: Int,
        country: String,
        session: URLSession,
        exactMatchRequired: Bool
    ) async throws -> [RecognizedArtist] {
        let direct = try await searchITunesArtists(
            query: query,
            limit: limit,
            country: country,
            session: session
        )
        try Task.checkCancellation()
        if containsMatch(direct, query: query, exactMatchRequired: exactMatchRequired) {
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
            try Task.checkCancellation()
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
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
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

    private static func containsMatch(_ candidates: [RecognizedArtist], query: String, exactMatchRequired: Bool) -> Bool {
        if exactMatchRequired {
            let normalizedQuery = ArtistNameMatching.normalized(query)
            return candidates.contains { ArtistNameMatching.normalized($0.canonicalName) == normalizedQuery }
        }
        return candidates.contains { ArtistNameMatching.contains($0.canonicalName, query: query) }
    }

    private static func mergedCandidates(
        primary: [RecognizedArtist],
        secondary: [RecognizedArtist],
        query: String,
        limit: Int
    ) -> [RecognizedArtist] {
        let normalizedQuery = ArtistNameMatching.normalized(query)
        let all = primary + secondary
        let relevant = all.filter { ArtistNameMatching.contains($0.canonicalName, query: query) }
        let combined = relevant.isEmpty ? all : relevant
        let ordered = combined.filter { ArtistNameMatching.normalized($0.canonicalName) == normalizedQuery }
            + combined.filter { ArtistNameMatching.normalized($0.canonicalName) != normalizedQuery }

        var seenIDs = Set<String>()
        var result: [RecognizedArtist] = []
        for candidate in ordered where seenIDs.insert(candidate.id).inserted {
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }

    private static func upgradedArtworkURL(_ rawValue: String?, size: Int) -> URL? {
        guard let rawValue else { return nil }
        let upgradedValue = rawValue.replacingOccurrences(
            of: "100x100",
            with: "\(size)x\(size)"
        )
        return URL(string: upgradedValue)
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

/// Resolve a representative album for a confirmed artist identity, or one unique exact match.
actor ArtistAlbumArtworkResolver {
    static let shared = ArtistAlbumArtworkResolver()

    private let session: any URLSessionProtocol
    private let search: any ArtistSearchServicing
    private let country: String
    private var cache: [String: URL?] = [:]

    init(
        session: any URLSessionProtocol = URLSession.shared,
        country: String = "CN",
        search: (any ArtistSearchServicing)? = nil
    ) {
        self.session = session
        self.country = country
        self.search = search ?? AppleMusicArtistSearchService(country: country)
    }

    func artworkURL(forArtistName name: String, artistID: String? = nil) async -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = "\(country)|\(artistID.map { "id:\($0)" } ?? "name:\(ArtistNameMatching.normalized(trimmed))")"
        if cache.keys.contains(key) { return cache[key] ?? nil }
        do {
            let resolvedID: String?
            if let artistID {
                resolvedID = artistID
            } else {
                let candidates = try await search.searchArtists(query: trimmed, exactMatchRequired: true)
                resolvedID = ArtistNameMatching.uniqueExactMatch(for: trimmed, among: candidates)?.id
            }
            let resolved: URL?
            if let resolvedID, let numericID = Int(resolvedID) {
                resolved = try await latestAlbumArtworkURL(artistID: numericID)
            } else {
                resolved = nil
            }
            try Task.checkCancellation()
            cache.updateValue(resolved, forKey: key)
            return resolved
        } catch {
            // A transient service failure must remain retryable in this launch.
            return nil
        }
    }

    private func latestAlbumArtworkURL(artistID: Int) async throws -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(artistID)),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url else { throw ArtistSearchError.invalidResponse(statusCode: nil) }
        let data = try await fetch(url)
        let decoded = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
        return Self.bestArtworkURL(from: decoded.results, artistID: artistID)
    }

    /// Only artwork belonging to this artist may be persisted onto their lineup slots.
    static func bestArtworkURL(from collections: [ITunesCollection], artistID: Int) -> URL? {
        let usable = collections.filter { $0.wrapperType == "collection" && $0.artworkUrl100 != nil }
        let own = usable.filter { $0.artistId == artistID }
        let artwork = own
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            .first?
            .artworkUrl100?
            .replacingOccurrences(of: "100x100", with: "600x600")
        return artwork.flatMap { URL(string: $0) }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw ArtistSearchError.invalidResponse(statusCode: nil) }
        guard (200..<300).contains(http.statusCode) else { throw ArtistSearchError.server(statusCode: http.statusCode) }
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
