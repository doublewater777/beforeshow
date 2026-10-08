import SwiftUI

struct TimetableArtistConnectionView: View {
    @Binding var performance: TimetableDraftPerformance
    let linker: TimetableArtistLinker

    @State private var isSearching = false
    @State private var query = ""
    @State private var candidates: [RecognizedArtist] = []
    @State private var isLoading = false
    @State private var failure: ArtistSearchFailureMessage?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            if performance.appleMusicArtistID != nil {
                Button(BSLocalization.text("解除艺人连接"), systemImage: "link.badge.minus") {
                    performance.disconnectArtist()
                }
            } else {
                Button(BSLocalization.text("连接艺人（可选）"), systemImage: "link") {
                    query = performance.artistName
                    isSearching.toggle()
                }
            }
            if isSearching {
                TextField(BSLocalization.text("艺人名称"), text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { attempt += 1 }
                ArtistSearchPicker(
                    options: candidates,
                    isLoading: isLoading,
                    failure: failure,
                    onRecovery: { attempt += 1 },
                    onPick: connect
                )
            }
        }
        .font(BSFont.caption)
        .foregroundStyle(TimetableStyle.mine)
        .buttonStyle(.plain)
        .task(id: "\(isSearching)|\(ArtistNameMatching.normalized(query))|\(attempt)") {
            await search()
        }
    }

    private func connect(_ artist: RecognizedArtist) {
        performance.connectArtist(artist)
        linker.rememberConnectedArtist(artist)
        isSearching = false
    }

    private func search() async {
        candidates = []
        failure = nil
        isLoading = false
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, !query.isEmpty else { return }
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            let found = try await linker.candidates(for: query)
            try Task.checkCancellation()
            candidates = found
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            failure = ArtistSearchFailureMessage(error: error)
            isLoading = false
        }
    }
}
