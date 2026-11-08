import Foundation
import SwiftData

/// Enforces the fragment<->show boundary against the current SwiftData state and
/// returns the on-disk-valid file map for media reconciliation.
///
/// - Fragments whose `showID` has no corresponding `Show` are orphan records (their
///   Show was deleted, or they were created against a fabricated showID) and are
///   removed here so `reconcileAll` can reclaim their files.
/// - Fragments that predate the `show` relationship (existing production data has
///   `showID` but `show == nil`) are backfilled with the relationship so the cascade
///   delete rule applies to them too.
///
/// Extracted from `reconcileAllMemoryMedia` so this production seam is unit-testable
/// without touching the media store actor or disk.
@MainActor
func reconcileMemoryFragmentShowBoundary(in modelContext: ModelContext) throws -> [UUID: [UUID: Set<String>]] {
    let shows = try modelContext.fetch(FetchDescriptor<Show>())
    let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let fragments = try modelContext.fetch(FetchDescriptor<MemoryFragment>())
    var valid: [UUID: [UUID: Set<String>]] = [:]
    var mutated = false
    var overflowPaths: [String] = []
    for fragment in fragments {
        guard let show = showsByID[fragment.showID] else {
            modelContext.delete(fragment)
            mutated = true
            continue
        }
        if fragment.show == nil {
            fragment.show = show
            mutated = true
        }
        if fragment.phaseRawValue == nil {
            fragment.phase = MemoryFragmentPhase.resolved(
                at: fragment.createdAt,
                timing: show.timingFields
            )
            mutated = true
        }
        let overflow = fragment.trimMediaToMaximum()
        if !overflow.isEmpty {
            mutated = true
            for item in overflow {
                overflowPaths.append(contentsOf: [item.relativePath, item.thumbnailRelativePath].compactMap { $0 })
                modelContext.delete(item)
            }
        }
        let paths = Set(
            fragment.mediaItems.flatMap { item in
                [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
            }
        )
        valid[fragment.showID, default: [:]][fragment.id] = paths
    }
    if mutated {
        try modelContext.save()
    }
    if !overflowPaths.isEmpty {
        Task {
            try? await MemoryFragmentMediaStore.shared.deleteFiles(relativePaths: overflowPaths)
        }
    }
    return valid
}

@MainActor
func saveModelContextRollingBackOnFailure(
    _ modelContext: ModelContext,
    save: () throws -> Void
) throws {
    do {
        try save()
    } catch {
        modelContext.rollback()
        throw error
    }
}

@MainActor
func saveModelContextRollingBackOnFailure(_ modelContext: ModelContext) throws {
    try saveModelContextRollingBackOnFailure(modelContext) {
        try modelContext.save()
    }
}

@MainActor
func reconcileShowAssetShowBoundary(
    in modelContext: ModelContext,
    existingRelativePaths: Set<String>
) throws -> Set<String> {
    let shows = try modelContext.fetch(FetchDescriptor<Show>())
    let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let assets = try modelContext.fetch(FetchDescriptor<ShowAsset>())
    var valid: Set<String> = []
    var mutated = false
    var keptByKey: [String: ShowAsset] = [:]

    let ordered = assets.sorted {
        if $0.updatedAt == $1.updatedAt {
            return $0.id.uuidString > $1.id.uuidString
        }
        return $0.updatedAt > $1.updatedAt
    }

    for asset in ordered {
        guard let show = showsByID[asset.showID] else {
            modelContext.delete(asset)
            mutated = true
            continue
        }
        if asset.show?.id != show.id {
            asset.show = show
            mutated = true
        }
        if ShowAssetKind(rawValue: asset.kindRawValue) == nil {
            modelContext.delete(asset)
            mutated = true
            continue
        }

        guard ShowAsset.isValidRelativePath(
            asset.relativePath,
            showID: asset.showID,
            kind: asset.kind
        ) else {
            modelContext.delete(asset)
            mutated = true
            continue
        }

        let key = ShowAsset.makeUniqueKey(showID: asset.showID, kind: asset.kind, assetID: asset.id)
        if asset.repairUniqueKeyIfNeeded() {
            mutated = true
        }
        if let kept = keptByKey[key] {
            if kept.id != asset.id {
                modelContext.delete(asset)
                mutated = true
            }
            continue
        }

        guard existingRelativePaths.contains(asset.relativePath) else {
            modelContext.delete(asset)
            mutated = true
            continue
        }

        keptByKey[key] = asset
        valid.insert(asset.relativePath)
    }

    if mutated {
        try saveModelContextRollingBackOnFailure(modelContext)
    }
    return valid
}

/// Merch photos share the ShowAssets root; keep their files out of the orphan sweep
/// and drop records whose show or photo is gone.
@MainActor
func reconcileMerchShowBoundary(
    in modelContext: ModelContext,
    existingRelativePaths: Set<String>
) throws -> Set<String> {
    let showsByID = Dictionary(
        try modelContext.fetch(FetchDescriptor<Show>()).map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    var valid: Set<String> = []
    var mutated = false
    for item in try modelContext.fetch(FetchDescriptor<MerchItem>()) {
        guard let show = showsByID[item.showID],
              MerchItem.isValidRelativePath(item.relativePath, showID: item.showID),
              existingRelativePaths.contains(item.relativePath) else {
            modelContext.delete(item)
            mutated = true
            continue
        }
        if item.show?.id != show.id {
            item.show = show
            mutated = true
        }
        valid.insert(item.relativePath)
        if let cutout = item.cutoutRelativePath {
            if MerchItem.isValidRelativePath(cutout, showID: item.showID), existingRelativePaths.contains(cutout) {
                valid.insert(cutout)
            } else {
                item.cutoutRelativePath = nil
                mutated = true
            }
        }
    }
    if mutated {
        try saveModelContextRollingBackOnFailure(modelContext)
    }
    return valid
}
