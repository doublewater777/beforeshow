import SwiftUI

struct ListeningLineupList: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var artists: [ListeningBrowseArtist] {
        var seen = Set<String>()
        return room.browseArtists.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ListeningLineupSection.sections(artists, query: query)) { section in
                    Section(section.id) {
                        ForEach(section.artists) { artist in
                            row(artist)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BSColor.Stage.background.ignoresSafeArea())
            .searchable(text: $query, prompt: ListeningCopy.text("搜索艺人"))
            .navigationTitle(ListeningCopy.text("全部艺人"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                ListeningArtistPage(room: room, artistID: id, show: show)
            }
            .toolbar {
                BSChromeToolbarCloseButton { dismiss() }
            }
        }
        .foregroundStyle(BSColor.Stage.foreground)
    }

    @ViewBuilder
    private func row(_ artist: ListeningBrowseArtist) -> some View {
        let label = HStack(spacing: BSSpacing.compact) {
            ListeningArtwork(url: artist.artworkURL, title: artist.name)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            Text(artist.name)
                .foregroundStyle(artist.isConnected ? BSColor.Stage.foreground : BSColor.Stage.muted)
            Spacer()
        }
        if artist.isConnected {
            NavigationLink(value: artist.id) { label }
                .listRowBackground(Color.clear)
        } else {
            // Matching happens inside the list, so the list never hands over to another sheet.
            NavigationLink {
                ListeningArtistMatchSheet(room: room, slotIndex: artist.slotIndex, query: artist.name, isPushed: true)
            } label: { label }
                .listRowBackground(Color.clear)
        }
    }
}
