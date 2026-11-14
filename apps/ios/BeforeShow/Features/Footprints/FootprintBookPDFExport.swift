import SwiftUI

/// The whole memory book as a PDF, one page per leaf, the way it reads on screen without the buttons.
@MainActor
enum FootprintBookPDFExport {
    static let pageSize = CGSize(width: 402, height: 874)

    static func render(book: FootprintBook, archive: FootprintArchiveSnapshot, covers: [UUID: FootprintCover]) async -> URL? {
        await FootprintCoverExportWarmup.warm(covers: covers)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(BSLocalization.text("回忆册") + ".pdf")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for index in book.pages.indices {
            let page = FootprintBookPageContent(
                book: book,
                archive: archive,
                covers: covers,
                pageIndex: index,
                turner: FootprintBookTurner(index: index, number: book.pageNumber(at: index), isLast: index == book.pages.count - 1, go: { _ in }, close: {}),
                export: nil
            )
            .environment(\.footprintBookPrinting, true)
            .frame(width: pageSize.width, height: pageSize.height)
            .background(FootprintRoomPalette.bookRoom)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }
}
