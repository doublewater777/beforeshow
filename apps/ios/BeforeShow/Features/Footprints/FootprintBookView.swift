import SwiftUI
import UIKit

/// The memory book, read one page at a time with the system page curl.
struct FootprintBookView: View {
    let book: FootprintBook
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var index: Int
    @State private var isExporting = false
    @State private var isShowingPaywall = false
    @State private var isShowingContents = false
    @State private var toast: BSToastPayload?

    init(book: FootprintBook, archive: FootprintArchiveSnapshot, covers: [UUID: FootprintCover]) {
        self.book = book
        self.archive = archive
        self.covers = covers
        _index = State(initialValue: book.openingIndex(now: Date(), calendar: .current))
    }

    var body: some View {
        FootprintPageCurl(count: book.pages.count, index: $index, animated: !reduceMotion) { pageIndex in
            AnyView(page(at: pageIndex))
        }
        .ignoresSafeArea()
        .background(FootprintRoomPalette.bookRoom.ignoresSafeArea())
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: index)
        .bsToastOverlay(toast, bottomPadding: 36)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
        .sheet(isPresented: $isShowingContents) {
            FootprintBookContentsSheet(book: book, currentIndex: index) { target in
                index = min(max(0, target), book.pages.count - 1)
            }
        }
    }

    private func page(at pageIndex: Int) -> some View {
        FootprintBookPageContent(
            book: book,
            archive: archive,
            covers: covers,
            pageIndex: pageIndex,
            turner: FootprintBookTurner(
                index: pageIndex,
                number: book.pageNumber(at: pageIndex),
                isLast: pageIndex == book.pages.count - 1,
                go: { target in index = min(max(0, target), book.pages.count - 1) },
                close: { dismiss() },
                openContents: book.pages[pageIndex] == .contents ? nil : { isShowingContents = true }
            ),
            export: FootprintBookLeafAccessory(
                symbol: "arrow.down.doc",
                label: BSLocalization.text("导出 PDF"),
                isBusy: isExporting,
                action: { Task { await exportPDF() } }
            )
        )
    }

    @MainActor
    private func exportPDF() async {
        guard !isExporting else { return }
        guard ProEntitlementStorage.decode(entitlementRawValue).isProActive else {
            isShowingPaywall = true
            return
        }
        isExporting = true
        defer { isExporting = false }
        guard let file = await FootprintBookPDFExport.render(book: book, archive: archive, covers: covers) else {
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("回忆册导出失败，请重试"))
            return
        }
        guard SystemPNGSharePresenter.present(items: [file], cleanup: file) else {
            try? FileManager.default.removeItem(at: file)
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("系统分享面板暂时无法打开"))
            return
        }
    }
}

/// One page of the book, whether read on screen or printed into the PDF.
struct FootprintBookPageContent: View {
    let book: FootprintBook
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let pageIndex: Int
    let turner: FootprintBookTurner
    let export: FootprintBookLeafAccessory?

    var body: some View {
        switch book.pages[pageIndex] {
        case .cover:
            FootprintBookCover(book: book, archive: archive, covers: covers, turner: turner, export: export)
        case .contents:
            FootprintBookContents(book: book, turner: turner)
        case .prologue:
            FootprintBookPrologue(book: book, archive: archive, turner: turner)
        case .chapter(let year):
            if let chapter = book.chapter(year: year) {
                FootprintBookChapterPage(book: book, chapter: chapter, covers: covers, turner: turner)
            }
        case .recap(let year):
            if let chapter = book.chapter(year: year) {
                FootprintBookRecapPage(book: book, chapter: chapter, covers: covers, turner: turner)
            }
        case .show(let id):
            if let show = book.show(id: id) {
                FootprintBookShowPage(book: book, show: show, cover: covers[id], turner: turner)
            }
        case .afterword:
            FootprintBookAfterword(book: book, covers: covers, turner: turner)
        }
    }
}

/// What a page needs to move through the book.
struct FootprintBookTurner {
    let index: Int
    let number: Int?
    let isLast: Bool
    let go: (Int) -> Void
    let close: () -> Void
    /// Opens the contents over the page to jump anywhere; nil on the contents page itself.
    var openContents: (() -> Void)?

    func previous() { go(index - 1) }
    func next() { go(index + 1) }
}

/// One leaf of the book: paper (or the dark chapter stock), a running head, and the folio with page turns.
enum FootprintBookStock { case paper, night }

/// A button a page adds beside 合上.
struct FootprintBookLeafAccessory {
    let symbol: String
    let label: String
    let isBusy: Bool
    let action: () -> Void
}

extension EnvironmentValues {
    /// The page is being drawn into the PDF: no buttons, and everything already settled.
    @Entry var footprintBookPrinting = false
}

struct FootprintBookLeaf<Content: View>: View {
    let stock: FootprintBookStock
    let label: String
    let turner: FootprintBookTurner
    var accessory: FootprintBookLeafAccessory?
    @ViewBuilder let content: Content

    @Environment(\.footprintBookPrinting) private var isPrinting

    private var ink: Color { stock == .paper ? FootprintRoomPalette.inkSoft : Color(white: 0.6) }
    private var faint: Color { stock == .paper ? FootprintRoomPalette.inkFaint : Color(white: 0.43) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .tracking(3)
                    .foregroundStyle(stock == .paper ? faint : FootprintRoomPalette.foil)
                Spacer(minLength: 0)
                if let accessory {
                    FootprintBookAccessoryButton(accessory: accessory, tint: ink)
                }
                if let openContents = turner.openContents {
                    chromeButton("list.bullet", label: BSLocalization.text("目录"), action: openContents)
                }
                chromeButton("xmark", label: BSLocalization.text("合上"), action: turner.close)
            }
            .opacity(isPrinting ? 0 : 1)
            .padding(.leading, 32)
            .padding(.trailing, 14)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 40)
                .padding(.trailing, 34)
            HStack {
                chromeButton("chevron.left", label: BSLocalization.text("上一页"), action: turner.previous)
                    .foregroundStyle(faint)
                Spacer(minLength: 0)
                if let number = turner.number {
                    Text("— \(number) —")
                        .font(.system(size: 14, design: .serif))
                        .tracking(2)
                        .foregroundStyle(faint)
                }
                Spacer(minLength: 0)
                if turner.isLast {
                    chromeButton("book.closed", label: BSLocalization.text("合上回忆册"), action: turner.close)
                } else {
                    chromeButton("chevron.right", label: BSLocalization.text("下一页"), action: turner.next)
                }
            }
            .padding(.leading, 26)
            .padding(.trailing, 18)
            .padding(.bottom, 6)
        }
        .foregroundStyle(stock == .paper ? FootprintRoomPalette.ink : FootprintRoomPalette.chapterInk)
        .background { FootprintBookPaper(stock: stock) }
    }

    private func chromeButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .buttonStyle(.plain)
        .opacity(isPrinting ? 0 : 1)
        .accessibilityLabel(label)
    }
}

struct FootprintBookAccessoryButton: View {
    let accessory: FootprintBookLeafAccessory
    let tint: Color

    var body: some View {
        Button(action: accessory.action) {
            Group {
                if accessory.isBusy {
                    ProgressView().controlSize(.small).tint(tint)
                } else {
                    Image(systemName: accessory.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .buttonStyle(.plain)
        .disabled(accessory.isBusy)
        .accessibilityLabel(accessory.label)
    }
}

/// Paper with a fine grain and the shadow of the binding along the left edge.
struct FootprintBookPaper: View {
    let stock: FootprintBookStock

    var body: some View {
        ZStack(alignment: .leading) {
            stock == .paper ? FootprintRoomPalette.paper : FootprintRoomPalette.chapterPaper
            if let grain = Self.grain {
                Image(uiImage: grain)
                    .resizable(resizingMode: .tile)
                    .opacity(stock == .paper ? 0.5 : 0.25)
                    .blendMode(stock == .paper ? .multiply : .screen)
            }
            LinearGradient(
                colors: [(stock == .paper ? Color(red: 0.24, green: 0.18, blue: 0.08).opacity(0.22) : Color.black.opacity(0.6)), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 34)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A small tile of paper fibre, made once.
    private static let grain: UIImage? = {
        let size = 128
        var seed: UInt64 = 7
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            for _ in 0..<1400 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(seed >> 40 & 127)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let y = CGFloat(seed >> 40 & 127)
                let shade = CGFloat(seed >> 20 & 255) / 255
                UIColor(white: 0.55 + shade * 0.4, alpha: 0.35).setFill()
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }()
}

extension View {
    /// Content settling onto the page: rises a little and comes into focus.
    func bookRise(_ delay: Double = 0) -> some View {
        modifier(FootprintBookRise(delay: delay))
    }
}

private struct FootprintBookRise: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.footprintBookPrinting) private var isPrinting

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPrinting {
            content
        } else {
            rising(content)
        }
    }

    private func rising(_ content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.7).delay(delay)) { shown = true }
            }
    }
}

/// UIPageViewController in page-curl mode, one hosted SwiftUI page per leaf.
private struct FootprintPageCurl: UIViewControllerRepresentable {
    let count: Int
    @Binding var index: Int
    let animated: Bool
    let page: (Int) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue]
        )
        controller.isDoubleSided = false
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = UIColor(FootprintRoomPalette.bookRoom)
        controller.setViewControllers([context.coordinator.leaf(at: index)], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let shown = controller.viewControllers?.first as? Leaf, shown.index != index else { return }
        controller.setViewControllers(
            [context.coordinator.leaf(at: index)],
            direction: index > shown.index ? .forward : .reverse,
            animated: animated
        )
    }

    final class Leaf: UIHostingController<AnyView> {
        var index = 0
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: FootprintPageCurl
        private var leaves: [Int: Leaf] = [:]

        init(_ parent: FootprintPageCurl) { self.parent = parent }

        func leaf(at index: Int) -> Leaf {
            if let leaf = leaves[index] { return leaf }
            let leaf = Leaf(rootView: parent.page(index))
            leaf.index = index
            leaf.view.backgroundColor = UIColor(FootprintRoomPalette.bookRoom)
            leaves[index] = leaf
            return leaf
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let leaf = viewController as? Leaf, leaf.index > 0 else { return nil }
            return self.leaf(at: leaf.index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let leaf = viewController as? Leaf, leaf.index < parent.count - 1 else { return nil }
            return self.leaf(at: leaf.index + 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let leaf = pageViewController.viewControllers?.first as? Leaf else { return }
            parent.index = leaf.index
        }
    }
}
