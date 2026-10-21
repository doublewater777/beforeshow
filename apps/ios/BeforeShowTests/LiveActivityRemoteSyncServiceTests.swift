import XCTest
@testable import BeforeShow

final class LiveActivityRemoteSyncServiceTests: XCTestCase {

    func testSyncPlanSuccessCompletesHandoverAndRevokesLocalNotification() async throws {
        let showID = UUID().uuidString
        let performanceID = UUID().uuidString
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

        let step = LiveActivityTransitionStep(
            scheduledAt: scheduledStartsAt.addingTimeInterval(-900), // 15 mins before
            state: contentState
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
        XCTAssertEqual(revokedID, eventKey.notificationIdentifier)
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
