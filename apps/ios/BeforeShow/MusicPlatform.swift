import Foundation

enum MusicPlatform: String, CaseIterable, Identifiable, Codable, Equatable {
    case appleMusic = "Apple Music"
    case neteaseCloudMusic = "网易云音乐"
    case qqMusic = "QQ 音乐"
    case spotify = "Spotify"

    var id: String { rawValue }

    var displayName: String { rawValue }

    func searchURL(for song: CandidateSongSnapshot) -> URL {
        let query = "\(song.songName) \(song.artist)"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        switch self {
        case .appleMusic:
            return URL(string: "music://music.apple.com/search?term=\(encodedQuery)")!
        case .neteaseCloudMusic:
            return URL(string: "orpheus://search/\(encodedQuery)")!
        case .qqMusic:
            return URL(string: "qqmusic://qq.com/ui/search?p=%7B%22key%22%3A%22\(encodedQuery)%22%7D")!
        case .spotify:
            return URL(string: "spotify:search:\(encodedQuery)")!
        }
    }
}
