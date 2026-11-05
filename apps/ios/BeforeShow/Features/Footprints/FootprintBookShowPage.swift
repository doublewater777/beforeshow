import SwiftUI

/// One show's page: the poster pinned with photo corners, the date set large, a postmark,
/// the ticket stub, and the first thing you kept from that night.
struct FootprintBookShowPage: View {
    let book: FootprintBook
    let show: Show
    let cover: FootprintCover?
    let turner: FootprintBookTurner

    private var calendar: Calendar { show.timingCalendar() }
    private var ordinal: Int { book.ordinal(of: show) }

    var body: some View {
        let chapter = book.chapter(containing: show)
        FootprintBookLeaf(
            stock: .paper,
            label: chapter.map { BSLocalization.format("第 %1$lld 章 · %2$@", $0.number, String($0.year)) } ?? "",
            turner: turner
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: String(format: "No. %03d", ordinal))
                        .font(.system(size: 18, design: .serif).italic())
                        .foregroundStyle(FootprintRoomPalette.inkMuted)
                    if ordinal == 1 {
                        Text(BSLocalization.text("第一场"))
                            .font(.system(size: 12))
                            .tracking(2)
                            .foregroundStyle(FootprintRoomPalette.stampGold)
                    }
                }
                .padding(.top, 14)
                .bookRise(0.2)
                posterRow
                    .padding(.top, 14)
                titleBlock
                    .padding(.top, 22)
                keepsakeRow
                    .padding(.top, 22)
                Spacer(minLength: 12)
                HStack {
                    Text(FootprintBookText.elapsed(since: show.effectiveDate, calendar: calendar))
                    Spacer(minLength: 0)
                    Text(remaining)
                        .font(.system(size: 14, design: .serif).italic())
                }
                .font(.system(size: 12))
                .foregroundStyle(FootprintRoomPalette.inkMuted)
                .padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(FootprintRoomPalette.ink.opacity(0.12)).frame(height: 1) }
                .padding(.bottom, 10)
                .bookRise(1.6)
            }
        }
    }

    private var remaining: String {
        let after = book.shows.count - ordinal
        return after > 0 ? BSLocalization.format("之后还有 %lld 场", after) : BSLocalization.text("这是最近的一场")
    }

    // MARK: Poster and date

    private var posterRow: some View {
        let parts = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        return ZStack(alignment: .topLeading) {
            FootprintResolvedCoverImage(show: show, cover: cover)
                .frame(width: 180, height: 240)
                .clipped()
                .overlay { photoCorners }
                .padding(8)
                .background(FootprintRoomPalette.photoPaper)
                .shadow(color: Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.22), radius: 13, y: 12)
                .rotationEffect(.degrees(-2.5))
                .bookRise(0.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: String(format: "%02d", parts.month ?? 0))
                Rectangle().fill(FootprintRoomPalette.ink).frame(width: 32, height: 1).padding(.vertical, 8)
                Text(verbatim: String(format: "%02d", parts.day ?? 0))
                Text(verbatim: "\(parts.year ?? 0) · \(FootprintBookText.weekday(show.effectiveDate, calendar: calendar))")
                    .font(.system(size: 11))
                    .tracking(3)
                    .foregroundStyle(FootprintRoomPalette.inkMuted)
                    .padding(.top, 12)
            }
            .font(.system(size: 58, weight: .light, design: .serif))
            .offset(x: 222, y: 4)
            .bookRise(0.8)
            postmark
                .offset(x: 214, y: 198)
                .bookRise(1.2)
        }
        .frame(height: 268, alignment: .topLeading)
    }

    private var photoCorners: some View {
        GeometryReader { proxy in
            let size: CGFloat = 20
            let corner = Color(red: 0.165, green: 0.153, blue: 0.133)
            Path { path in
                let w = proxy.size.width, h = proxy.size.height
                path.addLines([CGPoint(x: 0, y: 0), CGPoint(x: size, y: 0), CGPoint(x: 0, y: size)])
                path.closeSubpath()
                path.addLines([CGPoint(x: w, y: 0), CGPoint(x: w - size, y: 0), CGPoint(x: w, y: size)])
                path.closeSubpath()
                path.addLines([CGPoint(x: 0, y: h), CGPoint(x: size, y: h), CGPoint(x: 0, y: h - size)])
                path.closeSubpath()
                path.addLines([CGPoint(x: w, y: h), CGPoint(x: w - size, y: h), CGPoint(x: w, y: h - size)])
                path.closeSubpath()
            }
            .fill(corner)
        }
        .accessibilityHidden(true)
    }

    private var postmark: some View {
        let parts = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        return ZStack {
            Circle().stroke(lineWidth: 2)
            Circle().stroke(lineWidth: 1).padding(11)
            VStack(spacing: 1) {
                if let city = show.bookCity {
                    Text(verbatim: city)
                        .font(.system(size: 14, weight: .black, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(verbatim: String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
                    .font(.system(size: 10, design: .serif))
            }
            .padding(.horizontal, 4)
            .background(FootprintRoomPalette.paper)
            .frame(width: 68)
        }
        .foregroundStyle(FootprintRoomPalette.stampGold)
        .frame(width: 84, height: 84)
        .opacity(0.88)
        .rotationEffect(.degrees(-8))
        .accessibilityHidden(true)
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(show.name)
                .font(.system(size: 25, weight: .black, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let lineup {
                Text(lineup)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(FootprintRoomPalette.inkSoft)
                    .lineLimit(1)
            }
            if let venue = show.bookVenue {
                Label(venue, systemImage: "mappin")
                    .font(.system(size: 13))
                    .foregroundStyle(FootprintRoomPalette.inkMuted)
                    .padding(.top, 6)
            }
        }
        .bookRise(1)
    }

    /// The lineup, when it says something the title does not.
    private var lineup: String? {
        let title = show.name.lowercased()
        let names = show.artistNames.compactMap(FootprintTextNormalizer.nonEmptyTrimmed).filter { name in
            // An act whose name already appears in the title, in any of its spellings, adds nothing.
            !name.split(separator: " ").contains { $0.count >= 2 && title.contains($0.lowercased()) } && !title.contains(name.lowercased())
        }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(3).joined(separator: " · ")
        return names.count > 3 ? BSLocalization.format("%1$@ 等 %2$lld 位", shown, names.count) : shown
    }

    // MARK: Keepsakes

    private var keepsakeRow: some View {
        HStack(alignment: .top, spacing: 16) {
            memory
            Spacer(minLength: 0)
            ticket
        }
    }

    @ViewBuilder
    private var memory: some View {
        let fragments = show.memoryFragments.sorted { $0.createdAt < $1.createdAt }
        let photo = fragments.lazy.flatMap(\.orderedMediaItems).first
        let words = fragments.compactMap { FootprintTextNormalizer.nonEmptyTrimmed($0.text) }.first
        if photo != nil || words != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(BSLocalization.text("那天"))
                    .font(.system(size: 11))
                    .tracking(2)
                    .foregroundStyle(FootprintRoomPalette.inkFaint)
                if let photo {
                    MemoryThumbnail(relativePath: photo.thumbnailRelativePath ?? photo.relativePath)
                        .frame(width: 96, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                        .background(FootprintRoomPalette.photoPaper)
                        .rotationEffect(.degrees(-3))
                } else if let words {
                    Text(words)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(FootprintRoomPalette.inkSoft)
                        .lineLimit(3)
                        .frame(width: 140, alignment: .leading)
                }
            }
            .bookRise(1.4)
        }
    }

    private var ticket: some View {
        let parts = calendar.dateComponents([.year, .month, .day], from: show.effectiveDate)
        let place = show.bookVenue ?? show.bookCity ?? ""
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "ADMIT ONE")
                    .font(.system(size: 8))
                    .tracking(2.5)
                    .foregroundStyle(FootprintRoomPalette.foil)
                Spacer(minLength: 0)
                Text(verbatim: place)
                    .font(.system(size: 13, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(FootprintRoomPalette.paper.opacity(0.7))
                Spacer(minLength: 0)
                Canvas { canvas, size in
                    var x: CGFloat = 0
                    var seed = UInt64(ordinal) &* 2654435761
                    while x < size.width {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        let width = CGFloat(seed >> 62) + 1
                        canvas.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(FootprintRoomPalette.paper))
                        x += width + CGFloat(seed >> 61 & 3) + 1
                    }
                }
                .frame(height: 11)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: String(format: "№ %03d", ordinal))
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(FootprintRoomPalette.foil)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: 38)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.clear).frame(width: 1.5)
                        .overlay(Rectangle().stroke(FootprintRoomPalette.paper, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                }
        }
        .foregroundStyle(FootprintRoomPalette.paper)
        .frame(width: 176, height: 84)
        .background(FootprintRoomPalette.ink, in: RoundedRectangle(cornerRadius: 6))
        .rotationEffect(.degrees(3))
        .shadow(color: Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.18), radius: 6, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "№ %03d", ordinal))
        .bookRise(1.3)
    }
}
