import UIKit

/// The printed insert: spine band with the title, then the cover.
enum ShelfInsertArt {
    static let size = CGSize(width: 416, height: 376)
    static let band: CGFloat = 45

    nonisolated static func draw(title: String, year: String?, cover: UIImage) -> CGImage? {
        // Cover, filling the rest of the insert.
        let area = CGRect(x: band, y: 0, width: size.width - band, height: size.height)
        let scale = max(area.width / cover.size.width, area.height / cover.size.height)
        let drawn = CGSize(width: (cover.size.width * scale).rounded(.up), height: (cover.size.height * scale).rounded(.up))
        // Decoded once, at the size it is drawn: the spine's tone and the print read the same small bitmap.
        let cover = cover.preparingThumbnail(of: drawn) ?? cover
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Cover art is sRGB; a wide-colour bitmap would only double the memory every kept print holds.
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let tone = ListeningArtworkTone.average(cover)
            let spine = tone.map(ListeningArtworkTone.spine(for:))
            let fill = spine?.fill ?? UIColor(white: 0.12, alpha: 1)
            let ink = spine?.isLight == true ? UIColor.black.withAlphaComponent(0.8) : .white
            fill.setFill()
            context.fill(CGRect(x: 0, y: 0, width: band, height: size.height))

            context.cgContext.saveGState()
            context.cgContext.clip(to: area)
            cover.draw(in: CGRect(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
            context.cgContext.restoreGState()

            // Title up the spine, year at its foot.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .heavy), .kern: 1.6,
                .foregroundColor: ink, .paragraphStyle: paragraph,
            ]
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: band / 2, y: size.height * 0.42)
            context.cgContext.rotate(by: -.pi / 2)
            (title as NSString).draw(in: CGRect(x: -132, y: -11, width: 264, height: 22), withAttributes: titleAttributes)
            context.cgContext.restoreGState()
            if let year {
                let yearAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink, .paragraphStyle: paragraph,
                ]
                (year as NSString).draw(in: CGRect(x: 0, y: size.height - 40, width: band, height: 18), withAttributes: yearAttributes)
            }
        }
        return image.cgImage
    }
}
