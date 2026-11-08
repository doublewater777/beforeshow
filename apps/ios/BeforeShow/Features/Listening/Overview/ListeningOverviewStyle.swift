import SwiftUI

/// The overview's own type and sizes, shared by the poster, feed, artist page and now playing.
enum ListeningOverviewStyle {
    static func serif(_ size: CGFloat) -> Font { BSFont.Editorial.serif(size) }
    static func caps(_ size: CGFloat) -> Font { BSFont.Editorial.caps(size) }
    static let sectionTitle = Font.system(size: 19, weight: .bold)
    static let headerTitle = Font.system(size: 16, weight: .bold)
    static let itemTitle = Font.system(size: 14, weight: .semibold)
    static let buttonLabel = Font.system(size: 14, weight: .bold)
    static let meta = Font.system(size: 13)
    static let badgeGlyph = Font.system(size: 10, weight: .bold)

    static let posterHeight: CGFloat = 420
    static let pickCover: CGFloat = 104
    static let playlistTile = CGSize(width: 140, height: 140)
    static let artistHeroHeight: CGFloat = 300
    static let featuredCover: CGFloat = 132
    static let releaseCard: CGFloat = 128
    static let badge: CGFloat = 26
    static let pillHeight: CGFloat = 40

    /// Quiet card fill, round icon button fill and the scrim behind controls on artwork.
    static let cardFill = Color.white.opacity(0.06)
    static let buttonFill = Color.white.opacity(0.12)
    static let scrim = Color.black.opacity(0.25)
}

/// "2023 · 10 首" under a release, or just the track count when the date is unknown.
enum ListeningReleaseMeta {
    static func yearAndTrackCount(_ disc: ListeningDisc) -> String {
        let count = ListeningCopy.format("%d 首", disc.tracks.count)
        guard let date = disc.releaseDate else { return count }
        return "\(Calendar.current.component(.year, from: date)) · \(count)"
    }
}
