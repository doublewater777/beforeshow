import Foundation

struct ArtistVideo: Identifiable, Equatable, Sendable {
    let bvid: String
    let title: String
    let author: String
    let playCount: Int
    let duration: String
    let coverURL: URL?

    var id: String { bvid }

    var appURL: URL { URL(string: "bilibili://video/\(bvid)")! }
    var webURL: URL { URL(string: "https://www.bilibili.com/video/\(bvid)")! }
}

protocol ArtistVideoSearching: Sendable {
    func videos(for artist: String) async throws -> [ArtistVideo]
    func stream(for bvid: String) async throws -> ArtistVideoStream
}

/// A progressive mp4 the CDN serves only with the Bilibili referer.
struct ArtistVideoStream: Equatable, Sendable {
    let url: URL
    let headers: [String: String]
}

enum BilibiliSearchParser {
    private struct Response: Decodable {
        struct Payload: Decodable { let result: [Item]? }
        let code: Int
        let data: Payload?
    }

    private struct Item: Decodable {
        let bvid: String
        let title: String
        let author: String
        let play: FlexibleInt
        let duration: String
        let pic: String
    }

    private struct FlexibleInt: Decodable {
        let value: Int
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = number
            } else {
                value = Int(try container.decode(String.self)) ?? 0
            }
        }
    }

    struct ServiceError: Error, Equatable { let code: Int }

    /// Keeps only videos whose title or uploader names the artist; search otherwise drifts into unrelated hits.
    static func videos(from data: Data, artist: String, limit: Int = 10) throws -> [ArtistVideo] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == 0 else { throw ServiceError(code: response.code) }
        let needle = normalized(artist)
        var seen: Set<String> = []
        return (response.data?.result ?? []).compactMap { item -> ArtistVideo? in
            let title = plainText(item.title)
            guard !needle.isEmpty,
                  normalized(title).contains(needle) || normalized(item.author).contains(needle),
                  seen.insert(item.bvid).inserted else { return nil }
            let cover = item.pic.hasPrefix("//") ? "https:" + item.pic : item.pic
            return ArtistVideo(bvid: item.bvid, title: title, author: item.author,
                               playCount: item.play.value, duration: item.duration,
                               coverURL: URL(string: cover))
        }
        .prefix(limit)
        .map { $0 }
    }

    /// `view` gives the first part's cid; `playurl` turns it into an mp4 address.
    static func cid(from data: Data) throws -> Int {
        struct View: Decodable { struct Payload: Decodable { let cid: Int }; let code: Int; let data: Payload? }
        let view = try JSONDecoder().decode(View.self, from: data)
        guard view.code == 0, let cid = view.data?.cid else { throw ServiceError(code: view.code) }
        return cid
    }

    static func streamURL(from data: Data) throws -> URL {
        struct PlayURL: Decodable {
            struct Payload: Decodable { struct Part: Decodable { let url: String }; let durl: [Part]? }
            let code: Int
            let data: Payload?
        }
        let response = try JSONDecoder().decode(PlayURL.self, from: data)
        guard response.code == 0, let address = response.data?.durl?.first?.url,
              let url = URL(string: address.replacingOccurrences(of: "http://", with: "https://")) else {
            throw ServiceError(code: response.code)
        }
        return url
    }

    static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">")]
            .reduce(stripped) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }
}

/// Bilibili's public web search. It needs a `buvid3` device cookie, issued by the `spi` endpoint.
actor BilibiliVideoSearchService: ArtistVideoSearching {
    static let shared = BilibiliVideoSearchService()

    private let session: URLSession
    private var buvid3: String?
    private var cache: [String: [ArtistVideo]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func videos(for artist: String) async throws -> [ArtistVideo] {
        if let cached = cache[artist] { return cached }
        let cookie = try await deviceCookie()
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/search/type")!
        components.queryItems = [
            URLQueryItem(name: "search_type", value: "video"),
            // 3 is the music zone; other zones mostly match generic words in band names.
            URLQueryItem(name: "tids", value: "3"),
            URLQueryItem(name: "keyword", value: artist),
        ]
        let data = try await get(components.url!, cookie: cookie)
        let videos = try BilibiliSearchParser.videos(from: data, artist: artist)
        cache[artist] = videos
        return videos
    }

    func stream(for bvid: String) async throws -> ArtistVideoStream {
        let cookie = try await deviceCookie()
        let view = try await get(URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)")!, cookie: cookie)
        let cid = try BilibiliSearchParser.cid(from: view)
        let play = try await get(URL(string: "https://api.bilibili.com/x/player/playurl?bvid=\(bvid)&cid=\(cid)&platform=html5&qn=80&high_quality=1")!, cookie: cookie)
        return ArtistVideoStream(
            url: try BilibiliSearchParser.streamURL(from: play),
            headers: ["Referer": Self.referer, "User-Agent": Self.userAgent]
        )
    }

    private func get(_ url: URL, cookie: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.referer, forHTTPHeaderField: "Referer")
        request.setValue("buvid3=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return try await session.data(for: request).0
    }

    private func deviceCookie() async throws -> String {
        if let buvid3 { return buvid3 }
        struct SPI: Decodable {
            struct Payload: Decodable { let b_3: String }
            let data: Payload
        }
        var request = URLRequest(url: URL(string: "https://api.bilibili.com/x/frontend/finger/spi")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let value = try JSONDecoder().decode(SPI.self, from: data).data.b_3
        buvid3 = value
        return value
    }

    private static let referer = "https://www.bilibili.com/"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
}
