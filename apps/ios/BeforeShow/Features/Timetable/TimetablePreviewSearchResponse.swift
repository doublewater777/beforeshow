import Foundation

struct TimetablePreviewSearchResponse: Decodable {
    let results: [Track]

    struct Track: Decodable {
        let kind: String?
        let trackId: Int?
        let artistId: Int?
        let artistName: String?
        let trackName: String?
        let previewUrl: URL?
    }

    func preview(artistName: String, artistID: String?) -> ListeningPlaybackItem? {
        let songs = results.filter { $0.kind == "song" }
        let matching: [Track]
        if let artistID {
            matching = songs.filter { $0.artistId.map(String.init) == artistID }
        } else {
            let name = ArtistNameMatching.normalized(artistName)
            guard !name.isEmpty else { return nil }
            matching = songs.filter { $0.artistName.map(ArtistNameMatching.normalized) == name }
            guard Set(matching.compactMap(\.artistId)).count == 1 else { return nil }
        }
        guard let track = matching.first(where: {
            $0.trackId != nil && $0.previewUrl?.scheme == "https" && $0.previewUrl?.host != nil
        }), let id = track.trackId, let url = track.previewUrl else { return nil }
        return ListeningPlaybackItem(
            songID: String(id), duration: nil, previewURL: url,
            title: track.trackName, artistName: track.artistName
        )
    }
}
