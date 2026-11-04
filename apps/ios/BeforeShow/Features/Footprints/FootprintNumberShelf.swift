import SwiftUI

/// The record collection on the Footprints home: the latest records fanned out,
/// how many of fifty you hold, and which show presses the next one.
struct FootprintNumberShelf: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    var body: some View {
        let ordered = FootprintArchiveRankingBuilder.chronological(archive.shows)
        let shelf = FootprintNumberSongs.shelf(showCount: ordered.count)
        NavigationLink {
            FootprintRecordWallView(archive: archive, covers: covers)
        } label: {
            HStack(spacing: 16) {
                fan(Array(ordered.suffix(3)), firstNumber: max(1, ordered.count - 2))
                VStack(alignment: .leading, spacing: 6) {
                    Text(BSLocalization.text("数字唱片"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(shelf.unlocked.count))
                            .font(.system(size: 26, weight: .black).width(.compressed))
                            .foregroundStyle(FootprintRoomPalette.bulb)
                        Text("/ \(shelf.total)")
                            .font(.system(size: 14, weight: .bold).width(.compressed))
                            .foregroundStyle(BSColor.Stage.dim)
                    }
                    progress(shelf)
                    if let next = shelf.next {
                        Text(BSLocalization.format("下一张 · 第 %lld 场", next.number))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BSColor.Stage.accent)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .padding(16)
            .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.07)))
        }
        .buttonStyle(BSPressStyle())
    }

    /// The three newest records, overlapping like a hand of cards.
    private func fan(_ shows: [Show], firstNumber: Int) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(shows.enumerated()), id: \.element.id) { index, show in
                FootprintNumberDisc(number: firstNumber + index, diameter: 64, isPlaying: false, show: show, cover: covers[show.id])
                    .offset(x: CGFloat(index) * 22)
            }
        }
        .frame(width: 64 + CGFloat(max(shows.count - 1, 0)) * 22, height: 64, alignment: .leading)
    }

    private func progress(_ shelf: FootprintRecordShelf) -> some View {
        GeometryReader { proxy in
            Capsule().fill(Color.white.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [FootprintRoomPalette.brass, FootprintRoomPalette.bulb], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(shelf.unlocked.count) / CGFloat(max(shelf.total, 1)))
                }
        }
        .frame(width: 120, height: 4)
    }
}
