import XCTest
import SwiftData
import UserNotifications
@testable import BeforeShow

final class LiveActivityRemoteSyncServiceTests: XCTestCase {

    func testSyncPlanSuccessCompletesHandoverAndRevokesLocalNotification() async throws {
        let showID = UUID().uuidString
        let performanceID = UUID().uuidString
        let secondID = UUID().uuidString
        let scheduledStartsAt = Date().addingTimeInterval(3600) // 1 hour later

        let ledger = LiveActivityReminderLedger()
        let eventKey = PerformanceReminderEventKey(
            showID: showID,
            performanceID: performanceID,
            scheduledStartsAt: scheduledStartsAt
        )

        // Pre-condition: ledger has default local notification channel
        let initial = await ledger.record(for: eventKey)
        XCTAssertEqual(initial.channel, .localNotification)
        XCTAssertEqual(initial.status, .pending)

        let recorder = RevocationRecorder()
        let session = MockCloudSession(
            responseData: #"{"ok":true,"acceptedVersion":1,"planID":"plan-1"}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-dev", appSignature: "test-sig"),
            session: session
        )

        let service = LiveActivityRemoteSyncService(
            client: client,
            ledger: ledger,
            secretProvider: { "dummy-secret-32-chars-long-value" },
            notificationRevoker: { id in
                await recorder.record(id)
            }
        )

        var contentState = ShowLiveActivityAttributes.ContentState(
            showName: "Strawberry Festival",
            startDate: scheduledStartsAt
        )
        contentState.isReminderActive = true
        contentState.reminderPerformanceIDs = [performanceID]
        contentState.reminderStartsAt = scheduledStartsAt
        let secondStart = scheduledStartsAt.addingTimeInterval(300)
        let events: [LiveActivityReminderEvent] = [
            .init(performanceID: performanceID, startsAt: scheduledStartsAt),
            .init(performanceID: secondID, startsAt: secondStart)
        ]

        let step = LiveActivityTransitionStep(
            scheduledAt: scheduledStartsAt.addingTimeInterval(-900), // 15 mins before
            state: contentState, reminderEvents: events
        )
        let plan = LiveActivityBoundedTransitionPlan(
            planID: "plan-1",
            showID: showID,
            appInstanceID: "test-dev",
            activityPushToken: "token-hex",
            isProduction: false,
            version: 1,
            deadline: scheduledStartsAt.addingTimeInterval(7200),
            steps: [step]
        )

        // Sync at 30 minutes before show (before 15m trigger point)
        let now = scheduledStartsAt.addingTimeInterval(-1800)
        let success = await service.syncPlan(plan, now: now)

        XCTAssertTrue(success)
        let record = await ledger.record(for: eventKey)
        XCTAssertEqual(record.channel, .liveActivity)
        XCTAssertEqual(record.status, .handedOver)
        let revokedID = await recorder.revokedID
        XCTAssertEqual(revokedID, PerformanceReminderEventKey(showID: showID,
            performanceID: secondID, scheduledStartsAt: secondStart).notificationIdentifier)
        let secondRecord = await ledger.record(for: PerformanceReminderEventKey(showID: showID,
            performanceID: secondID, scheduledStartsAt: secondStart))
        XCTAssertEqual(secondRecord.status, .handedOver)
        let incorrectTime = await ledger.record(for: PerformanceReminderEventKey(showID: showID,
            performanceID: secondID, scheduledStartsAt: scheduledStartsAt))
        XCTAssertEqual(incorrectTime.channel, .localNotification)
    }

    func testSyncPlanNetworkFailurePreservesLocalNotificationFallback() async throws {
        let showID = UUID().uuidString
        let performanceID = UUID().uuidString
        let scheduledStartsAt = Date().addingTimeInterval(3600)

        let ledger = LiveActivityReminderLedger()
        let eventKey = PerformanceReminderEventKey(
            showID: showID,
            performanceID: performanceID,
            scheduledStartsAt: scheduledStartsAt
        )

        let recorder = RevocationRecorder()
        let session = MockCloudSession(
            responseData: Data(),
            statusCode: 500
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-dev", appSignature: "test-sig"),
            session: session
        )

        let service = LiveActivityRemoteSyncService(
            client: client,
            ledger: ledger,
            secretProvider: { "dummy-secret-32-chars-long-value" },
            notificationRevoker: { id in
                await recorder.record(id)
            }
        )

        var contentState = ShowLiveActivityAttributes.ContentState(
            showName: "Strawberry Festival",
            startDate: scheduledStartsAt
        )
        contentState.isReminderActive = true
        contentState.reminderPerformanceIDs = [performanceID]

        let plan = LiveActivityBoundedTransitionPlan(
            planID: "plan-1",
            showID: showID,
            appInstanceID: "test-dev",
            activityPushToken: "token-hex",
            isProduction: false,
            version: 1,
            deadline: scheduledStartsAt.addingTimeInterval(7200),
            steps: [LiveActivityTransitionStep(scheduledAt: scheduledStartsAt.addingTimeInterval(-900), state: contentState)]
        )

        let success = await service.syncPlan(plan, now: scheduledStartsAt.addingTimeInterval(-1800))
        XCTAssertFalse(success)

        // Local notification fallback preserved
        let record = await ledger.record(for: eventKey)
        XCTAssertEqual(record.channel, .localNotification)
        XCTAssertEqual(record.status, .pending)
        let revokedID = await recorder.revokedID
        XCTAssertNil(revokedID, "Local notification must not be revoked on failure")
    }

    func testRevokePlanSendsRequestSuccessfully() async throws {
        let session = MockCloudSession(
            responseData: #"{"ok":true,"revoked":true}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-dev", appSignature: "test-sig"),
            session: session
        )

        let service = LiveActivityRemoteSyncService(
            client: client,
            ledger: LiveActivityReminderLedger(),
            secretProvider: { "dummy-secret-32-chars-long-value" }
        )

        let success = await service.revokePlan(showID: "test-show-123")
        XCTAssertTrue(success)
    }

    func testLedgerPreventsReconciliationOfHandedOverNotification() async throws {
        let showID = UUID().uuidString
        let performanceID = UUID().uuidString
        let scheduledStartsAt = Date().addingTimeInterval(3600)

        let ledger = LiveActivityReminderLedger()
        let eventKey = PerformanceReminderEventKey(
            showID: showID,
            performanceID: performanceID,
            scheduledStartsAt: scheduledStartsAt
        )

        // Handover completed
        let didHandover = await ledger.completeHandover(eventKey: eventKey, planVersion: 1, now: Date())
        XCTAssertTrue(didHandover)

        // isHandedOverOrConsumed returns true for the notification identifier
        let isHandedOver = await ledger.isHandedOverOrConsumed(notificationIdentifier: eventKey.notificationIdentifier)
        XCTAssertTrue(isHandedOver)

        // Revoking to local restores pending state so it can be reconciled again
        let didRevoke = await ledger.revokeToLocal(eventKey: eventKey, now: Date())
        XCTAssertTrue(didRevoke)

        let isStillHandedOver = await ledger.isHandedOverOrConsumed(notificationIdentifier: eventKey.notificationIdentifier)
        XCTAssertFalse(isStillHandedOver)
    }

    func testRevokePlanRestoresFutureHandedOverRemindersToLocalNotification() async throws {
        let showID = UUID().uuidString
        let futurePerformanceID = UUID().uuidString
        let latePerformanceID = UUID().uuidString
        let now = Date()

        let futureStart = now.addingTimeInterval(3600)
        let lateStart = now.addingTimeInterval(300)
        let handoverTime = now.addingTimeInterval(-1800)

        let ledger = LiveActivityReminderLedger()
        let futureKey = PerformanceReminderEventKey(
            showID: showID,
            performanceID: futurePerformanceID,
            scheduledStartsAt: futureStart
        )
        let lateKey = PerformanceReminderEventKey(
            showID: showID,
            performanceID: latePerformanceID,
            scheduledStartsAt: lateStart
        )

        _ = await ledger.completeHandover(eventKey: futureKey, planVersion: 1, now: handoverTime)
        _ = await ledger.completeHandover(eventKey: lateKey, planVersion: 1, now: handoverTime)

        let session = MockCloudSession(
            responseData: #"{"ok":true,"revoked":true}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-dev", appSignature: "test-sig"),
            session: session
        )

        let recorder = RestorationRecorder()
        let service = LiveActivityRemoteSyncService(
            client: client,
            ledger: ledger,
            secretProvider: { "dummy-secret-32-chars-long-value" },
            notificationRestorer: { keys in
                await recorder.record(keys)
            }
        )

        let success = await service.revokePlan(showID: showID, now: now)
        XCTAssertTrue(success)

        let futureRecord = await ledger.record(for: futureKey)
        XCTAssertEqual(futureRecord.channel, .localNotification)
        XCTAssertEqual(futureRecord.status, .pending)

        let lateRecord = await ledger.record(for: lateKey)
        XCTAssertEqual(lateRecord.status, .handedOver)

        let recordedKeys = await recorder.restoredKeys
        XCTAssertEqual(recordedKeys, [futureKey])
    }

    @MainActor
    func testRevokePlanDefaultRestorerRecreatesOnlyFutureInterestedSystemRequests() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        if authorization == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.provisional])
            XCTAssertTrue(granted)
        }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
        let performances = try [3600.0, 4200, 4800, 300, -300].enumerated().map { index, offset in
            let start = now.addingTimeInterval(offset)
            let performance = try TimetablePerformance(
                artistName: "Restoration \(index)", startsAt: start,
                endsAt: start.addingTimeInterval(60)
            )
            performance.isInterested = true
            return performance
        }
        let calendar = Calendar.current
        let days = try Dictionary(grouping: performances, by: {
            calendar.startOfDay(for: $0.startsAt)
        }).map { date, performances in
            try TimetableDay(date: date, stages: [
                TimetableStage(name: "Main Stage", performances: performances)
            ])
        }
        let show = try Show(
            name: "Notification restoration", date: performances[4].startsAt,
            startTime: performances[4].startsAt,
            endDate: performances[2].endsAt, endTime: performances[2].endsAt,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        context.insert(show)
        let timetable = try Timetable(timeZoneIdentifier: calendar.timeZone.identifier, days: days)
        timetable.show = show
        show.timetable = timetable
        context.insert(timetable)
        context.insert(CurrentShowSelection(selectedShowID: show.id))
        try context.save()
        LocalNotificationCenter.shared.configure(with: container)

        let ledger = LiveActivityReminderLedger.shared
        let keys = performances.map {
            PerformanceReminderEventKey(showID: show.id.uuidString,
                performanceID: $0.id.uuidString, scheduledStartsAt: $0.startsAt)
        }
        for key in keys {
            let handedOver = await ledger.completeHandover(
                eventKey: key, planVersion: 1, now: now.addingTimeInterval(-3600)
            )
            XCTAssertTrue(handedOver)
        }
        let showID = show.id.uuidString
        addTeardownBlock {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending
                .filter { $0.identifier.hasPrefix(showID) }.map(\.identifier))
            for key in keys { await ledger.revoke(eventKey: key) }
        }
        _ = await LocalNotificationCenter.shared.reconcilePortfolio()
        let before = await center.pendingNotificationRequests()
        XCTAssertFalse(before.contains { keys.map(\.notificationIdentifier).contains($0.identifier) })

        let updatedStart = now.addingTimeInterval(4260)
        performances[1].startsAt = updatedStart
        performances[1].endsAt = updatedStart.addingTimeInterval(60)
        performances[2].isInterested = false
        try context.save()

        let session = MockCloudSession(
            responseData: #"{"ok":true,"revoked":true}"#.data(using: .utf8)!,
            statusCode: 200
        )
        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "test-dev", appSignature: "test-sig"),
            session: session
        )

        let service = LiveActivityRemoteSyncService(
            client: client,
            ledger: ledger,
            secretProvider: { "dummy-secret-32-chars-long-value" }
        )

        let success = await service.revokePlan(showID: show.id.uuidString, now: now)
        XCTAssertTrue(success)

        let pending = await center.pendingNotificationRequests()
        let restored = pending.filter { request in keys.contains { $0.notificationIdentifier == request.identifier } }
        XCTAssertEqual(Set(restored.map(\.identifier)), Set(keys.prefix(2).map(\.notificationIdentifier)))
        for (index, start) in [performances[0].startsAt, updatedStart].enumerated() {
            let request = try XCTUnwrap(restored.first { $0.identifier == keys[index].notificationIdentifier })
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            let fireDate = try XCTUnwrap(trigger.nextTriggerDate())
            XCTAssertEqual(fireDate.timeIntervalSince1970,
                start.addingTimeInterval(-900).timeIntervalSince1970, accuracy: 1)
        }
    }
}

private actor RestorationRecorder {
    var restoredKeys: [PerformanceReminderEventKey] = []
    func record(_ keys: [PerformanceReminderEventKey]) {
        restoredKeys = keys
    }
}

private actor MockCloudSession: URLSessionProtocol {
    var responseData: Data
    var statusCode: Int

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

private actor RevocationRecorder {
    var revokedID: String?
    func record(_ id: String) {
        revokedID = id
    }
}
