import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ShowVideoTests: XCTestCase {
    func testShowVideosAreGroupedByCategoryAndSortedWithinEachGroup() throws {
        let show = try makeShow()
        let otherShow = try makeShow(name: "另一场")
        let container = try makeContainer()
        container.mainContext.insert(show)
        container.mainContext.insert(otherShow)

        let laterStarter = try ShowVideo(
            showID: show.id,
            category: .starter,
            title: "入门第二条",
            sourceName: "相信音乐官方",
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BVstarter2")!,
            durationText: "12:30",
            reason: "第二条",
            sortOrder: 20
        )
        let firstStarter = try ShowVideo(
            showID: show.id,
            category: .starter,
            title: "入门第一条",
            sourceName: "相信音乐官方",
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BVstarter1")!,
            durationText: "48:12",
            reason: "第一条",
            sortOrder: 10
        )
        let preShow = try ShowVideo(
            showID: show.id,
            category: .preShow,
            title: "演前必看",
            sourceName: "Live精选",
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BVpreshow")!,
            durationText: "6:25",
            reason: "马上要去现场",
            sortOrder: 0
        )
        let other = try ShowVideo(
            showID: otherShow.id,
            category: .starter,
            title: "不应该出现",
            sourceName: "其他来源",
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BVother")!,
            durationText: "1:00",
            reason: "另一场",
            sortOrder: 0
        )

        [laterStarter, firstStarter, preShow, other].forEach(container.mainContext.insert)
        try container.mainContext.save()

        let videos = try container.mainContext.fetch(FetchDescriptor<ShowVideo>())
        let sections = ShowVideoLibraryService().sections(for: show.id, videos: videos)

        XCTAssertEqual(sections.map(\.category), ShowVideoCategory.allCases)
        XCTAssertEqual(sections.first(where: { $0.category == .starter })?.videos.map(\.title), [
            "入门第一条",
            "入门第二条"
        ])
        XCTAssertEqual(sections.first(where: { $0.category == .preShow })?.videos.map(\.title), ["演前必看"])
        XCTAssertEqual(sections.first(where: { $0.category == .highEnergy })?.videos, [])
        XCTAssertEqual(sections.first(where: { $0.category == .deepDive })?.videos, [])
    }

    func testShowVideoPresentationUsesFinalChineseCategoriesAndQuietBilibiliCards() throws {
        let video = try ShowVideo(
            showID: UUID(),
            category: .highEnergy,
            title: "万人合唱《倔强》现场",
            sourceName: "现场记录员",
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BVhighenergy")!,
            durationText: "5:44",
            reason: "这段适合提前感受现场的爆发力。",
            sortOrder: 0
        )

        XCTAssertEqual(ShowVideoCategory.allCases.map(\.title), [
            "入门先看",
            "演前必看",
            "名场面 / 高能现场",
            "深入补课"
        ])

        let presentation = ShowVideoCardPresentation(video: video)

        XCTAssertEqual(presentation.sourceText, "B站 · 现场记录员")
        XCTAssertEqual(presentation.title, "万人合唱《倔强》现场")
        XCTAssertEqual(presentation.reason, "这段适合提前感受现场的爆发力。")
        XCTAssertFalse(presentation.visibleTexts.contains("去 B站观看"))
        XCTAssertFalse(presentation.visibleTexts.contains("App 内打开 B站视频"))
        XCTAssertFalse(presentation.visibleTexts.contains("YouTube"))
        XCTAssertFalse(presentation.visibleTexts.contains("官方频道观看"))
    }

    func testSelectingShowVideoOpensAndClosesInAppWebViewState() throws {
        let video = try ShowVideo(
            showID: UUID(),
            category: .preShow,
            title: "本轮巡演上海站精选现场",
            sourceName: "Live精选",
            bilibiliURL: URL(string: "https://www.bilibili.com/video/BVpreshow")!,
            durationText: "6:25",
            reason: "如果你马上要去这场，建议先看这一版现场。",
            sortOrder: 0
        )
        var navigator = ShowVideoWebViewNavigator()

        navigator.open(video)

        XCTAssertEqual(navigator.presentedVideo?.id, video.id)
        XCTAssertEqual(navigator.navigationTitle, "本轮巡演上海站精选现场")
        XCTAssertEqual(navigator.presentedURL, URL(string: "https://www.bilibili.com/video/BVpreshow")!)

        navigator.close()

        XCTAssertNil(navigator.presentedVideo)
        XCTAssertNil(navigator.presentedURL)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self,
            ShowVideo.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeShow(name: String = "测试现场") throws -> Show {
        try Show(name: name, date: Date(timeIntervalSince1970: 1_779_552_000), type: .concert)
    }
}
