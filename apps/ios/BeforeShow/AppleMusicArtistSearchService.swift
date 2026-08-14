import Foundation

/// A single artist candidate returned by an [`ArtistSearchServicing`].
/// `id` is the iTunes catalog artist id (string-encoded) so the same artist reappears
/// the same way across searches.
struct RecognizedArtist: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let canonicalName: String
    let avatarURL: URL?
}

enum ArtistSearchAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

/// Boundary so the form / picker never has to know about the search backend directly.
/// Implementations must never throw on denial or empty results — return `[]` instead
/// so the picker can hide gracefully without blocking manual entry.
protocol ArtistSearchServicing: Sendable {
    func searchArtists(query: String) async throws -> [RecognizedArtist]
    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus
}

/// Production artist search backed by the public iTunes Search API.
///
/// 临时替换了原本的 MusicKit `MusicCatalogSearchRequest` 实现 —— MusicKit 需要
/// 开发者 token + Apple ID 登录 + 真机/已登录模拟器，演示阶段还没接 App Store Connect
/// 的 MusicKit key。iTunes Search API 是公开端点，模拟器直接出结果。
/// 后续接上 developer token 后可换回 `MusicCatalogSearchRequest`，调用方不动。
struct AppleMusicArtistSearchService: ArtistSearchServicing {
    let limit: Int
    let country: String
    let session: URLSession

    init(limit: Int = 8, country: String = "CN", session: URLSession = .shared) {
        self.limit = limit
        self.country = country
        self.session = session
    }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus {
        // iTunes Search 是公开端点,不需要 Apple ID 授权。
        .authorized
    }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            return decoded.results.map(Self.toRecognized)
        } catch {
            // 任何网络 / 解析错误都退化成空,避免 picker 显示错误态打断手输。
            return []
        }
    }

    private static func toRecognized(_ result: ITunesArtist) -> RecognizedArtist {
        // artworkUrl100 是 100×100,请求 240 让头像更锐。
        let avatar = result.artworkUrl100?
            .replacingOccurrences(of: "100x100", with: "240x240")
        return RecognizedArtist(
            id: String(result.artistId),
            canonicalName: result.artistName,
            avatarURL: avatar.flatMap { URL(string: $0) }
        )
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

/// Test / DEBUG stub — never hits the network. Tests inject canned results keyed by
/// the exact query string (or `"*"` as a wildcard fallback).
final class StubArtistSearchService: ArtistSearchServicing, @unchecked Sendable {
    var canned: [String: [RecognizedArtist]] = [:]
    var status: ArtistSearchAuthorizationStatus = .authorized
    private let counter = RequestCounter()

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus {
        status
    }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        counter.increment()
        return canned[query] ?? canned["*"] ?? []
    }

    var requestCount: Int { counter.value }

    private final class RequestCounter: @unchecked Sendable {
        private var _value: Int = 0
        private let lock = NSLock()
        func increment() { lock.lock(); _value += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    }
}
