import SwiftUI

// MARK: - Cover

/// A cloth-bound volume in the dark, the latest poster in its window. Tap to open.
struct FootprintBookCover: View {
    let book: FootprintBook
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let turner: FootprintBookTurner

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(action: turner.close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("合上"))
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 12)
            Button(action: turner.next) { volume }
                .buttonStyle(.plain)
                .offset(y: floating ? -4 : 0)
                .accessibilityLabel(BSLocalization.text("翻开回忆册"))
            VStack(spacing: 8) {
                Text(BSLocalization.format("%lld 场现场，收在这里", book.shows.count))
                    .font(.system(size: 15, design: .serif))
                    .tracking(1)
                    .foregroundStyle(Color(red: 0.894, green: 0.871, blue: 0.824))
                if let latest = book.shows.last {
                    Text(lastLine(latest))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.43))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .bookRise(0.8)
            Spacer(minLength: 12)
            Button(action: turner.next) {
                VStack(spacing: 6) {
                    Image(systemName: "book")
                        .font(.system(size: 16))
                    Text(BSLocalization.text("轻点翻开"))
                        .font(.system(size: 12))
                        .tracking(3)
                }
                .foregroundStyle(Color(white: 0.59))
                .frame(minHeight: BSLayout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(colors: [Color(red: 0.09, green: 0.082, blue: 0.102), FootprintRoomPalette.bookRoom], center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(1.2)) { floating = true }
        }
    }

    private var volume: some View {
        let latest = book.shows.last
        return ZStack(alignment: .topLeading) {
            // Page block showing past the boards.
            RoundedRectangle(cornerRadius: 6)
                .fill(FootprintRoomPalette.paperEdge)
                .frame(width: 284, height: 420)
                .offset(x: 10, y: 8)
            RoundedRectangle(cornerRadius: 6)
                .fill(FootprintRoomPalette.paper)
                .frame(width: 284, height: 420)
                .offset(x: 6, y: 4)
            ZStack {
                LinearGradient(colors: [FootprintRoomPalette.bookCloth, FootprintRoomPalette.bookClothDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 0) {
                    LinearGradient(colors: [Color(white: 0.04), Color(white: 0.1), Color(white: 0.06)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                    Spacer(minLength: 0)
                }
                Rectangle().stroke(FootprintRoomPalette.foil.opacity(0.35)).padding(EdgeInsets(top: 16, leading: 30, bottom: 16, trailing: 16))
                Rectangle().stroke(FootprintRoomPalette.foil.opacity(0.15)).padding(EdgeInsets(top: 20, leading: 34, bottom: 20, trailing: 20))
                VStack(spacing: 0) {
                    foilText(Text(verbatim: "VOL. 01").font(.system(size: 12, design: .serif)).tracking(5))
                    Group {
                        if let latest {
                            FootprintResolvedCoverImage(show: latest, cover: covers[latest.id])
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: 128, height: 170)
                    .clipped()
                    .padding(6)
                    .background(Color(white: 0.04))
                    .overlay(Rectangle().stroke(FootprintRoomPalette.foil.opacity(0.3)))
                    .padding(.top, 20)
                    foilText(Text(BSLocalization.text("足迹")).font(.system(size: 42, weight: .black, design: .serif)).tracking(12))
                        .padding(.top, 24)
                    foilText(Text(verbatim: yearSpan).font(.system(size: 15, design: .serif)).tracking(4))
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                    Text(verbatim: "BEFORESHOW")
                        .font(.system(size: 9))
                        .tracking(4)
                        .foregroundStyle(FootprintRoomPalette.foil.opacity(0.45))
                        .padding(.bottom, 30)
                }
                .padding(.leading, 16)
                .padding(.top, 38)
            }
            .frame(width: 284, height: 418)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 10, topTrailingRadius: 10))
            .shadow(color: .black.opacity(0.7), radius: 40, y: 30)
        }
        .frame(width: 296, height: 430, alignment: .topLeading)
    }

    private var yearSpan: String {
        guard let first = book.chapters.first?.year, let last = book.chapters.last?.year else { return "" }
        return first == last ? String(first) : "\(first) — \(last)"
    }

    private func lastLine(_ show: Show) -> String {
        let calendar = show.timingCalendar()
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: show.effectiveDate), to: calendar.startOfDay(for: Date())).day ?? 0
        return days > 0
            ? BSLocalization.format("上一场是 %lld 天前 · %@", days, show.name)
            : BSLocalization.format("上一场 · %@", show.name)
    }

    private func foilText(_ text: Text) -> some View {
        text.foregroundStyle(LinearGradient(
            colors: [FootprintRoomPalette.foilDark, FootprintRoomPalette.foil, FootprintRoomPalette.foilLight, FootprintRoomPalette.foil, FootprintRoomPalette.foilDark],
            startPoint: .leading,
            endPoint: .trailing
        ))
    }
}

// MARK: - Contents

struct FootprintBookContents: View {
    let book: FootprintBook
    let turner: FootprintBookTurner

    private struct Row: Identifiable {
        let kicker: String
        let title: String
        let detail: String
        let page: FootprintBook.Page
        var id: FootprintBook.Page { page }
    }

    var body: some View {
        FootprintBookLeaf(stock: .paper, label: BSLocalization.text("足迹 · VOL. 01"), turner: turner) {
            VStack(alignment: .leading, spacing: 0) {
                FootprintBookHeading(latin: "Contents", title: BSLocalization.text("目录"), size: 36)
                    .bookRise(0.2)
                    .padding(.top, 26)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                        Button { book.index(of: row.page).map(turner.go) } label: { line(row) }
                            .buttonStyle(.plain)
                            .bookRise(0.35 + Double(offset) * 0.05)
                    }
                }
                .padding(.top, 28)
            }
        }
    }

    private var rows: [Row] {
        [Row(kicker: "", title: BSLocalization.text("序"), detail: BSLocalization.format("%lld 场", book.shows.count), page: .prologue)]
            + book.chapters.map {
                Row(kicker: BSLocalization.format("第 %lld 章", $0.number), title: String($0.year), detail: BSLocalization.format("%lld 场", $0.shows.count), page: .chapter(year: $0.year))
            }
            + [Row(kicker: "", title: BSLocalization.text("后记"), detail: "", page: .afterword)]
    }

    private func line(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.kicker)
                .font(.system(size: 11))
                .foregroundStyle(FootprintRoomPalette.inkFaint)
                .frame(width: 44, alignment: .leading)
            Text(row.title)
                .font(.system(size: 17, weight: .semibold, design: .serif))
            Text(row.detail)
                .font(.system(size: 11))
                .foregroundStyle(FootprintRoomPalette.inkFaint)
            Rectangle()
                .fill(FootprintRoomPalette.ink.opacity(0.2))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(book.index(of: row.page).flatMap(book.pageNumber(at:)).map(String.init) ?? "")
                .font(.system(size: 17, design: .serif).monospacedDigit())
                .foregroundStyle(FootprintRoomPalette.inkSoft)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(FootprintRoomPalette.ink.opacity(0.08)).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

/// A Latin running word over a serif heading, as on a book's section openers.
struct FootprintBookHeading: View {
    let latin: String
    let title: String
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: latin)
                .font(.system(size: 16, design: .serif).italic())
                .foregroundStyle(FootprintRoomPalette.inkFaint)
            Text(title)
                .font(.system(size: size, weight: .black, design: .serif))
                .tracking(size > 50 ? 0 : 6)
        }
    }
}

// MARK: - Prologue

struct FootprintBookPrologue: View {
    let book: FootprintBook
    let archive: FootprintArchiveSnapshot
    let turner: FootprintBookTurner

    var body: some View {
        FootprintBookLeaf(stock: .paper, label: BSLocalization.text("序"), turner: turner) {
            VStack(alignment: .leading, spacing: 0) {
                FootprintBookHeading(latin: "Prologue", title: BSLocalization.text("序"), size: 64)
                    .bookRise(0.2)
                    .padding(.top, 20)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(FootprintBookText.prologue(book: book, archive: archive).enumerated()), id: \.offset) { offset, paragraph in
                        Text(paragraph)
                            .padding(.top, offset == 2 ? 10 : 0)
                            .bookRise(0.5 + Double(offset) * 0.15)
                    }
                }
                .font(.system(size: 16, design: .serif))
                .lineSpacing(10)
                .foregroundStyle(Color(red: 0.173, green: 0.165, blue: 0.145))
                .padding(.top, 28)
                Rectangle().fill(FootprintRoomPalette.ink.opacity(0.8)).frame(height: 1)
                    .padding(.top, 30)
                    .bookRise(1.2)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 20) {
                    stat(book.shows.count, BSLocalization.text("场现场"), 0)
                    stat(archive.artists.count, BSLocalization.text("位艺人"), 1)
                    stat(archive.cities.count, BSLocalization.text("座城市"), 2)
                    stat(archive.venues.count, BSLocalization.text("个场馆"), 3)
                }
                .padding(.top, 20)
                Spacer(minLength: 16)
                HStack(alignment: .bottom) {
                    Text(BSLocalization.format("— 写于 %@", FootprintBookText.longDate(Date(), calendar: .current)))
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundStyle(FootprintRoomPalette.inkMuted)
                    Spacer(minLength: 0)
                    seal
                }
                .bookRise(2)
                .padding(.bottom, 10)
            }
        }
    }

    private func stat(_ value: Int, _ label: String, _ order: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: String(value))
                .font(.system(size: 52, weight: .light, design: .serif).monospacedDigit())
            Text(label)
                .font(.system(size: 12))
                .tracking(1)
                .foregroundStyle(FootprintRoomPalette.inkMuted)
        }
        .bookRise(1.4 + Double(order) * 0.1)
    }

    private var seal: some View {
        ZStack {
            Circle().stroke(FootprintRoomPalette.stampGold, lineWidth: 1.5)
            Circle().stroke(FootprintRoomPalette.stampGold.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(4)
            VStack(spacing: 1) {
                Text(verbatim: "BEFORESHOW").font(.system(size: 7)).tracking(1.5)
                Text(verbatim: String(book.shows.count)).font(.system(size: 22, design: .serif))
            }
            .foregroundStyle(FootprintRoomPalette.stampGold)
        }
        .frame(width: 74, height: 74)
        .rotationEffect(.degrees(-10))
        .accessibilityHidden(true)
    }
}

// MARK: - Chapter

/// A year opens on the dark stock: the year set huge, its months as dots, its posters as a strip of film.
struct FootprintBookChapterPage: View {
    let book: FootprintBook
    let chapter: FootprintBook.Chapter
    let covers: [UUID: FootprintCover]
    let turner: FootprintBookTurner

    var body: some View {
        FootprintBookLeaf(stock: .night, label: BSLocalization.format("第 %lld 章", chapter.number), turner: turner) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: String(chapter.year))
                    .font(.system(size: 132, weight: .ultraLight, design: .serif))
                    .tracking(-4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.leading, -8)
                    .padding(.top, 24)
                    .bookRise(0.2)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(BSLocalization.format("%lld 场", chapter.shows.count))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                    if let tagline {
                        Text(tagline)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.59))
                    }
                }
                .bookRise(0.6)
                months
                    .padding(.top, 30)
                    .bookRise(0.8)
                film
                    .padding(.top, 30)
                    .padding(.leading, -40)
                    .padding(.trailing, -34)
                    .bookRise(1.1)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(FootprintBookText.chapterLines(book: book, chapter: chapter).enumerated()), id: \.offset) { offset, line in
                        Text(line)
                            .foregroundStyle(offset == 0 ? Color(red: 0.847, green: 0.827, blue: 0.784) : Color(white: 0.59))
                    }
                }
                .font(.system(size: 15, design: .serif))
                .lineSpacing(8)
                .padding(.top, 28)
                .bookRise(1.4)
            }
        }
    }

    private var tagline: String? {
        if chapter.year == book.busiestYear { return BSLocalization.text("你最常出门的一年") }
        if chapter.number == 1 { return BSLocalization.text("一切开始的一年") }
        return nil
    }

    private var months: some View {
        let counts = FootprintBook.monthCounts(of: chapter)
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<12, id: \.self) { month in
                    VStack(spacing: 3) {
                        ForEach(0..<min(counts[month], 4), id: \.self) { _ in
                            Circle().fill(FootprintRoomPalette.chapterDot).frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 27, alignment: .bottom)
                }
            }
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            HStack(spacing: 0) {
                ForEach(Array(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"].enumerated()), id: \.offset) { _, letter in
                    Text(verbatim: letter)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Color(white: 0.43))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var film: some View {
        ZStack {
            Color(white: 0.02)
            VStack {
                sprockets
                Spacer(minLength: 0)
                sprockets
            }
            .padding(.vertical, 6)
        }
        .frame(height: 146)
        // The frames ride on top so however many there are, they never widen the page.
        .overlay(alignment: .leading) {
            FootprintBookFilmFrames(shows: Array(chapter.shows.prefix(12)), covers: covers)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var sprockets: some View {
        Canvas { canvas, size in
            var x: CGFloat = 0
            while x < size.width {
                canvas.fill(Path(CGRect(x: x, y: 0, width: 10, height: size.height)), with: .color(FootprintRoomPalette.paper.opacity(0.18)))
                x += 18
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Afterword

/// The book ends on the last show and leaves the next page for the one you are waiting for.
struct FootprintBookAfterword: View {
    let book: FootprintBook
    let covers: [UUID: FootprintCover]
    let turner: FootprintBookTurner

    var body: some View {
        FootprintBookLeaf(stock: .paper, label: BSLocalization.text("后记"), turner: turner) {
            VStack(alignment: .leading, spacing: 0) {
                FootprintBookHeading(latin: "Afterword", title: BSLocalization.text("后记"), size: 40)
                    .bookRise(0.2)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(FootprintBookText.afterword(book: book).enumerated()), id: \.offset) { offset, line in
                        Text(line).bookRise(0.45 + Double(offset) * 0.15)
                    }
                }
                .font(.system(size: 15, design: .serif))
                .lineSpacing(10)
                .foregroundStyle(Color(red: 0.173, green: 0.165, blue: 0.145))
                .padding(.top, 22)
                nextLeaf
                    .frame(maxWidth: .infinity)
                    .padding(.top, 26)
                    .bookRise(1)
                VStack(spacing: 26) {
                    ForEach(0..<3, id: \.self) { _ in Rectangle().fill(FootprintRoomPalette.ink.opacity(0.14)).frame(height: 1) }
                }
                .padding(.top, 28)
                .bookRise(1.3)
            }
        }
    }

    private var nextLeaf: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(FootprintRoomPalette.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            VStack(spacing: 10) {
                Group {
                    if let next = book.next {
                        // Not in Footprints yet, so it has no archive cover; hang its own poster.
                        ShowCoverImageView(
                            urlString: next.coverImageURL,
                            aspectRatio: 3.0 / 4.0,
                            contentMode: .fill,
                            alignment: .top,
                            enforcesAspectRatio: false,
                            cornerRadius: 0
                        )
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 150, height: 200)
                .clipped()
                .shadow(color: Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.2), radius: 7, y: 6)
                Text(verbatim: nextCaption)
                    .font(.system(size: 15, design: .serif).italic())
                    .foregroundStyle(FootprintRoomPalette.inkSoft)
            }
            .padding(.top, 14)
            HStack {
                tape(-8)
                Spacer(minLength: 0)
                tape(7)
            }
            .padding(.horizontal, -10)
            .padding(.top, 2)
        }
        .frame(width: 180, height: 256)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nextCaption)
    }

    private var nextCaption: String {
        let number = String(format: "No. %03d", book.shows.count + 1)
        guard let next = book.next else { return number }
        let calendar = next.timingCalendar()
        let parts = calendar.dateComponents([.month, .day], from: next.effectiveDate)
        return number + String(format: " · %02d.%02d", parts.month ?? 0, parts.day ?? 0)
    }

    private func tape(_ angle: Double) -> some View {
        Rectangle()
            .fill(Color(red: 0.84, green: 0.77, blue: 0.59).opacity(0.75))
            .frame(width: 58, height: 18)
            .rotationEffect(.degrees(angle))
    }
}

/// The year's posters as frames of film, running slowly past like a reel.
private struct FootprintBookFilmFrames: View {
    let shows: [Show]
    let covers: [UUID: FootprintCover]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let frameWidth: CGFloat = 80
    private static let gap: CGFloat = 8
    /// Points per second.
    private static let speed: Double = 14

    private var reelWidth: CGFloat { CGFloat(shows.count) * (Self.frameWidth + Self.gap) }

    var body: some View {
        // Short reels stay put; a reel that fills the strip loops, drawn twice so it never runs out.
        let loops = !reduceMotion && reelWidth > 300
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !loops)) { context in
            let travel = loops ? CGFloat(context.date.timeIntervalSinceReferenceDate * Self.speed).truncatingRemainder(dividingBy: reelWidth) : 0
            HStack(spacing: Self.gap) {
                reel
                if loops { reel }
            }
            .padding(.leading, Self.gap)
            .fixedSize()
            .offset(x: -travel)
        }
    }

    private var reel: some View {
        HStack(spacing: Self.gap) {
            ForEach(shows) { show in
                FootprintResolvedCoverImage(show: show, cover: covers[show.id])
                    .frame(width: Self.frameWidth, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .saturation(0.85)
            }
        }
    }
}
