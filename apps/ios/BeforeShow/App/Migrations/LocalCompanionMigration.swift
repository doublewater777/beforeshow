import Foundation
import SwiftData

/// #388: companions became plain local names. Names on invites that were never
/// confirmed (pending) or were ended/revoked (canceled) never counted as footprints,
/// so they are cleared; confirmed names stay. Runs once, guarded by a defaults flag,
/// so names written after the upgrade are never touched.
@MainActor
enum LocalCompanionMigration {
    static let completedKey = "companion.local-record-migration.v1"

    static func migrateIfNeeded(in modelContext: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completedKey),
              let shows = try? modelContext.fetch(FetchDescriptor<Show>()) else { return }
        var didChange = false
        for show in shows where !show.companionNames.isEmpty {
            switch show.legacyCompanionStatus {
            case .pending, .canceled:
                show.clearLegacyUnconfirmedCompanionNames()
                didChange = true
            case .none, .confirmed:
                break
            }
        }
        if didChange {
            do { try modelContext.save() } catch { return }
        }
        defaults.set(true, forKey: completedKey)
    }
}
