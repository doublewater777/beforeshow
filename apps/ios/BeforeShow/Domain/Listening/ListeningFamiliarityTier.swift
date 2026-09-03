import Foundation

enum ListeningFamiliarityTier: String, CaseIterable, Equatable, Sendable {
    case firstEncounter
    case newListener
    case gettingIntoIt
    case familiar
    case deepListener

    static func resolve(familiarCount: Int, totalCount: Int) -> ListeningFamiliarityTier? {
        guard totalCount > 0, familiarCount >= 0, familiarCount <= totalCount else {
            return nil
        }
        guard familiarCount > 0 else { return .firstEncounter }

        let ratio = Double(familiarCount) / Double(totalCount)
        if ratio < 0.25 { return .newListener }
        if ratio < 0.50 { return .gettingIntoIt }
        if ratio < 0.75 { return .familiar }
        return .deepListener
    }
}
