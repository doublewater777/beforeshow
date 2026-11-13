import SwiftUI
import Vision
import XCTest
@testable import BeforeShow

/// 每张分享图都要带一处能在 App Store 搜到的本地化 App 名。
@MainActor
final class ShareCardBylineTests: XCTestCase {
    func testBylineIsTheStoreNameInEachLanguage() throws {
        let key = "开场前 · 分享图署名"
        let expected = ["zh-Hans": "开场前", "zh-Hant": "開場前", "en": "BeforeShow"]
        for (language, name) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), name, language)
        }
        XCTAssertEqual(BSShareByline.appName, "开场前")
    }

    func testDispersalCardCarriesByline() throws {
        let show = try makeShow()
        let image = try XCTUnwrap(DispersalCeremonyShareExport.renderImage(
            show: show, identity: identity(show), rating: 5, note: "灯亮得特别慢"
        ))
        try assertByline(in: image)
    }

    func testMemoryCardCarriesByline() throws {
        let show = try makeShow()
        let card = FootprintMemoryShareCard(show: show, identity: identity(show), materials: [], images: [:])
        try assertByline(in: render(card, size: CGSize(width: 360, height: 640)))
    }

    func testFootprintPageExportCarriesByline() throws {
        let page = FootprintPageExportView(title: "这些年", kicker: "") { Color.clear.frame(height: 200) }
        try assertByline(in: render(page, size: CGSize(width: FootprintPageExportLayout.width, height: 360)))
    }

    func testTimetablePosterCarriesByline() throws {
        let poster = TimetableFullPoster(
            identity: TimetableShareIdentity(name: "草莓音乐节", coverURL: nil),
            days: [],
            avatarURL: { _ in nil },
            timeZone: .current
        )
        try assertByline(in: render(poster.environment(\.colorScheme, .dark), size: nil))
    }

    func testCountdownCardCarriesByline() async throws {
        let start = Date().addingTimeInterval(12 * 86_400)
        let show = try Show(name: "草东没有派对 · 如常", date: start, startTime: start, city: "杭州", venueName: "杭州奥体中心体育馆")
        let image = await CountdownShareExport.renderImage(show: show, snapshot: HomeHeroSnapshot(show: show, now: .now))
        try assertByline(in: XCTUnwrap(image))
    }

    func testTornTicketCarriesByline() throws {
        let face = FootprintTicketFace(show: try makeShow(), ordinal: 37, lights: [.orange, .pink], isExport: true)
        try assertByline(in: render(face, size: nil))
    }

    // MARK: Helpers

    private func makeShow() throws -> Show {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        let show = try Show(name: "草东没有派对 · 如常", date: start, startTime: start, city: "杭州", venueName: "杭州奥体中心体育馆")
        show.markEnded(at: start.addingTimeInterval(3 * 3600))
        return show
    }

    private func identity(_ show: Show) -> FootprintDetailIdentity {
        FootprintDetailIdentityBuilder.make(show: show, archive: FootprintArchiveSnapshot.identityOnly(shows: [show]))
    }

    private func render<V: View>(_ view: V, size: CGSize?) throws -> UIImage {
        let renderer = ImageRenderer(content: view)
        if let size {
            renderer.proposedSize = ProposedViewSize(size)
        }
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage)
    }

    private func assertByline(in image: UIImage, file: StaticString = #filePath, line: UInt = #line) throws {
        let cgImage = try XCTUnwrap(image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        XCTAssertTrue(
            lines.contains { $0.contains(BSShareByline.appName) },
            "no byline in \(lines)",
            file: file,
            line: line
        )
    }
}
