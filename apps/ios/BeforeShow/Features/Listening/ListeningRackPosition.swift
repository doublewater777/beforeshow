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
        // On a new local day, a collapsed shelf should start at its new featured sleeve.
        let savedFocus = saved?["focusedID"] as? String
        let focusDay = saved?["focusedDay"] as? String
        focusedID = expandedGroupID != nil || focusDay == ListeningDailyFeaturedDiscPolicy.dayKey(for: Date())
            ? savedFocus : nil
    }

    func refreshDayIfNeeded() {
        guard let key, expandedGroupID == nil else { return }
        let day = ListeningDailyFeaturedDiscPolicy.dayKey(for: Date())
        guard defaults.dictionary(forKey: key)?["focusedDay"] as? String != day else { return }
        focusedID = nil
        save()
    }

    private func save() {
        guard let key else { return }
        var saved: [String: String] = [:]
        saved["expandedGroupID"] = expandedGroupID
        saved["focusedID"] = focusedID
        saved["focusedDay"] = ListeningDailyFeaturedDiscPolicy.dayKey(for: Date())
        defaults.set(saved, forKey: key)
    }
}
