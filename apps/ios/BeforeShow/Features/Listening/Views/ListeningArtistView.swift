import SwiftUI

struct ListeningArtistView: View {
    @Bindable var room: ListeningRoomCoordinator
    let artistID: String
    let returnToPlayer: () -> Void
    @State private var matching = false
    private var slot: Int? { room.show?.artists.firstIndex { $0.appleMusicArtistID == artistID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSSpacing.lg) {
                if let artist = room.artistPresentation(artistID) {
                    ListeningArtistArtwork(url: artist.artworkURL, name: artist.name)
                        .frame(width: 160, height: 160).clipShape(Circle()).frame(maxWidth: .infinity)
                    Text(artist.name).font(.largeTitle.bold())
                    if let tier = artist.tier {
                        Text(BSLocalization.text(tier.localizationKey)).font(.subheadline).foregroundStyle(BSColor.Stage.muted)
                    }
                    Text("\(BSLocalization.text("已熟悉歌曲")) · \(artist.familiarCount)").font(.caption)
                    if !artist.genres.isEmpty { Text(artist.genres.joined(separator: " · ")).font(.caption) }
                    if let editorial = artist.editorialText, !editorial.isEmpty {
                        Text(editorial).font(.body).foregroundStyle(BSColor.Stage.muted)
                    }
                    if (room.show?.artists.compactMap(\.appleMusicArtistID).count ?? 0) > 1 {
                        Button(BSLocalization.text(room.onlyArtistID == artistID ? "回到整场" : "只听这位")) {
                            if room.onlyArtistID == artistID { room.returnToWholeShow() }
                            else { room.filterArtist(artistID) }
                            returnToPlayer()
                        }.frame(minHeight: 44)
                    }
                    Button(BSLocalization.text(room.excludedArtistIDs.contains(artistID) ? "恢复" : "不听这位")) {
                        room.excludeArtist(artistID, excluded: !room.excludedArtistIDs.contains(artistID))
                    }.frame(minHeight: 44)
                    ListeningLibraryView(room: room, artist: artist, returnToPlayer: returnToPlayer)
                } else {
                    Text(BSLocalization.text("正在准备唱片"))
                    Button(BSLocalization.text("重试")) { if let show = room.show { Task { await room.load(show: show, force: true) } } }
                }
                Button(BSLocalization.text("不是这个艺人？")) { matching = true }.frame(minHeight: 44)
            }.padding(BSSpacing.lg)
        }.background(BSColor.Stage.background).foregroundStyle(BSColor.Stage.foreground)
            .sheet(isPresented: $matching) {
                if let slot { ListeningArtistMatchSheet(room: room, slotIndex: slot, query: room.show?.artists[slot].name ?? "") }
            }
    }
}
