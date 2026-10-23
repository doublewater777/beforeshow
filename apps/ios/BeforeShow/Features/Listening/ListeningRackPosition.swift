import Foundation
import Observation

@MainActor
@Observable
final class ListeningRackPosition {
    var expandedGroupID: String? { didSet { save() } }
    var focusedID: String? { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String?

    init(showID: UUID?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = showID.map { "listening.rackPosition.\($0.uuidString)" }
        let saved = key.flatMap { defaults.dictionary(forKey: $0) }
        expandedGroupID = saved?["expandedGroupID"] as? String
        focusedID = saved?["focusedID"] as? String
    }

    private func save() {
        guard let key else { return }
        var saved: [String: String] = [:]
        saved["expandedGroupID"] = expandedGroupID
        saved["focusedID"] = focusedID
        defaults.set(saved, forKey: key)
    }
}
