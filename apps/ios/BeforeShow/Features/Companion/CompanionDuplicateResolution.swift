import Foundation
import SwiftData
import SwiftUI

struct CompanionDuplicateResolution: Identifiable {
    let importedShow: Show
    let candidates: [Show]

    var id: UUID { importedShow.id }
}

enum CompanionDuplicateResolutionStore {
    private static let ignoredSessionKeysKey = "companion.duplicate-resolution.ignored.v1"

    static func isIgnored(
        sessionRecordName: String,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        Set(userDefaults.stringArray(forKey: ignoredSessionKeysKey) ?? [])
            .contains(sessionRecordName)
    }

    static func ignore(
        sessionRecordName: String,
        userDefaults: UserDefaults = .standard
    ) {
        var values = Set(userDefaults.stringArray(forKey: ignoredSessionKeysKey) ?? [])
        values.insert(sessionRecordName)
        userDefaults.set(values.sorted(), forKey: ignoredSessionKeysKey)
    }
}

@MainActor
enum CompanionDuplicateResolutionFinder {
    static func first(
        in shows: [Show],
        userDefaults: UserDefaults = .standard
    ) -> CompanionDuplicateResolution? {
        for imported in shows where imported.creationOrigin == .companionImport {
            guard let sessionRecordName = imported.companionCloudRecordName,
                  !CompanionDuplicateResolutionStore.isIgnored(
                    sessionRecordName: sessionRecordName,
                    userDefaults: userDefaults
                  ) else {
                continue
            }

            let candidates = shows.filter { candidate in
                guard candidate.id != imported.id,
                      candidate.companionCloudRecordName == nil else {
                    return false
                }
                return ShowDuplicateMatcher.isDuplicate(imported, candidate)
            }

            // A single match is already merged by the importer. A persisted imported copy
            // with multiple matches means the importer deliberately avoided guessing.
            if candidates.count > 1 {
                return CompanionDuplicateResolution(
                    importedShow: imported,
                    candidates: candidates.sorted { $0.effectiveDate > $1.effectiveDate }
                )
            }
        }
        return nil
    }
}

@MainActor
enum CompanionDuplicateMerger {
    static func merge(
        imported: Show,
        into target: Show,
        in modelContext: ModelContext
    ) throws {
        guard imported.id != target.id,
              imported.companionCloudRecordName != nil,
              target.companionCloudRecordName == nil else {
            throw CompanionSharingError.conflict
        }

        fillMissingShowData(from: imported, into: target)
        target.applyCompanionState(
            status: imported.companionStatus,
            names: imported.companionNames
        )
        copyCloudLinkage(from: imported, into: target)

        // If the temporary imported copy became Current because there was no previous
        // selection, keep Current pointing at the surviving local Show after the merge.
        let selectionStore = CurrentShowSelectionStore(modelContext: modelContext)
        if let selection = try? selectionStore.canonicalSelection(),
           selection?.selectedShowID == imported.id {
            _ = try? selectionStore.select(showID: target.id)
        }

        modelContext.delete(imported)
        try modelContext.save()
    }

    private static func fillMissingShowData(from imported: Show, into target: Show) {
        if target.endDate == nil { target.endDate = imported.endDate }
        if target.endTime == nil { target.endTime = imported.endTime }
        if target.timeZoneSecondsFromGMT == nil { target.timeZoneSecondsFromGMT = imported.timeZoneSecondsFromGMT }
        if target.endTimeZoneSecondsFromGMT == nil { target.endTimeZoneSecondsFromGMT = imported.endTimeZoneSecondsFromGMT }
        if nonEmpty(target.timeZoneIdentifier) == nil { target.timeZoneIdentifier = nonEmpty(imported.timeZoneIdentifier) }
        if nonEmpty(target.endTimeZoneIdentifier) == nil { target.endTimeZoneIdentifier = nonEmpty(imported.endTimeZoneIdentifier) }
        if nonEmpty(target.city) == nil { target.city = nonEmpty(imported.city) }
        if nonEmpty(target.venueName) == nil { target.venueName = nonEmpty(imported.venueName) }
        if nonEmpty(target.venueAddress) == nil { target.venueAddress = nonEmpty(imported.venueAddress) }
        if nonEmpty(target.coverImageURL) == nil { target.coverImageURL = portableCover(imported.coverImageURL) }
        target.artists = mergeArtists(local: target.artists, incoming: imported.artists)

        guard target.endedAt == nil else { return }
        switch imported.changeStatus {
        case .canceled:
            if target.changeStatus != .canceled { target.markCanceled() }
        case .postponed:
            if target.changeStatus == .scheduled {
                target.markPostponed(newDate: imported.postponedDate)
            }
        case .scheduled:
            break
        }
    }

    private static func copyCloudLinkage(from source: Show, into target: Show) {
        target.companionCloudRecordName = source.companionCloudRecordName
        target.companionCloudZoneName = source.companionCloudZoneName
        target.companionCloudOwnerName = source.companionCloudOwnerName
        target.companionShareRecordName = source.companionShareRecordName
        target.companionShareZoneName = source.companionShareZoneName
        target.companionShareOwnerName = source.companionShareOwnerName
        target.companionIsOwner = source.companionIsOwner
    }

    private static func mergeArtists(local: [ArtistSlot], incoming: [ArtistSlot]) -> [ArtistSlot] {
        var result = local
        for artist in incoming {
            if let index = result.firstIndex(where: { sameArtist($0, artist) }) {
                var existing = result[index]
                if nonEmpty(existing.avatarURL) == nil { existing.avatarURL = nonEmpty(artist.avatarURL) }
                if nonEmpty(existing.appleMusicURL) == nil { existing.appleMusicURL = nonEmpty(artist.appleMusicURL) }
                if nonEmpty(existing.appleMusicArtistID) == nil { existing.appleMusicArtistID = nonEmpty(artist.appleMusicArtistID) }
                if nonEmpty(existing.albumArtworkURL) == nil { existing.albumArtworkURL = nonEmpty(artist.albumArtworkURL) }
                result[index] = existing
            } else {
                result.append(artist)
            }
        }
        return result
    }

    private static func sameArtist(_ lhs: ArtistSlot, _ rhs: ArtistSlot) -> Bool {
        if let lhsID = nonEmpty(lhs.appleMusicArtistID),
           let rhsID = nonEmpty(rhs.appleMusicArtistID) {
            return lhsID == rhsID
        }
        return normalize(lhs.name) == normalize(rhs.name)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func portableCover(_ raw: String?) -> String? {
        guard let raw = nonEmpty(raw),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return raw
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CompanionDuplicateResolutionSheet: View {
    let resolution: CompanionDuplicateResolution
    let onMerge: (Show) -> Void
    let onKeepSeparate: () -> Void

    private let formatter = ShowDisplayFormatter()

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: BSSpacing.lg) {
                    BSStageSheetHeader(
                        icon: "rectangle.2.swap",
                        title: BSLocalization.text("这场可能已经存在"),
                        subtitle: BSLocalization.text("你本地有多场相似记录。选择正确的一场合并同行关系，或保留为另一场现场。")
                    )

                    VStack(spacing: BSSpacing.sm) {
                        ForEach(resolution.candidates) { candidate in
                            Button {
                                onMerge(candidate)
                            } label: {
                                candidateRow(candidate)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        onKeepSeparate()
                    } label: {
                        Text(BSLocalization.text("这是另一场，单独保留"))
                            .font(BSFont.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func candidateRow(_ show: Show) -> some View {
        HStack(spacing: BSSpacing.compact) {
            VStack(alignment: .leading, spacing: 5) {
                Text(show.name)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(2)
                Text(formatter.dateText(for: show))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                if let venue = nonEmpty(show.venueName) {
                    Text(venue)
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(BSLocalization.text("合并"))
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Stage.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
