import SwiftUI

/// The whole book at a glance while reading: every year and every show with its page, to jump straight to one.
struct FootprintBookContentsSheet: View {
    let book: FootprintBook
    let currentIndex: Int
    let go: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let index: Int
        let leading: String
        let title: String
        var id: Int { index }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        entries([entry(.prologue, title: BSLocalization.text("序"))])
                        ForEach(book.chapters, id: \.year) { chapter in
                            Section {
                                entries(entries(of: chapter))
                            } header: {
                                header(chapter)
                            }
                        }
                        entries([entry(.afterword, title: BSLocalization.text("后记"))])
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .task {
                    // After the first layout, so the lazy rows below the fold can be found.
                    await Task.yield()
                    reader.scrollTo(currentIndex, anchor: .center)
                }
            }
            .background(FootprintRoomPalette.bookRoom.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("目录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BSChromeToolbarCloseButton { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func entries(of chapter: FootprintBook.Chapter) -> [Entry] {
        let recap = chapter.shows.count > 1 ? [entry(.recap(year: chapter.year), title: BSLocalization.text("这一年"))] : []
        return recap + chapter.shows.compactMap { show in
            book.index(of: .show(show.id)).map {
                Entry(
                    index: $0,
                    leading: FootprintBookText.monthDay(show.effectiveDate, calendar: show.timingCalendar()),
                    title: FootprintBookText.act(of: show)
                )
            }
        }
    }

    private func entry(_ page: FootprintBook.Page, title: String) -> Entry {
        Entry(index: book.index(of: page) ?? 0, leading: "", title: title)
    }

    private func header(_ chapter: FootprintBook.Chapter) -> some View {
        Button { jump(book.index(of: .chapter(year: chapter.year))) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(BSLocalization.format("第 %lld 章", chapter.number))
                    .font(.system(size: 11))
                    .foregroundStyle(FootprintRoomPalette.foil)
                Text(verbatim: String(chapter.year))
                    .font(.system(size: 24, weight: .black, design: .serif))
                Text(BSLocalization.format("%lld 场", chapter.shows.count))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
                Spacer(minLength: 8)
                pageNumber(book.index(of: .chapter(year: chapter.year)))
            }
            .padding(.top, 22)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FootprintRoomPalette.bookRoom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(book.index(of: .chapter(year: chapter.year)))
    }

    private func entries(_ list: [Entry]) -> some View {
        ForEach(list) { item in
            Button { jump(item.index) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.leading)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Color(white: 0.5))
                        .frame(width: 58, alignment: .leading)
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(item.index == currentIndex ? FootprintRoomPalette.foil : FootprintRoomPalette.chapterInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    pageNumber(item.index)
                }
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id(item.index)
        }
    }

    private func pageNumber(_ index: Int?) -> some View {
        Text(index.flatMap(book.pageNumber(at:)).map(String.init) ?? "")
            .font(.system(size: 14, design: .serif).monospacedDigit())
            .foregroundStyle(index == currentIndex ? FootprintRoomPalette.foil : Color(white: 0.5))
    }

    private func jump(_ index: Int?) {
        guard let index else { return }
        go(index)
        dismiss()
    }
}
