import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import BeforeShow

@MainActor
final class TimetableExperienceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    func testLargeMatrixOnlyResolvesAvatarsNearTheViewportAndLoadsScrolledCards() async throws {
        let start = date(2026, 10, 18, 10, 0)
        var stages: [TimetableStage] = []
        for lane in 0..<12 {
            var performances: [TimetablePerformance] = []
            for slot in 0..<24 {
                performances.append(try TimetablePerformance(
                    artistName: "Artist \(lane)-\(slot)",
                    startsAt: start.addingTimeInterval(Double(slot * 30 * 60)),
                    endsAt: start.addingTimeInterval(Double((slot + 1) * 30 * 60))
                ))
            }
            stages.append(try TimetableStage(name: "Stage \(lane)", sortOrder: lane, performances: performances))
        }
        let day = try TimetableDay(date: date(2026, 10, 18, 0, 0), stages: stages)
        context.insert(day)
        var resolvedNames: [String] = []
        let view = TimetableStageMatrixView(
            day: day, now: start.addingTimeInterval(-3600), timeZone: TimeZone(identifier: "Asia/Tokyo")!,
            wantOnly: false, canReturnToNow: .constant(false), returnToNowRequest: 0,
            avatarURL: { resolvedNames.append($0.artistName); return nil },
            onSelectPerformance: { _ in }, onToggleInterested: { $0.isInterested.toggle() },
            onAddPerformance: { _, _ in }, onManage: {}
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        let host = UIHostingController(rootView: view.modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let initiallyResolved = Set(resolvedNames)
        print("Matrix initial: \(initiallyResolved.count) of \(day.performances.count) artists, \(resolvedNames.count) resolutions")
        XCTAssertTrue(initiallyResolved.contains("Artist 0-0"))
        XCTAssertLessThan(initiallyResolved.count, day.performances.count / 2,
                          "Opening the matrix must not prepare every offscreen card")
        XCTAssertFalse(initiallyResolved.contains("Artist 8-18"))

        func scrollViews(in view: UIView) -> [UIScrollView] {
            let own = (view as? UIScrollView).map { [$0] } ?? []
            return own + view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scrolls = scrollViews(in: host.view)
        let vertical = try XCTUnwrap(scrolls.first { $0.contentSize.height > $0.bounds.height + 500 })
        let horizontal = try XCTUnwrap(scrolls.first { $0.contentSize.width > $0.bounds.width + 500 })
        resolvedNames = []
        vertical.setContentOffset(CGPoint(x: 0, y: 1100), animated: false)
        horizontal.setContentOffset(CGPoint(x: 960, y: 0), animated: false)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(resolvedNames.contains("Artist 8-18"), "Scrolling in both axes must load newly visible cards")
        XCTAssertLessThan(Set(resolvedNames).count, day.performances.count / 2)
        print("Matrix scroll: \(Set(resolvedNames).count) artists, \(resolvedNames.count) resolutions")
        resolvedNames = []
        vertical.setContentOffset(CGPoint(x: 0, y: 1104), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(resolvedNames.isEmpty, "Small scroll movements must not rebuild cards inside the render buffer")

        host.view.layoutIfNeeded()
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Large matrix after scrolling"
        attachment.lifetime = .keepAlways
        add(attachment)

        let visiblePerformance = try XCTUnwrap(stages[8].performances.first { $0.artistName == "Artist 8-18" })
        visiblePerformance.artistName = "Updated Artist"
        visiblePerformance.isInterested = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(resolvedNames.contains("Updated Artist"), "Viewport rendering must still observe performance edits")
    }

    func testFortyMinuteLongNameCardKeepsPreviewControlVisible() throws {
        let start = date(2026, 10, 18, 14, 0)
        let card = TimetableMatrixLayout.Card(
            id: UUID(), artistName: "夜晚做决定 No Decision At Night", laneIndex: 0,
            top: 0, height: 40 * TimetableMatrixLayout.pointsPerMinute - TimetableMatrixLayout.cardSpacing,
            startsAt: start, endsAt: start.addingTimeInterval(40 * 60),
            status: .upcoming, isInterested: false
        )
        let player = TimetablePreviewPlayer.shared
        player.stop()
        defer { player.stop() }

        func render() throws -> Data {
            let view = TimetableMatrixCard(
                card: card, width: 170, avatarURL: nil, artistID: nil,
                isGhost: false, nowOffset: nil, stageTint: .purple,
                timeZone: TimeZone(identifier: "Asia/Taipei")!, onSelect: {}, onToggle: {}
            )
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            return try XCTUnwrap(renderer.uiImage?.pngData())
        }

        let idle = try render()
        // The synchronous loading state changes only the preview control.
        // Rendering and cancellation finish before its network task can run.
        player.toggle(performanceID: card.id, artistName: card.artistName, artistID: nil)
        XCTAssertTrue(player.isLoading(performanceID: card.id))
        let loading = try render()
        XCTAssertNotEqual(idle, loading, "A short card must visibly update its preview control, even with a long artist name")
        for (name, data) in [("Card idle", idle), ("Card loading", loading)] {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - 1. Interested State Persistence

    func testInterestedStateCanBeToggledAndPersistedIndependently() throws {
        let showDate = date(2026, 8, 15, 10, 0)
        let show = try Show(
            name: "Summer Sonic 2026",
            date: showDate,
            startTime: showDate,
            timeZoneIdentifier: "Asia/Tokyo"
        )
        context.insert(show)

        let perf1 = try TimetablePerformance(
            artistName: "NewJeans",
            startsAt: date(2026, 8, 15, 13, 0),
            endsAt: date(2026, 8, 15, 14, 0)
        )
        let perf2 = try TimetablePerformance(
            artistName: "Blur",
            startsAt: date(2026, 8, 15, 19, 0),
            endsAt: date(2026, 8, 15, 20, 30)
        )
        let stage = try TimetableStage(name: "Marine Stage", performances: [perf1, perf2])
        let day = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Tokyo", days: [day])
        timetable.show = show
        show.timetable = timetable
        context.insert(timetable)
        try context.save()

        XCTAssertFalse(perf1.isInterested)
        XCTAssertFalse(perf2.isInterested)

        // Toggle perf1 to interested
        perf1.isInterested = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimetablePerformance>())
        let fetchedPerf1 = fetched.first { $0.id == perf1.id }!
        let fetchedPerf2 = fetched.first { $0.id == perf2.id }!
        XCTAssertTrue(fetchedPerf1.isInterested)
        XCTAssertFalse(fetchedPerf2.isInterested)

        // Toggle perf1 back
        perf1.isInterested = false
        try context.save()
        XCTAssertFalse(perf1.isInterested)
    }

    // MARK: - 5. Multi-day, Multi-stage, Long Artist Names Robustness

    func testMultiDayMultiStageTimetableWithLongArtistNames() throws {
        let tokyo = "Asia/Tokyo"
        let longArtist1 = "King Gizzard & The Lizard Wizard"
        let longArtist2 = "Godspeed You! Black Emperor"
        let longArtist3 = "And So I Watch You From Afar"

        // Day 1
        let d1p1 = try TimetablePerformance(artistName: longArtist1, startsAt: date(2026, 8, 15, 14, 0), endsAt: date(2026, 8, 15, 15, 30))
        let d1p2 = try TimetablePerformance(artistName: longArtist2, startsAt: date(2026, 8, 15, 18, 0), endsAt: date(2026, 8, 15, 19, 30))
        let d1p3 = try TimetablePerformance(artistName: "Toe", startsAt: date(2026, 8, 15, 18, 30), endsAt: date(2026, 8, 15, 19, 45))

        let stageA = try TimetableStage(name: "Mountain Stage", performances: [d1p1, d1p2])
        let stageB = try TimetableStage(name: "Sonic Stage", performances: [d1p3])
        let day1 = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stageA, stageB])

        // Day 2
        let d2p1 = try TimetablePerformance(artistName: longArtist3, startsAt: date(2026, 8, 16, 15, 0), endsAt: date(2026, 8, 16, 16, 0))
        let stageC = try TimetableStage(name: "Rainbow Stage", performances: [d2p1])
        let day2 = try TimetableDay(date: date(2026, 8, 16, 0, 0), stages: [stageC])

        let timetable = try Timetable(timeZoneIdentifier: tokyo, days: [day1, day2])
        XCTAssertEqual(timetable.orderedDays.count, 2)
        XCTAssertEqual(day1.orderedStages.count, 2)
        XCTAssertEqual(day1.performances.count, 3)
    }

    // MARK: - 6. Usability without any Interested

    func testTimetableRemainsFullyUsableWithZeroInterestedPerformances() throws {
        let p1 = try TimetablePerformance(artistName: "Oasis", startsAt: date(2026, 8, 15, 14, 0), endsAt: date(2026, 8, 15, 15, 0))
        let p2 = try TimetablePerformance(artistName: "Pulp", startsAt: date(2026, 8, 15, 19, 0), endsAt: date(2026, 8, 15, 20, 30))
        let stage = try TimetableStage(name: "Main Stage", performances: [p1, p2])
        let day = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "Asia/Tokyo", days: [day])

        // Verify zero interested
        XCTAssertEqual(day.performances.filter(\.isInterested).count, 0)

        // All timetable schedules are accessible
        XCTAssertEqual(timetable.orderedDays.first?.performances.count, 2)
        XCTAssertEqual(timetable.orderedDays.first?.orderedStages.first?.orderedPerformances.count, 2)
    }

    // MARK: - 8. In-Situ Matrix Editing & Stage Migration

    func testInSituPerformanceMutationsAndStageMoving() throws {
        let p1 = try TimetablePerformance(artistName: "Radiohead", startsAt: date(2026, 8, 15, 18, 0), endsAt: date(2026, 8, 15, 19, 0))
        let stage1 = try TimetableStage(name: "Moon Stage", sortOrder: 0, performances: [p1])
        p1.stage = stage1

        let p2 = try TimetablePerformance(artistName: "Massive Attack", startsAt: date(2026, 8, 15, 19, 30), endsAt: date(2026, 8, 15, 20, 30))
        let stage2 = try TimetableStage(name: "Sun Stage", sortOrder: 1, performances: [p2])
        p2.stage = stage2

        let day = try TimetableDay(date: date(2026, 8, 15, 0, 0), stages: [stage1, stage2])
        stage1.day = day
        stage2.day = day

        // 1. Shift time by +10 minutes
        p1.shiftTimes(by: 600)
        XCTAssertEqual(p1.startsAt, date(2026, 8, 15, 18, 10))
        XCTAssertEqual(p1.endsAt, date(2026, 8, 15, 19, 10))

        // 2. Move p1 to stage2
        p1.moveTo(stage: stage2)
        XCTAssertEqual(p1.stage?.id, stage2.id)

        // 3. Rename stage
        try stage1.updateName("Earth Stage")
        XCTAssertEqual(stage1.name, "Earth Stage")

        // 4. Update details
        try p1.updateDetails(
            artistName: "The Smile",
            startsAt: date(2026, 8, 15, 18, 30),
            endsAt: date(2026, 8, 15, 19, 45)
        )
        XCTAssertEqual(p1.artistName, "The Smile")
        XCTAssertEqual(p1.startsAt, date(2026, 8, 15, 18, 30))
        XCTAssertEqual(p1.endsAt, date(2026, 8, 15, 19, 45))

        // 5. Add stage to day
        let newStage = try day.addStage(name: "Star Stage")
        XCTAssertEqual(newStage.name, "Star Stage")
        XCTAssertTrue(day.stages.contains { $0.id == newStage.id })
    }

    func testMatrixLayoutYToDateMapping() throws {
        let dayStart = date(2026, 8, 15, 12, 0)
        let perf = try TimetablePerformance(
            artistName: "Artist",
            startsAt: date(2026, 8, 15, 14, 0),
            endsAt: date(2026, 8, 15, 15, 0)
        )
        let stage = try TimetableStage(name: "Main", performances: [perf])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let layout = TimetableMatrixLayout(
            stages: [.init(id: stage.id, name: stage.name, performances: [
                .init(id: perf.id, artistName: perf.artistName, startsAt: perf.startsAt, endsAt: perf.endsAt, isInterested: false)
            ])],
            now: dayStart,
            calendar: cal
        )

        let yStart = layout.y(for: layout.start)
        XCTAssertEqual(yStart, TimetableMatrixLayout.topInset, accuracy: 0.1)

        let mappedStart = layout.date(for: yStart)
        XCTAssertEqual(mappedStart.timeIntervalSince(layout.start), 0, accuracy: 1)

        let oneHourLater = layout.start.addingTimeInterval(3600)
        let yOneHour = layout.y(for: oneHourLater)
        XCTAssertEqual(yOneHour, TimetableMatrixLayout.topInset + 60 * TimetableMatrixLayout.pointsPerMinute, accuracy: 0.1)
        let mappedHour = layout.date(for: yOneHour)
        XCTAssertEqual(mappedHour.timeIntervalSince(oneHourLater), 0, accuracy: 1)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: components)!
    }
}
