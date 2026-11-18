import Foundation

struct RecognizedArtist: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let canonicalName: String
    let avatarURL: URL?
    let appleMusicURL: URL?
    /// avatarURL 是 MusicKit 或 Apple Music 公开艺人页提供的艺人照片。
    var isOfficialArtistPhoto = false
}
