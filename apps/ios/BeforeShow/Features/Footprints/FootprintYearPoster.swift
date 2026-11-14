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

/// How many columns give `count` cells of one aspect (width / height) the largest size inside an area,
/// with `rowExtra` of each row's height taken up by something other than the cell.
struct FootprintYearPosterGrid {
    let columns: Int
    let rows: Int
    let cell: CGSize

    init(count: Int, in area: CGSize, aspect: CGFloat, gap: CGFloat, rowExtra: CGFloat = 0) {
        let count = max(count, 1)
        var best = (columns: 1, rows: count, width: CGFloat(0))
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            let byWidth = (area.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let byHeight = ((area.height - gap * CGFloat(rows - 1)) / CGFloat(rows) - rowExtra) * aspect
            let width = min(byWidth, byHeight)
            if width > best.width { best = (columns, rows, width) }
        }
        columns = best.columns
        rows = best.rows
        cell = CGSize(width: best.width, height: best.width / aspect)
    }
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

    private var rows: [FootprintBookRecapText.Row] { FootprintBookRecapText.rows(recap) }

    /// The shows cut into lines of `size`, in order.
    private func lines(of size: Int) -> [[Show]] {
        stride(from: 0, to: recap.shows.count, by: max(size, 1)).map { Array(recap.shows[$0..<min($0 + size, recap.shows.count)]) }
    }

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
            filmStrips
                .padding(.top, 18)
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
            .padding(.top, 16)
            .padding(.bottom, 14)
            BSShareByline(tone: Color(white: 0.5))
        }
        .foregroundStyle(FootprintRoomPalette.chapterInk)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FootprintRoomPalette.chapterPaper)
    }

    /// Every show of the year as a frame, on as many strips as it takes.
    private var filmStrips: some View {
        GeometryReader { proxy in
            let edge: CGFloat = 14
            let grid = FootprintYearPosterGrid(
                count: recap.shows.count,
                in: CGSize(width: proxy.size.width - 48, height: proxy.size.height),
                aspect: 3 / 4,
                gap: 4,
                rowExtra: edge * 2
            )
            // A few shows stay the size of frames rather than filling the page.
            let frame = CGSize(width: min(grid.cell.width, 72), height: min(grid.cell.width, 72) * 4 / 3)
            VStack(spacing: 4) {
                ForEach(Array(lines(of: grid.columns).enumerated()), id: \.offset) { _, line in
                    ZStack {
                        Color(white: 0.02)
                        VStack {
                            sprockets
                            Spacer(minLength: 0)
                            sprockets
                        }
                        .padding(.vertical, 4)
                        HStack(spacing: 4) {
                            ForEach(line, id: \.id) { show in
                                cover(show, named: frame.width >= 44)
                                    .frame(width: frame.width, height: frame.height)
                                    .clipped()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    }
                    .frame(height: frame.height + edge * 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
            ticketList
            perforation.padding(.vertical, 12)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows, id: \.label) { row in
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

    /// Every show of the year, in up to three columns, set as large as the space allows.
    private var ticketList: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let count = recap.shows.count
            let lineHeight = { (columns: Int) -> CGFloat in
                let rows = CGFloat((count + columns - 1) / max(columns, 1))
                return min(20, (proxy.size.height - spacing * (rows - 1)) / max(rows, 1))
            }
            let columns = (1...3).first { lineHeight($0) >= 15 } ?? 3
            let size = min(13, lineHeight(columns) * 0.72)
            let perColumn = (count + columns - 1) / columns
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(lines(of: perColumn).enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(column, id: \.id) { show in
                            HStack(alignment: .firstTextBaseline, spacing: columns == 1 ? 10 : 6) {
                                Text(columns == 1 ? FootprintBookText.monthDay(show.effectiveDate, calendar: show.timingCalendar()) : Self.shortDate(show))
                                    .font(.system(size: size - 2).monospacedDigit())
                                    .foregroundStyle(FootprintRoomPalette.inkMuted)
                                    .fixedSize()
                                    .frame(width: columns == 1 ? 58 : nil, alignment: .leading)
                                Text(FootprintBookText.act(of: show))
                                    .font(.system(size: size, weight: .semibold, design: .serif))
                                    .lineLimit(1)
                            }
                            .frame(height: lineHeight(columns))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// "05.12": the month and day in the width of a narrow column.
    private static func shortDate(_ show: Show) -> String {
        let parts = show.timingCalendar().dateComponents([.month, .day], from: show.effectiveDate)
        return String(format: "%02d.%02d", parts.month ?? 0, parts.day ?? 0)
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
        // Every poster of the year; a short last row stretches to the edge so the wall has no holes.
        let size = FootprintYearPosterLayout.size
        let gap: CGFloat = 2
        let grid = FootprintYearPosterGrid(count: recap.shows.count, in: size, aspect: 3 / 4, gap: gap)
        let height = (size.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: gap) {
                ForEach(Array(lines(of: grid.columns).enumerated()), id: \.offset) { _, line in
                    let width = (size.width - gap * CGFloat(line.count - 1)) / CGFloat(line.count)
                    HStack(spacing: gap) {
                        ForEach(line, id: \.id) { show in
                            cover(show)
                                .frame(width: width, height: height)
                                .clipped()
                        }
                    }
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
    private func cover(_ show: Show, named: Bool = true) -> some View {
        if let image = artwork[show.id] {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                FootprintRoomPalette.bookCloth
                if named {
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
}
