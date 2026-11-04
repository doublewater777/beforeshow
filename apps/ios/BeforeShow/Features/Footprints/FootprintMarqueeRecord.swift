import SwiftUI

/// The marquee with your latest number record standing on its board: the board opens
/// the pass, the record opens the wall of fifty.
struct FootprintMarqueeWithRecord: View {
    let status: FootprintMarqueeStatus
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    @State private var controller = FootprintNumberSongPlayer.shared

    private static let disc: CGFloat = 104

    var body: some View {
        let shelf = FootprintNumberSongs.shelf(showCount: archive.shows.count)
        let latest = shelf.unlocked.first
        ZStack(alignment: .trailing) {
            NavigationLink {
                FootprintBackstagePassView(archive: archive, covers: covers)
            } label: {
                FootprintMarqueeView(status: status, recordInset: latest == nil ? 0 : Self.disc + 12)
            }
            .buttonStyle(.plain)
            if let latest {
                NavigationLink {
                    FootprintRecordWallView(archive: archive)
                } label: {
                    VStack(spacing: 4) {
                        FootprintNumberDisc(
                            number: latest.number,
                            diameter: Self.disc,
                            isPlaying: controller.isPlaying(latest.number),
                            artworkURL: controller.previews[latest.number]?.artworkURL
                        )
                        Text("No.\(latest.number) · \(shelf.unlocked.count)/\(shelf.total)")
                            .font(.system(size: 11, weight: .bold).width(.condensed).monospacedDigit())
                            .tracking(1)
                            .foregroundStyle(FootprintRoomPalette.marqueeInk.opacity(0.75))
                    }
                }
                .buttonStyle(BSPressStyle())
                .padding(.trailing, 26)
                .accessibilityLabel(BSLocalization.format("数字唱片，%lld / %lld", shelf.unlocked.count, shelf.total))
                .task(id: latest.number) { await controller.load([latest]) }
            }
        }
    }
}
