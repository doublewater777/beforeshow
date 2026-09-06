import SwiftUI

struct ListeningArtistDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @State private var matching: Int?
    @State private var artistID: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if room.onlyArtistID != nil {
                    Button(BSLocalization.text("回到整场")) { room.returnToWholeShow(); dismiss() }
                }
                ForEach(Array(show.artists.enumerated()), id: \.offset) { index, artist in
                    HStack(spacing: BSSpacing.md) {
                        ListeningArtistArtwork(url: artist.avatarURL.flatMap(URL.init(string:)), name: artist.name)
                            .frame(width: 52, height: 52).clipShape(Circle())
                        Text(artist.name).font(.headline)
                        Spacer()
                        if let id = artist.appleMusicArtistID {
                            Button { artistID = id } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                                .accessibilityLabel(artist.name)
                        } else {
                            Button(BSLocalization.text("连接艺人")) { matching = index }.frame(minHeight: 44)
                        }
                    }
                }
                if show.artists.isEmpty {
                    Button(BSLocalization.text("连接艺人")) { matching = 0 }
                }
            }.scrollContentBackground(.hidden).background(BSColor.Stage.background)
                .navigationTitle(BSLocalization.text("艺人详情"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(BSLocalization.text("完成")) { dismiss() } } }
                .sheet(isPresented: Binding(get: { matching != nil }, set: { if !$0 { matching = nil } })) {
                    if let matching { ListeningArtistMatchSheet(room: room, slotIndex: matching, query: show.artists.indices.contains(matching) ? show.artists[matching].name : "") }
                }
                .navigationDestination(isPresented: Binding(get: { artistID != nil }, set: { if !$0 { artistID = nil } })) {
                    if let artistID { ListeningArtistView(room: room, artistID: artistID, returnToPlayer: { dismiss() }) }
                }
        }.tint(BSColor.Stage.foreground).presentationDragIndicator(.visible)
    }
}
