import CoreImage
import XCTest
@testable import BeforeShow

/// 现场分享卡：详情里分享出去的海报。开场前和开场中可以发，散场后不行；码扫出来就是这场现场。
@MainActor
final class CountdownShareCardTests: XCTestCase {
    func testAvailableUntilTheShowIsOver() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let show = try Show(name: "A", date: start, startTime: start)
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(-5 * 86_400))))
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(-3_600))))
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(600))), "Still on during the show")
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(2 * 86_400))), "Ended shows still share")

        show.markCanceled()
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(-5 * 86_400))))
    }

    func testCodeOnTheCardAddsTheShow() async throws {
        let start = Date().addingTimeInterval(12 * 86_400)
        let show = try Show(
            name: "五月天 回到那一天 25周年巡回演唱会 上海站",
            date: start,
            startTime: start,
            timeZoneIdentifier: "Asia/Shanghai",
            city: "上海",
            venueName: "上海体育场",
            artists: (1...50).map { ArtistSlot(name: "乐队\($0)", avatarURL: nil) },
            coverImageURL: "https://img.alicdn.com/imgextra/i3/2251059038/O1CN01AbCdEfGh1TmM6Hk0i_!!2251059038.jpg"
        )
        let rendered = await CountdownShareExport.renderImage(show: show, snapshot: HomeHeroSnapshot(show: show, now: .now))
        let card = try XCTUnwrap(rendered)
        // The cover may already be saved on this device; the card is sized by whatever poster it drew.
        let poster = ShowCoverReference.url(show.coverImageURL).flatMap { ShowCoverImageCache.shared.persistedImage(for: $0) }
        let size = CountdownShareExport.renderSize(style: .classic, poster: poster)
        XCTAssertEqual(card.cgImage?.width, Int(size.width * CountdownShareExport.renderScale))
        XCTAssertEqual(card.cgImage?.height, Int(size.height * CountdownShareExport.renderScale))

        // Chat apps resend pictures smaller and as JPEG.
        for (width, quality) in [(1_080.0, 1.0), (720.0, 0.6)] {
            let scanned = try XCTUnwrap(scan(recompressed(card, width: width, quality: quality)), "no code at \(width)")
            let draft = try XCTUnwrap(ShowShareLink.draft(from: XCTUnwrap(URL(string: scanned))))
            XCTAssertEqual(draft.name, show.name)
            XCTAssertEqual(draft.startTime, Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded()))
            XCTAssertEqual(draft.coverImageURL, show.coverImageURL)
        }
    }

    func testPosterCardKeepsTheWholePosterAtRuleWidth() {
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { _ in }
        let width = CountdownSharePosterLayout.contentWidth
        XCTAssertEqual(CountdownSharePosterLayout.posterHeight(poster: tall), width * 1.5)
        XCTAssertEqual(
            CountdownShareExport.renderSize(style: .classic, poster: tall).height,
            CountdownSharePosterLayout.height(poster: tall)
        )
        let scroll = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 500)).image { _ in }
        XCTAssertEqual(CountdownSharePosterLayout.posterHeight(poster: scroll), width * 1.6, "Long images are capped")
        XCTAssertEqual(CountdownShareExport.renderSize(style: .stub, poster: tall), CountdownShareExport.renderSize)
    }

    private func recompressed(_ image: UIImage, width: CGFloat, quality: CGFloat) throws -> CGImage {
        let size = CGSize(width: width, height: width * image.size.height / image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        let jpeg = try XCTUnwrap(resized.jpegData(compressionQuality: quality))
        return try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
    }

    private func scan(_ image: CGImage) throws -> String? {
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        return detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
