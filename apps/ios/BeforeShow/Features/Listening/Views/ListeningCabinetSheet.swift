import SwiftUI

struct ListeningCabinetSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisc: ListeningDisc?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    HStack(spacing: BSSpacing.md) {
                        if let artist = room.browsingArtist {
                            ListeningArtistArtwork(url: artist.artworkURL, name: artist.name)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                       VStack(alignment: .leading, spacing: 3) {
                           Text(room.browsingArtist?.name ?? BSLocalization.text("BeforeShow 热门合辑"))
                               .font(BSFont.V3.title3)
                               .bold()
                               .foregroundStyle(BSColor.Stage.foreground)
                            Text(room.catalogState == .loading && room.libraryDiscs.isEmpty
                                 ? BSLocalization.text("加载中…")
                                 : BSLocalization.format("%d 张唱片", room.libraryDiscs.count))
                               .font(BSFont.caption)
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
                                .font(BSFont.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 72)
                    } else if room.libraryDiscs.isEmpty {
                       VStack(spacing: BSSpacing.sm) {
                           Image(systemName: "opticaldisc")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(BSColor.Stage.dim)
                            Text(BSLocalization.text("唱片柜暂无唱片"))
                                .font(BSFont.headline)
                                .foregroundStyle(BSColor.Stage.foreground)
                            Text(BSLocalization.text("匹配演出艺人后，将在此展示专辑与预热碟。"))
                                .font(BSFont.caption)
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 72)
                    } else {
                   LazyVGrid(columns: [GridItem(.flexible(), spacing: BSSpacing.md), GridItem(.flexible(), spacing: BSSpacing.md)], spacing: BSSpacing.lg) {
                       ForEach(room.libraryDiscs) { disc in
                           Button { selectedDisc = disc } label: {
                               VStack(alignment: .leading, spacing: 6) {
                                   ListeningDiscCover(disc: disc, show: room.show)
                                   Text(disc.title)
                                       .font(BSListeningTokens.captionMedium)
                                       .lineLimit(2)
                                       .foregroundStyle(room.isPlayingDisc(disc) ? BSColor.Stage.accent : BSColor.Stage.foreground)
                                       .frame(maxWidth: .infinity, alignment: .leading)
                               }
                           }
                           .buttonStyle(BSListeningPressStyle(scale: 0.96))
                           .accessibilityLabel("\(disc.title), \(room.browsingArtist?.name ?? "BeforeShow")")
                           .accessibilityValue(ListeningSleeveMarks.accessibilityText(room: room, disc: disc))
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
