import Foundation
import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import BeforeShow

@MainActor
final class TimetableSmartRecognitionTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TimetableSmartRecognitionTests_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Quota Tests

    func testQuota_initialFreeUserHasLifetimeQuota() {
        let quota = TimetableRecognitionQuota(userDefaults: testDefaults)
        XCTAssertEqual(quota.usedCount, 0)
        XCTAssertEqual(quota.remainingFreeCount(isPro: false), 2)
        XCTAssertTrue(quota.canRecognize(isPro: false))
        XCTAssertEqual(quota.badgeText(isPro: false), "免费剩余 2 次")
    }

    func testQuota_consumingFreeQuotaDecrementsRemaining() {
        var quota = TimetableRecognitionQuota(userDefaults: testDefaults)
        quota.consumeQuotaIfFree(isPro: false)
        XCTAssertEqual(quota.usedCount, 1)
        XCTAssertEqual(quota.remainingFreeCount(isPro: false), 1)
        XCTAssertTrue(quota.canRecognize(isPro: false))
        XCTAssertEqual(quota.badgeText(isPro: false), "免费剩余 1 次")

        quota.consumeQuotaIfFree(isPro: false)
        XCTAssertEqual(quota.usedCount, 2)
        XCTAssertEqual(quota.remainingFreeCount(isPro: false), 0)
        XCTAssertFalse(quota.canRecognize(isPro: false))
        XCTAssertTrue(quota.badgeText(isPro: false).contains("已用完"))
    }

    func testQuota_proUserHasUnlimitedQuota() {
        var quota = TimetableRecognitionQuota(userDefaults: testDefaults)
        XCTAssertEqual(quota.remainingFreeCount(isPro: true), .max)
        XCTAssertTrue(quota.canRecognize(isPro: true))
        XCTAssertEqual(quota.badgeText(isPro: true), "Pro 不限次")

        quota.consumeQuotaIfFree(isPro: true)
        XCTAssertEqual(quota.usedCount, 0)
        XCTAssertTrue(quota.canRecognize(isPro: true))
    }

    // MARK: - Remote Service Tests

    private final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
        var handler: ((URLRequest) throws -> (Data, URLResponse))?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return try handler(request)
        }
    }

    func testRemoteService_successParsesDocument() async throws {
        let mockSession = MockURLSession()
        let expectedJSON = """
        {
            "ok": true,
            "document": {
                "version": 1,
                "timeZone": "Asia/Shanghai",
                "days": [
                    {
                        "date": "2026-10-17",
                        "stages": [
                            {
                                "name": "草莓舞台",
                                "performances": [
                                    {
                                        "artist": "落日飞车",
                                        "start": "19:00",
                                        "end": "20:00"
                                    }
                                ]
                            }
                        ]
                    }
                ]
            },
            "model": "qwen3.7-flash"
        }
        """

        mockSession.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(expectedJSON.utf8), response)
        }

        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-id", appSignature: "test-sig"),
            session: mockSession
        )

        let service = RemoteTimetableRecognitionService(client: client)
        let sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }

        let doc = try await service.recognize(images: [sampleImage])
        XCTAssertEqual(doc.version, 1)
        XCTAssertEqual(doc.timeZone, "Asia/Shanghai")
        XCTAssertEqual(doc.days.count, 1)
        XCTAssertEqual(doc.days[0].stages[0].performances[0].artist, "落日飞车")
    }

    func testRemoteService_rateLimitedThrowsError() async {
        let mockSession = MockURLSession()
        let rateLimitJSON = """
        {
            "ok": false,
            "error": {
                "code": "RATE_LIMITED",
                "message": "Too many requests"
            }
        }
        """

        mockSession.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(rateLimitJSON.utf8), response)
        }

        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-id", appSignature: "test-sig"),
            session: mockSession
        )

        let service = RemoteTimetableRecognitionService(client: client)
        let sampleImage = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }

        do {
            _ = try await service.recognize(images: [sampleImage])
            XCTFail("Expected rate limited error")
        } catch let err as RemoteTimetableRecognitionError {
            XCTAssertEqual(err, .rateLimited)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Date Alignment Tests

    func testTimetableShift_shiftsDaysAndPerformancesToMatchTargetDate() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseDate = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let showDate = cal.date(byAdding: .day, value: 3, to: baseDate)!

        let show = try Show(name: "Festival", date: showDate, startTime: showDate.addingTimeInterval(14 * 3600))
        let p1 = try TimetablePerformance(
            artistName: "Band A",
            startsAt: baseDate.addingTimeInterval(15 * 3600),
            endsAt: baseDate.addingTimeInterval(16 * 3600)
        )
        let stage = try TimetableStage(name: "Main", performances: [p1])
        let day1 = try TimetableDay(date: baseDate, stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "UTC", days: [day1])

        XCTAssertFalse(timetable.matchesDates(of: show))

        // Shift timetable to match show date
        try timetable.shift(toStartDate: show.effectiveDate, for: show)

        XCTAssertTrue(timetable.matchesDates(of: show))
        XCTAssertFalse(timetable.needsDateConfirmation)
        XCTAssertEqual(cal.startOfDay(for: day1.date), cal.startOfDay(for: showDate))
        XCTAssertEqual(p1.startsAt, showDate.addingTimeInterval(15 * 3600))
        XCTAssertEqual(p1.endsAt, showDate.addingTimeInterval(16 * 3600))
    }

    func testShowAlignDate_updatesShowEffectiveDateAndTimesToMatchTimetable() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let showDate = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let timetableDate = cal.date(byAdding: .day, value: 2, to: showDate)!

        let show = try Show(name: "Festival", date: showDate, startTime: showDate.addingTimeInterval(18 * 3600))
        let p1 = try TimetablePerformance(
            artistName: "Band B",
            startsAt: timetableDate.addingTimeInterval(19 * 3600),
            endsAt: timetableDate.addingTimeInterval(20 * 3600)
        )
        let stage = try TimetableStage(name: "Electronic", performances: [p1])
        let day1 = try TimetableDay(date: timetableDate, stages: [stage])
        let timetable = try Timetable(timeZoneIdentifier: "UTC", days: [day1])

        XCTAssertFalse(timetable.matchesDates(of: show))

        // Align show to match timetable
        show.alignDate(with: timetable)

        XCTAssertTrue(timetable.matchesDates(of: show))
        XCTAssertFalse(timetable.needsDateConfirmation)
        XCTAssertEqual(cal.startOfDay(for: show.date), cal.startOfDay(for: timetableDate))
        XCTAssertEqual(show.startTime, timetableDate.addingTimeInterval(18 * 3600))
    }

    func testShowAlignDate_singleDayShowExpandsToMultiDayTimetableWhenStartDateMatches() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1Date = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let day2Date = cal.date(byAdding: .day, value: 1, to: day1Date)!
        let day3Date = cal.date(byAdding: .day, value: 2, to: day1Date)!

        // User created a single-day show (e.g. only selected start day)
        let show = try Show(name: "Strawberry Festival", date: day1Date, startTime: day1Date.addingTimeInterval(14 * 3600))
        XCTAssertNil(show.endDate)

        let p1 = try TimetablePerformance(artistName: "Artist A", startsAt: day1Date.addingTimeInterval(15 * 3600), endsAt: day1Date.addingTimeInterval(16 * 3600))
        let p2 = try TimetablePerformance(artistName: "Artist B", startsAt: day2Date.addingTimeInterval(15 * 3600), endsAt: day2Date.addingTimeInterval(16 * 3600))
        let p3 = try TimetablePerformance(artistName: "Artist C", startsAt: day3Date.addingTimeInterval(15 * 3600), endsAt: day3Date.addingTimeInterval(16 * 3600))

        let d1 = try TimetableDay(date: day1Date, stages: [TimetableStage(name: "Main", performances: [p1])])
        let d2 = try TimetableDay(date: day2Date, stages: [TimetableStage(name: "Main", performances: [p2])])
        let d3 = try TimetableDay(date: day3Date, stages: [TimetableStage(name: "Main", performances: [p3])])
        let timetable = try Timetable(timeZoneIdentifier: "UTC", days: [d1, d2, d3])

        // When dates are aligned via alignDate, show.endDate must expand to day 3
        show.alignDate(with: timetable)

        XCTAssertEqual(show.endDate, day3Date)
        XCTAssertTrue(timetable.matchesDates(of: show))
        XCTAssertFalse(timetable.needsDateConfirmation)
    }

    func testCommitTimetable_automaticallyAlignsShowDates() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1Date = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let day2Date = cal.date(byAdding: .day, value: 1, to: day1Date)!

        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext

        let show = try Show(name: "Festival", date: day1Date, startTime: day1Date.addingTimeInterval(14 * 3600))
        context.insert(show)
        try context.save()

        let p1 = TimetableDraftPerformance(artistName: "Band 1", startsAt: day1Date.addingTimeInterval(14 * 3600), endsAt: day1Date.addingTimeInterval(15 * 3600))
        let p2 = TimetableDraftPerformance(artistName: "Band 2", startsAt: day2Date.addingTimeInterval(14 * 3600), endsAt: day2Date.addingTimeInterval(15 * 3600))
        let s1 = TimetableDraftStage(name: "Stage 1", performances: [p1])
        let s2 = TimetableDraftStage(name: "Stage 1", performances: [p2])
        let d1 = TimetableDraftDay(date: day1Date, stages: [s1])
        let d2 = TimetableDraftDay(date: day2Date, stages: [s2])
        let draft = TimetableDraft(timeZoneIdentifier: "UTC", days: [d1, d2])

        let coordinator = TimetableManagementCoordinator()
        let committed = await coordinator.commit(draft: draft, newImagesData: [], show: show, modelContext: context)

        XCTAssertTrue(committed)
        XCTAssertEqual(show.endDate, day2Date)
        XCTAssertNotNil(show.timetable)
        XCTAssertTrue(try XCTUnwrap(show.timetable?.matchesDates(of: show)))
        XCTAssertFalse(try XCTUnwrap(show.timetable?.needsDateConfirmation))
    }
}
