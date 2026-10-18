import Foundation

struct RecognizedArtist: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let canonicalName: String
    let avatarURL: URL?
    let appleMusicURL: URL?
    /// avatarURL 是 Apple Music 艺人照片（MusicKit Artist.artwork），而不是专辑/歌曲图或来源不明的图。
    var isOfficialArtistPhoto = false
}
