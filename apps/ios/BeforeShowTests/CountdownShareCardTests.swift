import CoreImage
import XCTest
@testable import BeforeShow

/// 倒计时分享卡：开场前在「当前」截图时浮出；卡上的码扫出来就是这场现场，聊天软件压缩过也能扫。
@MainActor
final class CountdownShareCardTests: XCTestCase {
    func testOnlyBeforeDoors() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let show = try Show(name: "A", date: start, startTime: start)
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(-5 * 86_400))))
        XCTAssertTrue(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(-3_600))))
        XCTAssertFalse(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(600))))
        XCTAssertFalse(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(2 * 86_400))))

        show.markCanceled()
        XCTAssertFalse(CountdownShareExport.isAvailable(HomeHeroSnapshot(show: show, now: start.addingTimeInterval(-5 * 86_400))))
    }

    func testScreenshotOffersTheCardOnlyWhenTheCountdownIsOnScreen() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let show = try Show(name: "A", date: start, startTime: start)
        let before = start.addingTimeInterval(-5 * 86_400)
        XCTAssertTrue(CountdownScreenshotShare.offers(show, isVisible: true, now: before))
        XCTAssertFalse(CountdownScreenshotShare.offers(show, isVisible: false, now: before), "A sheet or another tab is on screen")
        XCTAssertFalse(CountdownScreenshotShare.offers(nil, isVisible: true, now: before))
        XCTAssertFalse(CountdownScreenshotShare.offers(show, isVisible: true, now: start.addingTimeInterval(600)))
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
        XCTAssertEqual(card.cgImage?.width, 1_080)
        XCTAssertEqual(card.cgImage?.height, 1_920)

        // Chat apps resend pictures smaller and as JPEG.
        for (width, quality) in [(1_080.0, 1.0), (720.0, 0.6)] {
            let scanned = try XCTUnwrap(scan(recompressed(card, width: width, quality: quality)), "no code at \(width)")
            let draft = try XCTUnwrap(ShowShareLink.draft(from: XCTUnwrap(URL(string: scanned))))
            XCTAssertEqual(draft.name, show.name)
            XCTAssertEqual(draft.startTime, Date(timeIntervalSince1970: start.timeIntervalSince1970.rounded()))
            XCTAssertEqual(draft.coverImageURL, show.coverImageURL)
        }
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
