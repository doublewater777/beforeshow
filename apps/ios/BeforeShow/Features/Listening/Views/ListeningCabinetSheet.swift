import SwiftUI

private struct ListeningCabinetGridCell: View {
    let disc: ListeningDisc
    let show: Show?
    let isPlaying: Bool
    let artistName: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: BSListeningTokens.shelfItemSpacing) {
                ListeningDiscCover(disc: disc, show: show)
                Text(disc.title)
                    .font(BSListeningTokens.captionMedium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isPlaying ? BSColor.Stage.accent : BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(BSListeningPressStyle(scale: 0.96))
        .accessibilityLabel("\(disc.title), \(artistName)")
        .accessibilityValue(isPlaying ? BSLocalization.text("正在播放") : "")
    }
}

struct ListeningCabinetSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisc: ListeningDisc?

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: BSSpacing.sm),
        count: 3
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    HStack(spacing: BSSpacing.md) {
                        if let artist = room.browsingArtist {
                            ListeningArtistArtwork(url: artist.artworkURL, name: artist.name, size: 48)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                       VStack(alignment: .leading, spacing: BSSpacing.xs) {
                           Text(room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑"))
                               .font(BSListeningTokens.headline)
                               .foregroundStyle(BSColor.Stage.foreground)
                            Text(room.catalogState == .loading && room.libraryDiscs.isEmpty
                                 ? BSLocalization.text("加载中…")
                                 : BSLocalization.format("%d 张唱片", room.libraryDiscs.count))
                               .font(BSListeningTokens.caption)
                               .foregroundStyle(BSColor.Stage.muted)
                       }
                   }
                   .padding(.top, 4)

                    if room.catalogState == .loading && room.libraryDiscs.isEmpty {
                        VStack(spacing: BSSpacing.md) {
                            ProgressView()
                                .tint(BSColor.Stage.accent)
                                .scaleEffect(1.1)
                            Text(BSLocalization.text("正在载入唱片…"))
                                .font(BSListeningTokens.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BSSpacing.xl * 2)
                    } else if room.libraryDiscs.isEmpty {
                       VStack(spacing: BSSpacing.sm) {
                           Image(systemName: "opticaldisc")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(BSColor.Stage.dim)
                            Text(BSLocalization.text("唱片柜暂无唱片"))
                                .font(BSListeningTokens.headline)
                                .foregroundStyle(BSColor.Stage.foreground)
                            Text(BSLocalization.text("匹配演出艺人后，将在此展示专辑与预热碟。"))
                                .font(BSListeningTokens.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BSSpacing.xl * 2)
                    } else {
                        let currentPlayingDiscID = room.isPlaying ? room.mechanism.disc?.id : nil
                        let browsingArtistName = room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑")
                        let currentShow = room.show

                        LazyVGrid(columns: gridColumns, spacing: BSSpacing.lg) {
                            ForEach(room.libraryDiscs) { disc in
                                ListeningCabinetGridCell(
                                    disc: disc,
                                    show: currentShow,
                                    isPlaying: disc.id == currentPlayingDiscID,
                                    artistName: browsingArtistName,
                                    onSelect: { selectedDisc = disc }
                                )
                            }
                        }
                    }
               }
               .padding(BSSpacing.roomy)
            }
            .background(BSColor.Stage.background)
            .foregroundStyle(BSColor.Stage.foreground)
           .navigationTitle(BSLocalization.text("唱片柜"))
           .navigationBarTitleDisplayMode(.inline)
           .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
           }
           .sheet(item: $selectedDisc) { disc in
                ListeningDiscDetailView(room: room, disc: disc, onLoad: { dismiss() })
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
