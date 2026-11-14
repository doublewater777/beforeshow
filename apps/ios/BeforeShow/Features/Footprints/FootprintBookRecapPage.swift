import SwiftUI

/// The year looked back on: how long you stood in front of a stage, what kept coming back,
/// where the year began and ended, and what is still to come before it is out.
struct FootprintBookRecapPage: View {
    let book: FootprintBook
    let chapter: FootprintBook.Chapter
    let covers: [UUID: FootprintCover]
    let turner: FootprintBookTurner

    private var recap: FootprintBookRecap { FootprintBookRecap(book: book, chapter: chapter) }

    var body: some View {
        let recap = recap
        FootprintBookLeaf(
            stock: .paper,
            label: BSLocalization.format("第 %1$lld 章 · %2$@", chapter.number, String(chapter.year)),
            turner: turner
        ) {
            VStack(alignment: .leading, spacing: 0) {
                FootprintBookHeading(latin: "The Year", title: BSLocalization.text("这一年"), size: 44)
                    .padding(.top, 20)
                    .bookRise(0.2)
                headline(recap)
                    .padding(.top, 22)
                    .bookRise(0.5)
                Rectangle().fill(FootprintRoomPalette.ink.opacity(0.8)).frame(height: 1)
                    .padding(.top, 24)
                    .bookRise(0.8)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(FootprintBookRecapText.rows(recap).enumerated()), id: \.offset) { offset, row in
                        rowView(row)
                            .bookRise(1 + Double(offset) * 0.12)
                    }
                }
                .padding(.top, 4)
                if let span = FootprintBookRecapText.span(recap) {
                    Text(span)
                        .font(.system(size: 15, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(FootprintRoomPalette.inkSoft)
                        .padding(.top, 22)
                        .bookRise(1.6)
                }
                Spacer(minLength: 12)
                if recap.upcomingCount > 0 {
                    Text(BSLocalization.format("今年还有 %lld 场在等你。", recap.upcomingCount))
                        .font(.system(size: 16, design: .serif).italic())
                        .foregroundStyle(FootprintRoomPalette.stampGold)
                        .padding(.bottom, 10)
                        .bookRise(2)
                }
            }
        }
    }

    private func headline(_ recap: FootprintBookRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: String(recap.shows.count))
                    .font(.system(size: 72, weight: .light, design: .serif).monospacedDigit())
                Text(BSLocalization.text("场"))
                    .font(.system(size: 22, design: .serif))
            }
            if recap.durationMinutes > 0 {
                Text(BSLocalization.format("在台下站了 %@", FootprintBookText.duration(minutes: recap.durationMinutes)))
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(FootprintRoomPalette.inkMuted)
            }
        }
    }

    private func rowView(_ row: FootprintBookRecapText.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.label)
                .font(.system(size: 12))
                .tracking(1)
                .foregroundStyle(FootprintRoomPalette.inkMuted)
                .frame(width: 64, alignment: .leading)
            Text(row.value)
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let detail = row.detail {
                Text(detail)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(FootprintRoomPalette.inkMuted)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FootprintRoomPalette.ink.opacity(0.12)).frame(height: 1)
        }
    }
}

/// The recap said in words, shared by the page and the year poster.
@MainActor
enum FootprintBookRecapText {
    struct Row: Equatable {
        let label: String
        let value: String
        let detail: String?
    }

    static func rows(_ recap: FootprintBookRecap) -> [Row] {
        var rows: [Row] = []
        if let artist = recap.topArtist {
            rows.append(Row(label: BSLocalization.text("最常见"), value: artist.name, detail: times(artist.count)))
        }
        if let venue = recap.topVenue {
            rows.append(Row(label: BSLocalization.text("最常去"), value: venue.name, detail: times(venue.count)))
        }
        if let companion = recap.topCompanion {
            rows.append(Row(label: BSLocalization.text("最常同行"), value: companion.name, detail: times(companion.count)))
        }
        if recap.cityCount > 0 {
            rows.append(Row(label: BSLocalization.text("走过"), value: BSLocalization.format("%lld 座城市", recap.cityCount), detail: nil))
        }
        return rows
    }

    /// Where the year began and where it got to.
    static func span(_ recap: FootprintBookRecap) -> String? {
        guard let first = recap.first, let last = recap.last, first.id != last.id else { return nil }
        return BSLocalization.format(
            "从%1$@的%2$@，到%3$@的%4$@。",
            FootprintBookText.monthDay(first.effectiveDate, calendar: first.timingCalendar()),
            FootprintBookText.act(of: first),
            FootprintBookText.monthDay(last.effectiveDate, calendar: last.timingCalendar()),
            FootprintBookText.act(of: last)
        )
    }

    private static func times(_ count: Int) -> String {
        BSLocalization.format("%lld 次", count)
    }
}
