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
func reconcileDynamicCoverModelBoundary(
    in modelContext: ModelContext,
    existingRelativePaths: Set<String>
) throws -> Set<String> {
    let shows = try modelContext.fetch(FetchDescriptor<Show>())
    let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let covers = try modelContext.fetch(FetchDescriptor<DynamicCover>())
    var validPaths = Set<String>()
    var mutated = false
    var keptByShowID: [UUID: DynamicCover] = [:]

    for cover in covers.sorted(by: { $0.updatedAt > $1.updatedAt }) {
        guard let show = showsByID[cover.showID],
              cover.showID == show.id,
              DynamicCover.isValidRelativePath(cover.relativePath, showID: show.id),
              existingRelativePaths.contains(cover.relativePath) else {
            if let show = showsByID[cover.showID], show.dynamicCover?.id == cover.id {
                show.dynamicCover = nil
                DynamicCoverFaceStore.clear(showID: show.id)
                mutated = true
            }
            modelContext.delete(cover)
            mutated = true
            continue
        }
        if let kept = keptByShowID[show.id], kept.id != cover.id {
            modelContext.delete(cover)
            mutated = true
            continue
        }
        if cover.show?.id != show.id {
            cover.show = show
            mutated = true
        }
        keptByShowID[show.id] = cover
        validPaths.insert(cover.relativePath)
        if let posterPath = cover.posterRelativePath {
            if DynamicCover.isValidRelativePath(posterPath, showID: show.id),
               existingRelativePaths.contains(posterPath) {
                validPaths.insert(posterPath)
            } else {
                cover.posterRelativePath = nil
                mutated = true
            }
        }
    }
    for show in shows {
        let reconciledCover = keptByShowID[show.id]
        if show.dynamicCover?.id != reconciledCover?.id {
            show.dynamicCover = reconciledCover
            if reconciledCover == nil {
                DynamicCoverFaceStore.clear(showID: show.id)
            }
            mutated = true
        }
        if show.dynamicCover?.showID != show.id {
            show.dynamicCover = nil
            DynamicCoverFaceStore.clear(showID: show.id)
            mutated = true
        }
    }
    if mutated { try modelContext.save() }
    return validPaths
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

        let key = ShowAsset.makeUniqueKey(showID: asset.showID, kind: asset.kind)
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
