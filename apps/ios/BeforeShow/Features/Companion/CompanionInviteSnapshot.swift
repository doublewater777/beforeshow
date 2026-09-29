import Foundation

/// In-memory snapshot of an incoming invitation decoded directly from a web or app link token.
/// Used for deferred deep link detection and customized first-time invited onboarding.
struct CompanionInviteSnapshot: Equatable, Sendable, Identifiable {
    var id: String { token }
    let token: String
    let shareURL: URL
    let showName: String
    let showStartTime: Date
    let timeZoneIdentifier: String?
    let timeZoneSecondsFromGMT: Int?
    let location: String?
    let ownerName: String
    let coverImageURL: URL?
}
