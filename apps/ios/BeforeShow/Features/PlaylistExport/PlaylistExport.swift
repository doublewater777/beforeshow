import SwiftUI

/// A show's setlist in the two forms music apps import from: plain text and screenshots.
enum PlaylistExport {
    struct Song: Equatable {
        let title: String
        let artistName: String
    }

    /// Few enough rows per image that a music app's screenshot import reads every one.
    static let songsPerImage = 15
    static let imageWidth: CGFloat = 390
    static let imageScale: CGFloat = 3

    /// Each song once, in the order it was first played; songs without a title are dropped.
    static func songs(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.compactMap { song in
            let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert("\(title.lowercased())\u{1F}\(artist.lowercased())").inserted else { return nil }
            return Song(title: title, artistName: artist)
        }
    }

    static func text(_ songs: [Song]) -> String {
        songs.map { song in
            let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            return artist.isEmpty ? song.title : "\(song.title) - \(artist)"
        }
        .joined(separator: "\n")
    }

    static func pages(_ songs: [Song]) -> [[Song]] {
        stride(from: 0, to: songs.count, by: songsPerImage).map {
            Array(songs[$0..<min($0 + songsPerImage, songs.count)])
        }
    }

    @MainActor
    static func images(_ songs: [Song]) -> [UIImage]? {
        let rendered = pages(songs).compactMap { page in
            FootprintShareImageExport.render(
                PlaylistExportPage(songs: page),
                size: CGSize(width: imageWidth, height: PlaylistExportPage.height(rows: page.count)),
                scale: imageScale
            )
        }
        return rendered.count == pages(songs).count ? rendered : nil
    }
}

/// One screenshot's worth of songs, laid out like a music app's list: title over artist, black on white.
struct PlaylistExportPage: View {
    let songs: [PlaylistExport.Song]

    static let rowHeight: CGFloat = 60
    static let padding: CGFloat = 20

    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + padding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.offset) { _, song in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: song.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                    if !song.artistName.isEmpty {
                        Text(verbatim: song.artistName)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, Self.padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}
