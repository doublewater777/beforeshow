import Foundation

/// A single artist candidate returned by an [`ArtistSearchServicing`].
/// `id` is the iTunes catalog artist id (string-encoded) so the same artist reappears
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
            avatarURL: avatar.flatMap { URL(string: $0) },
            appleMusicURL: result.artistLinkUrl.flatMap { URL(string: $0) }
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
        if let cached = cache[key] { return cached }
        let resolved = await resolve(artistName: trimmed, country: country)
        cache[key] = resolved
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

