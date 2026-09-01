import Foundation

enum FootprintCoverBadge: String, Equatable {
    case memory = "MEMORY"
    case keepsake = "KEEPSAKE"
    case archive = "ARCHIVE"

    var localizedTitle: String {
        switch self {
        case .memory: return BSLocalization.text("回忆")
        case .keepsake: return BSLocalization.text("留念")
        case .archive: return BSLocalization.text("归档")
        }
    }
}

enum FootprintCoverSource: Equatable {
    case local(URL)
    case remote(URL)
    case archive
}

struct FootprintCover: Identifiable, Equatable {
    let showID: UUID
    let source: FootprintCoverSource
    let badge: FootprintCoverBadge
    let ordinal: Int
    let variant: Int
    /// 记忆封面对应的原始媒体是否为视频;仅 badge == .memory 时有意义。
    var isVideoMemory = false

    var id: UUID { showID }
}

enum FootprintArchiveCoverLayout {
    static func variant(for id: UUID) -> Int {
        let value = id.uuidString.utf8.reduce(UInt64(5381)) { hash, byte in
            (hash &* 33) &+ UInt64(byte)
        }
        return Int(value % 4)
    }
}

@MainActor
enum FootprintCoverResolver {
    static func resolve(
        shows: [Show],
        fragments: [MemoryFragment],
        assets: [ShowAsset]
    ) -> [UUID: FootprintCover] {
        let ordered = FootprintArchiveRankingBuilder.chronological(shows)
        let ordinals = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset + 1) })
        let fragmentsByShow = Dictionary(grouping: fragments, by: \.showID)
        let assetsByShow = Dictionary(grouping: assets, by: \.showID)

        return Dictionary(uniqueKeysWithValues: shows.map { show in
            let fragments = fragmentsByShow[show.id] ?? []
            let assets = assetsByShow[show.id] ?? []
            let cover = resolve(
                show: show,
                fragments: fragments,
                assets: assets,
                ordinal: ordinals[show.id] ?? 1
            )
            return (show.id, cover)
        })
    }

    private static func resolve(
        show: Show,
        fragments: [MemoryFragment],
        assets: [ShowAsset],
        ordinal: Int
    ) -> FootprintCover {
        if let rawURL = show.coverImageURL,
           let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FootprintCover(
                showID: show.id,
                source: url.isFileURL ? .local(url) : .remote(url),
                badge: .archive,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        let memoryItems = fragments
            .flatMap(\.orderedMediaItems)
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        if let memory = memoryItems.first(where: { $0.kind == .photo || $0.kind == .video }) {
            let path = memory.thumbnailRelativePath ?? memory.relativePath
            return FootprintCover(
                showID: show.id,
                source: .local(MemoryMediaLocation.applicationSupport().url(for: path)),
                badge: .memory,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id),
                isVideoMemory: memory.kind == .video
            )
        }

        if let ticket = assets.first(where: { $0.kind == .ticket }),
           let location = try? ShowAssetMediaLocation.applicationSupport() {
            return FootprintCover(
                showID: show.id,
                source: .local(location.rootDirectory.appendingPathComponent(ticket.relativePath)),
                badge: .keepsake,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        if let posterPath = show.dynamicCover?.posterRelativePath,
           !posterPath.isEmpty,
           let location = try? DynamicCoverMediaLocation.applicationSupport() {
            return FootprintCover(
                showID: show.id,
                source: .local(location.url(for: posterPath)),
                badge: .archive,
                ordinal: ordinal,
                variant: FootprintArchiveCoverLayout.variant(for: show.id)
            )
        }

        return FootprintCover(
            showID: show.id,
            source: .archive,
            badge: .archive,
            ordinal: ordinal,
            variant: FootprintArchiveCoverLayout.variant(for: show.id)
        )
    }
}
