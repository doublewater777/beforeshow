import Foundation

struct RecognizedArtist: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let canonicalName: String
    let avatarURL: URL?
    let appleMusicURL: URL?
}
