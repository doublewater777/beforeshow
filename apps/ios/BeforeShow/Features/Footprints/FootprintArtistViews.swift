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
                .foregroundColor(BSColor.Stage.accent)
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
        guard let url = await ArtistAlbumArtworkResolver.shared.artworkURL(forArtistName: name) else { return nil }
        if FootprintAlbumArtworkWriteback.persist(url, artistName: name, showIDs: showIDs, in: shows) {
            try? modelContext.save()
        }
        return url
    }
}

private struct FootprintArtistCoverView: View {
    let item: FootprintArtistArchiveItem
    let shows: [Show]
    let size: CGFloat

    @Environment(\.modelContext) private var modelContext
    @State private var resolvedAlbumArtworkURL: URL?

    var body: some View {
        FootprintArtistAvatarView(
            url: FootprintArtistArtworkPolicy.displayURL(
                avatarURL: item.artworkURL,
                persistedAlbumURL: item.albumArtworkURL,
                resolvedAlbumURL: resolvedAlbumArtworkURL
            ),
            name: item.name,
            size: size
        )
        .task(id: item.id) {
            guard FootprintArtistArtworkPolicy.shouldResolveAlbumArtwork(
                avatarURL: item.artworkURL,
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
    let onArchiveVisibilityChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            footprintExportAwareNavigationLink(isForExport: isForExport) {
                FootprintFilteredShowsView(
                    title: first.name,
                    shows: archive.shows(for: first.showIDs),
                    archive: archive,
                    covers: covers,
                    onDetailVisibilityChange: onArchiveVisibilityChange
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
                            covers: covers,
                            onDetailVisibilityChange: onArchiveVisibilityChange
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
                .foregroundColor(BSColor.Stage.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.35), lineWidth: 0.5))
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(BSLocalization.format("%lld 场", item.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                if let city = latestCity(for: item) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .semibold))
                        Text(BSLocalization.format("最近观看 · %@", city))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Text(BSLocalization.text("最常看").uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(BSColor.Stage.accent)
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
                .foregroundColor(BSColor.Stage.dim)
                .frame(width: 16, alignment: .leading)

            FootprintArtistCoverView(item: item, shows: archive.shows, size: 36)

            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)

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

struct FootprintArtistArchiveView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onDetailVisibilityChange: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = archive.artistArchiveItems
        FootprintArchivePage(
            title: BSLocalization.text("艺人足迹"),
            kicker: "",
            shareCovers: covers,
            extraWarmup: {
                await FootprintCoverExportWarmup.warm(artists: items)
            }
        ) { isForExport in
            artistSummaryCard(items: items)

            HStack(spacing: 6) {
                Text(BSLocalization.text("同场次按最近观看排序"))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                footprintExportAwareNavigationLink(isForExport: isForExport) {
                    FootprintFilteredShowsView(
                        title: item.name,
                        shows: archive.shows(for: item.showIDs),
                        archive: archive,
                        covers: covers,
                        onDetailVisibilityChange: onDetailVisibilityChange
                    )
                } label: {
                    artistArchiveRow(rank: index + 1, item: item, isForExport: isForExport)
                }
            }
        }
    }

    private func artistSummaryCard(items: [FootprintArtistArchiveItem]) -> some View {
        HStack(spacing: 0) {
            summaryMetric("\(items.count)", BSLocalization.text("位艺人"))
            summaryDivider
            summaryMetric("\(archive.shows.count)", BSLocalization.text("场现场"))
            summaryDivider
            VStack(spacing: 4) {
                Text(BSLocalization.text("最常看"))
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                Text(items.first?.name ?? "—")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BSColor.Stage.border))
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func artistArchiveRow(rank: Int, item: FootprintArtistArchiveItem, isForExport: Bool) -> some View {
        HStack(spacing: 12) {
            rankBadge(rank)

            FootprintArtistCoverView(item: item, shows: archive.shows, size: rank == 1 ? 64 : 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.system(size: rank == 1 ? 17 : 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                if rank == 1 {
                    Text("\(BSLocalization.text("最常看")) · #1")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 0.5))
                }
                if let city = latestCity(for: item) {
                    Text(BSLocalization.format("最近观看 · %@", city))
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(BSLocalization.format("%lld 场", item.count))
                .font(.system(size: 13, weight: rank == 1 ? .semibold : .medium))
                .foregroundColor(rank == 1 ? BSColor.Stage.accent : BSColor.Stage.dim)

            footprintRowChevron(isForExport: isForExport, size: 11, weight: .semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, rank == 1 ? 16 : 13)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(rank == 1 ? BSColor.Stage.accent.opacity(0.28) : BSColor.Stage.border, lineWidth: 1)
        )
    }

    private func rankBadge(_ rank: Int) -> some View {
        ZStack {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(BSColor.Stage.accent)
                    .offset(y: -16)
            }
            Text("\(rank)")
                .font(.system(size: rank == 1 ? 22 : 18, weight: .semibold))
                .foregroundColor(rank == 1 ? BSColor.Stage.accent : BSColor.Stage.dim)
        }
        .frame(width: 28, height: rank == 1 ? 44 : 28)
    }

    private func latestCity(for item: FootprintArtistArchiveItem) -> String? {
        guard let showID = item.latestShowID else { return nil }
        return archive.shows(for: [showID]).first.flatMap { FootprintTextNormalizer.nonEmptyTrimmed($0.city) }
    }
}
