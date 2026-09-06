import SwiftUI

struct ListeningArtistDetailView: View {
    @Bindable var room: ListeningRoomCoordinator
    let show: Show
    @Environment(\.dismiss) private var dismiss
    @State private var rematchIndex: Int?
    @State private var query = ""
    @State private var results: [RecognizedArtist] = []
    @State private var isSearching = false
    var body: some View {
        NavigationStack {
            List {
                if room.onlyArtistID != nil {
                    Button(BSLocalization.text("听所有艺人")) { room.filterArtist(nil) }
                }
                ForEach(Array(show.artists.enumerated()), id: \.offset) { index, artist in
                    Section(artist.name) {
                        if let id = artist.appleMusicArtistID {
                            Button(BSLocalization.text("仅听此艺人")) { room.filterArtist(id) }
                            Button(BSLocalization.text(room.excludedArtistIDs.contains(id) ? "恢复此艺人" : "排除此艺人")) {
                                room.excludeArtist(id, excluded: !room.excludedArtistIDs.contains(id))
                            }
                        } else { Text(BSLocalization.text("尚未匹配艺人")).foregroundStyle(BSColor.Stage.muted) }
                        Button(BSLocalization.text("重新匹配")) { rematchIndex = index; query = artist.name }
                    }
                }
                if rematchIndex != nil {
                    Section(BSLocalization.text("匹配艺人")) {
                        TextField(BSLocalization.text("艺人名称"), text: $query)
                        if isSearching { ProgressView() }
                        if !isSearching && results.isEmpty { Text(BSLocalization.text("未找到艺人")).foregroundStyle(BSColor.Stage.muted) }
                        ForEach(results) { artist in
                            Button(artist.canonicalName) {
                                guard let index = rematchIndex else { return }
                                Task { await room.rematch(slotIndex: index, artist: artist); rematchIndex = nil }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BSColor.Stage.background)
            .listRowBackground(BSColor.Stage.surface)
            .foregroundStyle(BSColor.Stage.foreground)
            .navigationTitle(BSLocalization.text("艺人详情"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(BSLocalization.text("完成")) { dismiss() } } }
            .onAppear { if show.artists.isEmpty { rematchIndex = 0 } }
            .task(id: query) {
                guard rematchIndex != nil else { return }
                isSearching = true
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    let matches = try await AppleMusicArtistSearchService().searchArtists(query: query)
                    try Task.checkCancellation()
                    results = matches; isSearching = false
                } catch { if !Task.isCancelled { results = []; isSearching = false } }
            }
        }.tint(BSColor.Stage.accent).presentationDragIndicator(.visible)
    }
}
