import Foundation

/// Deprecated: element type of the persisted `Show.companionMembers` field from the
/// retired invite flow. Kept so existing stores decode; nothing reads it anymore.
struct CompanionMember: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var alias: String?
}
