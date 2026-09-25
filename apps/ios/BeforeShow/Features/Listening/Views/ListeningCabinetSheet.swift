import SwiftUI

struct ListeningCabinetSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisc: ListeningDisc?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: BSSpacing.md), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    HStack(spacing: BSSpacing.md) {
                        if let artist = room.browsingArtist {
                            ListeningArtistArtwork(url: artist.artworkURL, name: artist.name,
                                                   size: BSListeningTokens.cabinetAvatar)
                                .frame(width: BSListeningTokens.cabinetAvatar, height: BSListeningTokens.cabinetAvatar)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "opticaldisc")
                                .font(BSListeningTokens.stateIconFont)
                                .foregroundStyle(BSColor.Stage.accent)
                                .frame(width: BSListeningTokens.cabinetAvatar, height: BSListeningTokens.cabinetAvatar)
                                .background(BSColor.Stage.surfaceRaised, in: Circle())
                        }
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text(room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑"))
                                .font(BSListeningTokens.stateTitle)
                                .foregroundStyle(BSColor.Stage.foreground)
                            Text(BSLocalization.format("%d 张唱片", room.libraryDiscs.count))
                                .font(BSListeningTokens.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                    }
                    .padding(.vertical, BSSpacing.sm)

                    if room.catalogState == .loading && room.libraryDiscs.isEmpty {
                        ListeningStateMessage(icon: "opticaldisc", title: BSLocalization.text("正在载入唱片…"), isLoading: true)
                    } else if room.libraryDiscs.isEmpty {
                        ListeningStateMessage(icon: "opticaldisc", title: BSLocalization.text("唱片柜暂无唱片"))
                    } else {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: BSSpacing.lg) {
                            ForEach(room.libraryDiscs) { disc in
                                ListeningCabinetGridCell(
                                    disc: disc,
                                    show: room.show,
                                    isPlaying: room.isPlayingDisc(disc),
                                    isLoaded: room.mechanism.disc?.id == disc.id && room.mechanism.position != .stored,
                                    artistName: room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑"),
                                    onSelect: { selectedDisc = disc }
                                )
                            }
                        }
                    }
                }
                .padding(BSSpacing.roomy)
            }
            .background(ListeningSheetBackground())
            .foregroundStyle(BSColor.Stage.foreground)
            .navigationTitle(BSLocalization.text("唱片柜"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BSChromeToolbarCloseButton { dismiss() } }
            .sheet(item: $selectedDisc) { disc in
                ListeningDiscDetailView(room: room, disc: disc, onLoad: { dismiss() })
            }
        }
        .tint(BSColor.Stage.foreground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
