import SwiftUI

struct ListeningArtistMatchSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    let slotIndex: Int
    @State var query: String
    @State private var candidates: [RecognizedArtist] = []
    @State private var selected: RecognizedArtist?
    @State private var searching = false
    @State private var failed = false
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                TextField(BSLocalization.text("艺人名称"), text: $query)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                if let error = room.errorText { Text(error).foregroundStyle(BSColor.Stage.muted) }
                if searching { ProgressView() }
                if failed { Text(BSLocalization.text("暂时无法搜索")) }
                if !searching && !failed && candidates.isEmpty { Text(BSLocalization.text("未找到艺人")) }
                ForEach(candidates) { candidate in
                    Button { selected = candidate } label: {
                        HStack {
                            ListeningArtistArtwork(url: candidate.avatarURL, name: candidate.canonicalName).frame(width: 48, height: 48).clipShape(Circle())
                            Text(candidate.canonicalName).font(.body)
                            Spacer()
                            if selected?.id == candidate.id { Image(systemName: "checkmark.circle.fill") }
                        }.frame(minHeight: 44)
                    }.accessibilityAddTraits(selected?.id == candidate.id ? .isSelected : [])
                }
            }.scrollContentBackground(.hidden).background(BSColor.Stage.background)
                .navigationTitle(BSLocalization.text("连接艺人"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(BSLocalization.text("取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(BSLocalization.text("确认")) {
                            guard let selected else { return }
                            confirming = true
                            Task {
                                room.errorText = nil
                                await room.rematch(slotIndex: slotIndex, artist: selected)
                                confirming = false
                                if room.errorText == nil { dismiss() }
                            }
                        }.disabled(selected == nil || confirming)
                    }
                }
                .task(id: query) {
                    selected = nil; candidates = []; searching = true; failed = false
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                        let result = try await AppleMusicArtistSearchService().searchArtists(query: query)
                        try Task.checkCancellation()
                        candidates = result; searching = false
                    } catch { if !Task.isCancelled { searching = false; failed = true } }
                }
        }.tint(BSColor.Stage.foreground)
    }
}
