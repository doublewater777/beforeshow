import Foundation

/// Fingerprint used to decide when `FootprintsView` should re-run its
/// archive/cover preparation task.
///
/// The previous implementation only compared counts of fragments and assets,
/// which missed content edits that don't change the count (e.g. replacing
/// one memory photo with another, or `ShowAsset.replaceImage(...)`).
/// Including `updatedAt` per id makes every meaningful edit observable to
/// `.task(id:)`.
///
/// `make(...)` is the single source of truth — do not recompute the
/// fingerprint inline at call sites, or the regression it guards against
/// will return.
struct FootprintsPreparationFingerprint: Hashable {
    let value: String

    static func make(
        shows: [Show],
        fragments: [MemoryFragment],
        assets: [ShowAsset]
    ) -> FootprintsPreparationFingerprint {
        let showPart = shows
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        let fragmentPart = fragments
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        let assetPart = assets
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        return FootprintsPreparationFingerprint(
            value: "S#\(showPart)#F#\(fragmentPart)#A#\(assetPart)"
        )
    }
}
