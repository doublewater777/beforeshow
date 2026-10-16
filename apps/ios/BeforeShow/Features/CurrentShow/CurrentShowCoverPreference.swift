import Foundation

/// 现场模式下切回普通封面的选择，只对做出选择的那场演出生效；该场现场结束时清除。
enum CurrentShowCoverPreference {
    static let key = "currentShow.expandedCoverShowID"

    static func isExpanded(storedShowID: String, showID: UUID) -> Bool {
        storedShowID == showID.uuidString
    }

    static func toggled(storedShowID: String, showID: UUID) -> String {
        isExpanded(storedShowID: storedShowID, showID: showID) ? "" : showID.uuidString
    }
}
