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

        // No token yet, version should be nil
        let initialVersion = await coordinator.currentVersion(for: showID.uuidString)
        XCTAssertNil(initialVersion)

        // Token arrived
        await coordinator.handleTokenUpdate("token-hex-12345", for: showID.uuidString)

        let v1 = await coordinator.currentVersion(for: showID.uuidString)
        XCTAssertEqual(v1, 1)

        // Snapshot updated again -> new version 2
        await coordinator.updateSnapshot(snapshot)
        let v2 = await coordinator.currentVersion(for: showID.uuidString)
        XCTAssertEqual(v2, 2)
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
        let v1 = await coordinator.currentVersion(for: showID.uuidString)
        XCTAssertEqual(v1, 1)

        await coordinator.revoke(showID: showID.uuidString)
        let vAfterRevoke = await coordinator.currentVersion(for: showID.uuidString)
        XCTAssertNil(vAfterRevoke)

        let requests = await session.recordedRequests
        let revokeReq = requests.first { $0.url?.lastPathComponent == "revokeLiveActivityPlan" }
        XCTAssertNotNil(revokeReq)
        if let body = revokeReq?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            XCTAssertEqual(json["showID"] as? String, showID.uuidString)
        } else {
            XCTFail("Missing or invalid revoke request body")
        }
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
