import SwiftUI

struct TimetableArtistConnectionView: View {
    @Binding var performance: TimetableDraftPerformance
    let linker: TimetableArtistLinker
    let onRevealSearch: () -> Void

    @State private var candidates: [RecognizedArtist] = []
    @State private var isLoading = false
    @State private var failure: ArtistSearchFailureMessage?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            if performance.appleMusicArtistID != nil {
                Label(BSLocalization.format("已连接：%@", performance.artistName), systemImage: "link")
                    .foregroundStyle(TimetableStyle.muted)
            } else if !performance.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ArtistSearchPicker(
                    options: candidates,
                    isLoading: isLoading,
                    failure: failure,
                    onRecovery: { attempt += 1 },
                    onPick: connect
                )
                .id("artist-search-\(performance.id)")
            }
        }
        .font(BSFont.caption)
        .foregroundStyle(TimetableStyle.mine)
        .buttonStyle(.plain)
        .task(id: "\(performance.artistName)|\(performance.appleMusicArtistID ?? "")|\(attempt)") {
            await search()
        }
        .task(id: candidates.count) {
            guard !candidates.isEmpty, performance.appleMusicArtistID == nil else { return }
            await Task.yield()
            onRevealSearch()
        }
    }

    private func connect(_ artist: RecognizedArtist) {
        performance.connectArtist(artist)
        linker.rememberConnectedArtist(artist)
    }

    private func search() async {
        candidates = []
        failure = nil
        isLoading = false
        let name = performance.artistName
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard performance.appleMusicArtistID == nil, !query.isEmpty else { return }
        candidates = linker.savedCandidates(for: query)
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            let found = try await linker.candidates(for: query, includingRemote: true)
            try Task.checkCancellation()
            guard performance.artistName == name, performance.appleMusicArtistID == nil else { return }
            candidates = found
            isLoading = false
            if let match = ArtistNameMatching.uniqueConfidentMatch(for: query, among: found) {
                connect(match)
            }
        } catch {
            guard !Task.isCancelled else { return }
            failure = ArtistSearchFailureMessage(error: error)
            isLoading = false
        }
    }
}
