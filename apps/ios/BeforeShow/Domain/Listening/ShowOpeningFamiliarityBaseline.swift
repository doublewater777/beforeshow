import Foundation
import SwiftData

@Model
final class ShowOpeningFamiliarityBaseline {
    @Attribute(.unique)
    private(set) var showIDKey: String
    private(set) var showID: UUID
    var effectiveStartAtCapture: Date
    var familiarSongIDsAtCapture: [String]
    var capturedAt: Date

    init(
        showID: UUID,
        effectiveStartAtCapture: Date,
        familiarSongIDsAtCapture: [String],
        capturedAt: Date = Date()
    ) {
        self.showIDKey = Self.makeUniqueKey(showID: showID)
        self.showID = showID
        self.effectiveStartAtCapture = effectiveStartAtCapture
        self.familiarSongIDsAtCapture = familiarSongIDsAtCapture
        self.capturedAt = capturedAt
    }

    static func makeUniqueKey(showID: UUID) -> String {
        showID.uuidString
    }
}
