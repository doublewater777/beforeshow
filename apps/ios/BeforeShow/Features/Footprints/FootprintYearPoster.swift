import SwiftUI
import UIKit

enum FootprintYearPosterStyle: String, BSSharePosterStyle {
    case film
    case ticket
    case wall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: BSLocalization.text("胶片")
        case .ticket: BSLocalization.text("票根")
        case .wall: BSLocalization.text("海报墙")
        }
    }

    var isPro: Bool { self != .film }
}

enum FootprintYearPosterLayout {
    static let size = CGSize(width: 360, height: 480)
    static let scale: CGFloat = 3
}

/// The posters of a year, decoded before the poster is drawn so the renderer never waits on a load.
@MainActor
enum FootprintYearPosterArtwork {
    static func load(shows: [Show], covers: [UUID: FootprintCover]) async -> [UUID: UIImage] {
        var images: [UUID: UIImage] = [:]
        for show in shows {
            switch covers[show.id]?.source {
            case .remote(let url):
                images[show.id] = await ShowCoverImageCache.shared.image(from: url)
            case .local(let url):
                images[show.id] = await Task.detached(priority: .userInitiated) { thumbnail(url) }.value
            case .archive, nil:
                break
            }
        }
        return images
    }

    nonisolated private static func thumbnail(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// A year on one 3:4 card, in one of three looks.
struct FootprintYearPoster: View {
    let recap: FootprintBookRecap
    let style: FootprintYearPosterStyle
    let artwork: [UUID: UIImage]

    var body: some View {
        Group {
            switch style {
            case .film: film
            case .ticket: ticket
            case .wall: wall
            }
        }
        .frame(width: FootprintYearPosterLayout.size.width, height: FootprintYearPosterLayout.size.height)
        .clipped()
    }

    private var summary: String {
        let count = BSLocalization.format("%lld 场现场", recap.shows.count)
        guard recap.durationMinutes > 0 else { return count }
        return count + " · " + FootprintBookText.duration(minutes: recap.durationMinutes)
    }

    private var rows: [FootprintBookRecapText.Row] { Array(FootprintBookRecapText.rows(recap).prefix(3)) }

    // MARK: Film

    private var film: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "BEFORESHOW · THE YEAR")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.8)
                .foregroundStyle(FootprintRoomPalette.foil)
            Text(verbatim: String(recap.year))
                .font(.system(size: 104, weight: .ultraLight, design: .serif))
                .tracking(-3)
                .padding(.leading, -5)
                .padding(.top, 6)
            Text(summary)
                .font(.system(size: 15, weight: .semibold, design: .serif))
            filmStrip
                .padding(.top, 20)
                .padding(.horizontal, -24)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 52, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 18)
            Spacer(minLength: 0)
            BSShareByline(tone: Color(white: 0.5))
        }
        .foregroundStyle(FootprintRoomPalette.chapterInk)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FootprintRoomPalette.chapterPaper)
    }

    private var filmStrip: some View {
        ZStack {
            Color(white: 0.02)
            VStack {
                sprockets
                Spacer(minLength: 0)
                sprockets
            }
            .padding(.vertical, 5)
            HStack(spacing: 6) {
                ForEach(recap.shows.suffix(5), id: \.id) { show in
                    cover(show)
                        .frame(width: 58, height: 76)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
        .frame(height: 104)
    }

    private var sprockets: some View {
        Canvas { canvas, size in
            var x: CGFloat = 0
            while x < size.width {
                canvas.fill(Path(CGRect(x: x, y: 0, width: 8, height: size.height)), with: .color(FootprintRoomPalette.paper.opacity(0.18)))
                x += 15
            }
        }
        .frame(height: 6)
    }

    // MARK: Ticket

    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.format("%@ 现场年票", String(recap.year)))
                    .font(.system(size: 22, weight: .black, design: .serif))
                Spacer(minLength: 0)
                Text(verbatim: String(format: "No. %03d", recap.shows.count))
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(FootprintRoomPalette.inkMuted)
            }
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(FootprintRoomPalette.inkMuted)
                .padding(.top, 4)
            perforation.padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(recap.shows.suffix(9), id: \.id) { show in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(FootprintBookText.monthDay(show.effectiveDate, calendar: show.timingCalendar()))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(FootprintRoomPalette.inkMuted)
                            .frame(width: 58, alignment: .leading)
                        Text(FootprintBookText.act(of: show))
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            perforation.padding(.bottom, 12)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows.prefix(2), id: \.label) { row in
                        Text(row.label + "  " + row.value)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                stamp
            }
            BSShareByline(tone: FootprintRoomPalette.inkMuted)
                .padding(.top, 10)
        }
        .foregroundStyle(FootprintRoomPalette.ink)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FootprintRoomPalette.paper)
    }

    private var perforation: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(FootprintRoomPalette.ink.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        .frame(height: 1)
    }

    private var stamp: some View {
        ZStack {
            Circle().stroke(FootprintRoomPalette.stampGold, lineWidth: 1.5)
            Circle().stroke(FootprintRoomPalette.stampGold.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(4)
            Text(verbatim: String(recap.year))
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(FootprintRoomPalette.stampGold)
        }
        .frame(width: 62, height: 62)
        .rotationEffect(.degrees(-10))
    }

    // MARK: Wall

    private var wall: some View {
        // Only as many posters as fill the grid: nine, four, two or one.
        let (count, columns) = recap.shows.count >= 9 ? (9, 3) : recap.shows.count >= 4 ? (4, 2) : (min(recap.shows.count, 2), 1)
        let shows = Array(recap.shows.suffix(count))
        let rows = max(count / columns, 1)
        let gap: CGFloat = 2
        let width = (FootprintYearPosterLayout.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (FootprintYearPosterLayout.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(shows.indices.filter { $0 / columns == row }, id: \.self) { index in
                            cover(shows[index])
                                .frame(width: width, height: height)
                                .clipped()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            LinearGradient(
                stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.88), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(recap.year))
                    .font(.system(size: 64, weight: .ultraLight, design: .serif))
                Text(summary)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                BSShareByline(tone: .white.opacity(0.7))
                    .padding(.top, 12)
            }
            .foregroundStyle(.white)
            .padding(22)
        }
        .background(Color.black)
    }

    // MARK: Covers

    @ViewBuilder
    private func cover(_ show: Show) -> some View {
        if let image = artwork[show.id] {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                FootprintRoomPalette.bookCloth
                Text(FootprintBookText.act(of: show))
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(FootprintRoomPalette.foil)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(6)
            }
        }
    }
}
