import XCTest
@testable import BeforeShow

final class LiveActivityPushCoordinatorTests: XCTestCase {

    func testHandleTokenUpdateTriggersSyncWithIncrementingVersion() async throws {
        let showID = UUID()
        let performanceID = UUID()
        let scheduledStartsAt = Date().addingTimeInterval(3600)

        let session = MockPushCloudSession { req in
            if req.url?.lastPathComponent == "syncLiveActivityPlan" {
                var ver = 1
                if let body = req.httpBody,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let plan = json["plan"] as? [String: Any],
                   let v = plan["version"] as? Int {
                    ver = v
                }
                return (try! JSONSerialization.data(withJSONObject: ["ok": true, "acceptedVersion": ver, "planID": "p-1"]), 200)
            }
            return (try! JSONSerialization.data(withJSONObject: ["ok": true]), 200)
        }

        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "dev-test", appSignature: "sig-test"),
            session: session
        )
        let syncService = LiveActivityRemoteSyncService(
            client: client,
            ledger: LiveActivityReminderLedger(),
            secretProvider: { "dummy-secret-32-chars-test-value" },
            notificationRevoker: { _ in }
        )

        let coordinator = LiveActivityPushCoordinator(
            syncService: syncService,
            appInstanceIDProvider: { "dev-test" }
        )

        let snapshot = makeSnapshot(showID: showID, performanceID: performanceID, start: scheduledStartsAt)
        await coordinator.updateSnapshot(snapshot)

        let initialRequests = await session.recordedRequests
        XCTAssertTrue(initialRequests.isEmpty)

        // Token arrived
        await coordinator.handleTokenUpdate("token-hex-12345", for: showID.uuidString)

        await coordinator.updateSnapshot(snapshot)
        let requests = await session.recordedRequests
        let versions = try requests.map {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap($0.httpBody)) as? [String: Any])
            let plan = try XCTUnwrap(json["plan"] as? [String: Any])
            return try XCTUnwrap(plan["version"] as? Int)
        }
        XCTAssertEqual(versions.count, 2)
        XCTAssertGreaterThan(versions[1], versions[0])
    }

    func testRevokeClearsTokenAndNotifiesService() async throws {
        let showID = UUID()
        let performanceID = UUID()
        let scheduledStartsAt = Date().addingTimeInterval(3600)

        let session = MockPushCloudSession { req in
            if req.url?.lastPathComponent == "revokeLiveActivityPlan" {
                return (try! JSONSerialization.data(withJSONObject: ["ok": true, "revoked": true]), 200)
            }
            return (try! JSONSerialization.data(withJSONObject: ["ok": true, "acceptedVersion": 1]), 200)
        }

        let client = BeforeShowCloudClient(
            rootURL: URL(string: "https://example.com")!,
            credentials: BeforeShowAppCredentials(appInstanceId: "dev-test", appSignature: "sig-test"),
            session: session
        )
        let syncService = LiveActivityRemoteSyncService(
            client: client,
            ledger: LiveActivityReminderLedger(),
            secretProvider: { "dummy-secret-32-chars-test-value" }
        )

        let coordinator = LiveActivityPushCoordinator(
            syncService: syncService,
            appInstanceIDProvider: { "dev-test" }
        )

        let snapshot = makeSnapshot(showID: showID, performanceID: performanceID, start: scheduledStartsAt)
        await coordinator.updateSnapshot(snapshot)
        await coordinator.handleTokenUpdate("token-hex-12345", for: showID.uuidString)
        await coordinator.revoke(showID: showID.uuidString)
        await coordinator.updateSnapshot(snapshot)

        let requests = await session.recordedRequests
        XCTAssertEqual(requests.filter { $0.url?.lastPathComponent == "syncLiveActivityPlan" }.count, 1)
        let revokeReq = requests.first { $0.url?.lastPathComponent == "revokeLiveActivityPlan" }
        XCTAssertNotNil(revokeReq)
        if let body = revokeReq?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            XCTAssertEqual(json["showID"] as? String, showID.uuidString)
        } else {
            XCTFail("Missing or invalid revoke request body")
        }
    }

    func testRestartAndReenableUploadNewerVersionsEvenAfterFailedUpload() async throws {
        let showID = UUID()
        let snapshot = makeSnapshot(
            showID: showID, performanceID: UUID(), start: Date().addingTimeInterval(3600)
        )
        let session = MockPushCloudSession { request in
            if request.url?.lastPathComponent == "revokeLiveActivityPlan" {
                return (Data(#"{"ok":true,"revoked":true}"#.utf8), 200)
            }
            // An unacknowledged upload must not let a later process reuse its version.
            return (Data(), 500)
        }
        let service = LiveActivityRemoteSyncService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(appInstanceId: "restart-test", appSignature: "sig"),
                session: session
            ),
            ledger: LiveActivityReminderLedger(),
            secretProvider: { "dummy-secret-32-chars-test-value" },
            notificationRevoker: { _ in }
        )
        let first = LiveActivityPushCoordinator(syncService: service, appInstanceIDProvider: { "restart-test" })
        await first.updateSnapshot(snapshot)
        await first.handleTokenUpdate("old-token", for: showID.uuidString)

        let restarted = LiveActivityPushCoordinator(syncService: service, appInstanceIDProvider: { "restart-test" })
        await restarted.updateSnapshot(snapshot)
        await restarted.handleTokenUpdate("new-token", for: showID.uuidString)
        await restarted.revoke(showID: showID.uuidString)
        await restarted.handleTokenUpdate("reenabled-token", for: showID.uuidString)

        let requests = await session.recordedRequests
        let plans = try requests.filter { $0.url?.lastPathComponent == "syncLiveActivityPlan" }.map {
            let body = try XCTUnwrap($0.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["plan"] as? [String: Any])
        }
        XCTAssertEqual(plans.count, 3)
        let versions = try plans.map { try XCTUnwrap($0["version"] as? Int) }
        XCTAssertGreaterThan(versions[1], versions[0])
        XCTAssertGreaterThan(versions[2], versions[1])
        XCTAssertEqual(plans[1]["activityPushToken"] as? String, "new-token")
    }

    private func makeSnapshot(showID: UUID, performanceID: UUID, start: Date) -> WidgetShowSnapshot {
        let perf = WidgetTimetablePerformance(
            id: performanceID,
            artistName: "椅子乐团",
            stageID: UUID(),
            stageName: "风舞台",
            startsAt: start,
            endsAt: start.addingTimeInterval(2700),
            isInterested: true
        )
        let day = WidgetTimetableDay(id: UUID(), date: start, performances: [perf])
        let timetable = WidgetTimetableSnapshot(days: [day])
        let timing = ShowTimingFields(
            date: start,
            startTime: start,
            endDate: start.addingTimeInterval(2700),
            endTime: start.addingTimeInterval(2700),
            timeZoneSecondsFromGMT: 8 * 3600,
            endTimeZoneSecondsFromGMT: nil,
            timeZoneIdentifier: "Asia/Taipei",
            endTimeZoneIdentifier: nil,
            endedAt: nil,
            postponedDate: nil,
            changeStatus: .scheduled
        )
        return WidgetShowSnapshot(
            showID: showID,
            name: "草莓音乐节",
            city: "北京",
            venueName: "延庆区世园公园",
            coverImageURL: nil,
            timing: timing,
            generatedAt: Date(),
            timetable: timetable
        )
    }
}

private actor MockPushCloudSession: URLSessionProtocol {
    private let handler: @Sendable (URLRequest) -> (Data, Int)
    var recordedRequests: [URLRequest] = []

    init(handler: @escaping @Sendable (URLRequest) -> (Data, Int)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        let (data, code) = handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: code,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
