import Foundation

/// Fingerprint used to decide when `FootprintsView` should re-run its
/// archive/cover preparation task.
///
/// Each model contributes only its stable id + revision timestamp. Sets make
/// the fingerprint independent of SwiftData query ordering without allocating,
/// sorting, and joining large intermediary strings on every body evaluation.
struct FootprintsPreparationFingerprint: Hashable {
    struct Revision: Hashable {
        let id: UUID
        let updatedAt: Date
    }

    let shows: Set<Revision>
    let fragments: Set<Revision>
    let assets: Set<Revision>

    static func make(
        shows: [Show],
        fragments: [MemoryFragment],
        assets: [ShowAsset]
    ) -> FootprintsPreparationFingerprint {
        FootprintsPreparationFingerprint(
            shows: Set(shows.map { Revision(id: $0.id, updatedAt: $0.updatedAt) }),
            fragments: Set(fragments.map { Revision(id: $0.id, updatedAt: $0.updatedAt) }),
            assets: Set(assets.map { Revision(id: $0.id, updatedAt: $0.updatedAt) })
        )
    }
}
