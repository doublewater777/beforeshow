import SwiftData
import SwiftUI

enum FootprintArtistArtworkPolicy {
    static func displayURL(
        avatarURL: URL?,
        persistedAlbumURL: URL?,
        resolvedAlbumURL: URL?
    ) -> URL? {
        avatarURL ?? persistedAlbumURL ?? resolvedAlbumURL
    }

    static func shouldResolveAlbumArtwork(
        avatarURL: URL?,
        persistedAlbumURL: URL?
    ) -> Bool {
        avatarURL == nil && persistedAlbumURL == nil
    }
}

/// Top-artist card; owns its artwork-resolution state so
/// `FootprintDashboardSections` stays a pure value type.
private struct FootprintArtistAvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                if let cached = ShowCoverImageCache.shared.memoryImage(for: url) {
                    Image(uiImage: cached)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            initialFallback
                        }
                    }
                }
            } else {
                initialFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.18), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(6, size * 0.18), style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var initialFallback: some View {
        ZStack {
            LinearGradient(
                colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(BSColor.Stage.accent)
        }
    }
}

@MainActor
private enum FootprintArtistAlbumArtworkLoader {
    static func resolveIfNeeded(
        name: String,
        existingURL: URL?,
        showIDs: [UUID],
        in shows: [Show],
        modelContext: ModelContext
    ) async -> URL? {
        if let existingURL { return existingURL }
        let identities = Set(shows.filter { showIDs.contains($0.id) }
            .flatMap(\.artists)
            .filter { ArtistNameMatching.normalized($0.name) == ArtistNameMatching.normalized(name) }
            .compactMap { AppleMusicArtistIdentity.artistID(for: $0) })
        guard identities.count <= 1 else { return nil }
        let artistID = identities.first
        guard let url = await ArtistAlbumArtworkResolver.shared.artworkURL(forArtistName: name, artistID: artistID),
              !Task.isCancelled else { return nil }
        if FootprintAlbumArtworkWriteback.persist(url, artistName: name, artistID: artistID, showIDs: showIDs, in: shows) {
            try? modelContext.save()
            return url
        }
        return nil
    }
}

private struct FootprintArtistCoverView: View {
    let item: FootprintArtistArchiveItem
    let shows: [Show]
    let size: CGFloat

    @Environment(\.modelContext) private var modelContext
    @State private var resolvedAlbumArtworkURL: URL?

    private var avatarURL: URL? {
        ArtistAvatarResolver.shared.displayURL(artistID: item.artistID, stored: item.artworkURL?.absoluteString)
    }

    var body: some View {
        FootprintArtistAvatarView(
            url: FootprintArtistArtworkPolicy.displayURL(
                avatarURL: avatarURL,
                persistedAlbumURL: item.albumArtworkURL,
                resolvedAlbumURL: resolvedAlbumArtworkURL
            ),
            name: item.name,
            size: size
        )
        .task(id: item.id) {
            guard FootprintArtistArtworkPolicy.shouldResolveAlbumArtwork(
                avatarURL: avatarURL,
                persistedAlbumURL: item.albumArtworkURL
            ) else {
                resolvedAlbumArtworkURL = nil
                return
            }
            resolvedAlbumArtworkURL = await FootprintArtistAlbumArtworkLoader.resolveIfNeeded(
                name: item.name,
                existingURL: item.albumArtworkURL,
                showIDs: item.showIDs,
                in: shows,
                modelContext: modelContext
            )
        }
    }
}

struct FootprintTopArtistCard: View {
    let items: [FootprintArtistArchiveItem]
    let first: FootprintArtistArchiveItem
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let isForExport: Bool

    var body: some View {
        VStack(spacing: 0) {
            footprintExportAwareNavigationLink(isForExport: isForExport) {
                FootprintFilteredShowsView(
                    title: first.name,
                    shows: archive.shows(for: first.showIDs),
                    archive: archive,
                    covers: covers
                )
            } label: {
                artistHeroRow(first, showsChevron: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 14)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.dropFirst().prefix(2).enumerated()), id: \.element.id) { offset, item in
                    footprintExportAwareNavigationLink(isForExport: isForExport) {
                        FootprintFilteredShowsView(
                            title: item.name,
                            shows: archive.shows(for: item.showIDs),
                            archive: archive,
                            covers: covers
                        )
                    } label: {
                        artistRankRow(rank: offset + 2, item: item, showsChevron: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Color.white.opacity(0.045)).frame(height: 1)
                            }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private func artistHeroRow(_ item: FootprintArtistArchiveItem, showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .topLeading) {
                FootprintArtistCoverView(item: item, shows: archive.shows, size: 108)
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("#1")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                }
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 0.5))
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(BSLocalization.format("%lld 场", item.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent)
                if let city = latestCity(for: item) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .semibold))
                        Text(BSLocalization.format("最近观看 · %@", city))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(BSColor.Stage.dim)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(BSLocalization.text("最常看").uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(BSColor.Stage.accent)
                if showsChevron {
                    footprintRowChevron(isForExport: isForExport, size: 12, weight: .semibold)
                }
            }
        }
    }

    private func artistRankRow(rank: Int, item: FootprintArtistArchiveItem, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BSColor.Stage.dim)
                .frame(width: 16, alignment: .leading)

            FootprintArtistCoverView(item: item, shows: archive.shows, size: 36)

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BSColor.Stage.dim)

            if showsChevron {
                footprintRowChevron(isForExport: isForExport, size: 11, weight: .semibold)
            }
        }
    }

    private func latestCity(for item: FootprintArtistArchiveItem) -> String? {
        guard let showID = item.latestShowID else { return nil }
        return archive.shows(for: [showID]).first.flatMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
    }
}
