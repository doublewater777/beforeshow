import SwiftUI

struct ListeningCabinetSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisc: ListeningDisc?
    @State private var searchText = ""
    @State private var showsArtistDetail = false

    private var artists: [ListeningArtistPresentation] {
        room.cabinetArtists
    }

    private var isSingleArtist: Bool {
        artists.count <= 1
    }

    private var warmUpDisc: ListeningDisc? {
        room.warmUpDisc
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        // Header Show Card
                        if let show = room.show {
                            showOverviewCard(show)
                        }

                        // Artist fast index pills (for 3+ artists)
                        if artists.count >= 3 && searchText.isEmpty {
                            artistQuickIndex(scroll)
                        }

                    if !searchText.isEmpty {
                        // Search flat results
                        searchResultsView
                    } else {
                        // Shelf 1: 本场预热碟 (Live Warm Up Disc)
                        if let warmUp = warmUpDisc {
                            warmUpShelfSection(warmUp)
                        }

                        // Shelves: One row per artist
                        ForEach(artists) { artist in
                            artistShelfSection(artist)
                                .id("artist-\(artist.id)")
                        }
                    }
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.vertical, BSSpacing.md)
                }
            }
            .background(BSColor.Stage.background)
            .foregroundStyle(BSColor.Stage.foreground)
            .searchable(text: $searchText, prompt: BSLocalization.text("搜索唱片或艺人"))
            .navigationTitle(BSLocalization.text("唱片柜"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(BSLocalization.text("完成")) { dismiss() }
                        .foregroundStyle(BSColor.Stage.accent)
                }
            }
            .sheet(item: $selectedDisc) { disc in
                ListeningDiscDetailView(room: room, disc: disc, onLoad: { dismiss() })
            }
            .sheet(isPresented: $showsArtistDetail) {
                if let show = room.show {
                    ListeningArtistDetailView(room: room, show: show)
                }
            }
        }
        .tint(BSColor.Stage.accent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Show Overview Card

    private func showOverviewCard(_ show: Show) -> some View {
        Button {
            showsArtistDetail = true
        } label: {
            HStack(spacing: BSSpacing.md) {
                // Show poster / artwork thumbnail
                ListeningArtwork(url: warmUpDisc?.artworkURL, title: show.name)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.sm).stroke(BSColor.Stage.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(show.name)
                        .font(BSFont.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(1)

                    let artistCount = max(1, artists.count)
                    let totalDiscs = (warmUpDisc != nil ? 1 : 0) + artists.reduce(0) { $0 + max(1, $1.albums.count) }

                    Text("\(artistCount) \(BSLocalization.text("位艺人")) · \(totalDiscs) \(BSLocalization.text("张唱片"))")
                        .font(BSFont.caption)
                        .foregroundStyle(BSColor.Stage.dim)

                    let artistNames = artists.map(\.name).joined(separator: " / ")
                    if !artistNames.isEmpty {
                        Text(artistNames)
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.muted)
            }
            .padding(BSSpacing.md)
            .background(BSColor.Stage.surfaceRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("艺人详情"))
    }

    // MARK: - Artist Quick Index

    private func artistQuickIndex(_ scroll: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.xs) {
                ForEach(artists) { artist in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scroll.scrollTo("artist-\(artist.id)", anchor: .top)
                        }
                    } label: {
                        Text(artist.name)
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.foreground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(BSColor.Stage.surfaceRaised, in: Capsule())
                            .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Warm Up Shelf Section

    private func warmUpShelfSection(_ warmUp: ListeningDisc) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            shelfHeader(title: BSLocalization.text("本场预热碟"), countText: "1 \(BSLocalization.text("张唱片"))")

            JewelCaseShelf {
                Button { selectedDisc = warmUp } label: {
                    ListeningJewelCase(
                        disc: warmUp,
                        subtitle: artists.map(\.name).joined(separator: " / "),
                        isLoaded: room.mechanism.disc?.id == warmUp.id && room.mechanism.position != .stored
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Artist Shelf Section

    private func artistShelfSection(_ artist: ListeningArtistPresentation) -> some View {
        let discs = artist.albums.isEmpty
            ? [ListeningDisc(id: "artist-\(artist.id)", title: artist.name, artworkURL: artist.artworkURL, tracks: artist.all)]
            : artist.albums

        return VStack(alignment: .leading, spacing: 6) {
            if !isSingleArtist {
                shelfHeader(title: artist.name, countText: "\(discs.count) \(BSLocalization.text("张唱片"))")
            }

            JewelCaseShelf {
                ForEach(discs) { disc in
                    Button { selectedDisc = disc } label: {
                        ListeningJewelCase(
                            disc: disc,
                            subtitle: artist.name,
                            isLoaded: room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(disc.title)
                }
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allDiscs: [(disc: ListeningDisc, artist: String)] = {
            var items: [(ListeningDisc, String)] = []
            if let warmUp = warmUpDisc {
                items.append((warmUp, BSLocalization.text("现场预热")))
            }
            for artist in artists {
                let discs = artist.albums.isEmpty
                    ? [ListeningDisc(id: "artist-\(artist.id)", title: artist.name, artworkURL: artist.artworkURL, tracks: artist.all)]
                    : artist.albums
                for d in discs {
                    items.append((d, artist.name))
                }
            }
            return items
        }()

        let filtered = allDiscs.filter {
            $0.disc.title.localizedCaseInsensitiveContains(term) || $0.artist.localizedCaseInsensitiveContains(term)
        }

        if filtered.isEmpty {
            return AnyView(
                VStack(spacing: BSSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(BSColor.Stage.muted)
                    Text(BSLocalization.text("未找到相关唱片或艺人"))
                        .font(BSFont.body)
                        .foregroundStyle(BSColor.Stage.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            )
        } else {
            return AnyView(
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(filtered, id: \.disc.id) { item in
                        Button { selectedDisc = item.disc } label: {
                            ListeningJewelCase(
                                disc: item.disc,
                                subtitle: item.artist,
                                isLoaded: room.mechanism.disc?.id == item.disc.id && room.mechanism.position != .stored
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            )
        }
    }

    // MARK: - Helpers

    private func shelfHeader(title: String, countText: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(BSColor.Stage.accent)
                    .frame(width: 3, height: 13)
                    .clipShape(Capsule())

                Text(title)
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
            }

            Spacer()

            Text(countText)
                .font(BSFont.V3.caption)
                .foregroundStyle(BSColor.Stage.dim)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Translucent Jewel Case Shelf (透明实体亚克力/玻璃唱片架)

struct JewelCaseShelf<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 14, content: content)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 12)
        }
        .background {
            ZStack(alignment: .bottom) {
                // Shelf back wall depth shadow
                LinearGradient(
                    colors: [Color.black.opacity(0.4), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Bottom shelf glass/acrylic ledge
                VStack(spacing: 0) {
                    // Glass bevel highlight line
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.1), Color.white.opacity(0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)

                    // Glass thickness body
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 10)
                        .background(.ultraThinMaterial)

                    // Glass bottom shadow
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.sm)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Physical CD Jewel Case (透明 CD 盒外壳)

struct ListeningJewelCase: View {
    let disc: ListeningDisc
    let subtitle: String?
    let isLoaded: Bool

    private let caseWidth: CGFloat = 106
    private let caseHeight: CGFloat = 106

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Jewel case frame
            ZStack {
                // Background tray inlay artwork
                ListeningArtwork(url: disc.artworkURL, title: disc.title)
                    .frame(width: caseWidth - 8, height: caseHeight - 4)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                    .offset(x: 2)

                // CD Spine edge (left hinge)
                HStack {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.black.opacity(0.6),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 5)
                    Spacer()
                }

                // Front transparent jewel case plastic cover sheen
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.25), location: 0.0),
                        .init(color: Color.clear, location: 0.28),
                        .init(color: Color.white.opacity(0.08), location: 0.70),
                        .init(color: Color.clear, location: 0.75),
                        .init(color: Color.black.opacity(0.18), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Loaded indicator badge
                if isLoaded {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(BSColor.Stage.accent)
                                .frame(width: 8, height: 8)
                                .shadow(color: BSColor.Stage.accent, radius: 4)
                                .padding(5)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: caseWidth, height: caseHeight)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            // Realistic plastic jewel case border with highlights
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.55), location: 0.0),
                                .init(color: Color.white.opacity(0.15), location: 0.4),
                                .init(color: Color.black.opacity(0.40), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            // Front tray retention tabs on the right edge
            .overlay(
                VStack(spacing: 24) {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 2, height: 8)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 2, height: 8)
                }
                .padding(.trailing, 2),
                alignment: .trailing
            )
            // Jewel case drop shadow on shelf
            .shadow(color: Color.black.opacity(0.6), radius: 6, x: 2, y: 4)

            // Titles
            VStack(alignment: .leading, spacing: 2) {
                Text(disc.title)
                    .font(BSFont.V3.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(BSColor.Stage.foreground)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }
            .frame(width: caseWidth, alignment: .leading)
        }
    }
}
