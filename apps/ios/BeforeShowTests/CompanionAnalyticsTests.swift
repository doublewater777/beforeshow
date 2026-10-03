import CloudKit
import PostHog
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionAnalyticsTests: XCTestCase {
    func testJoinSuccessRequiresDurableImportForBothEntryPoints() async throws {
        let analytics = CompanionAnalyticsRecorder()
        defer { analytics.close() }
        let session = makeSession()
        for source in ["onboarding", "confirmation"] {
            let container = try makeContainer()
            let (accepted, result) = try await CompanionJoinOperation.run(
                source: source, in: container.mainContext, strategy: .automatic
            ) { _ in session }
            let persisted = try ModelContext(container).fetch(FetchDescriptor<Show>())
            XCTAssertEqual(persisted.count, 1)
            XCTAssertEqual(persisted.first?.companionCloudRecordName, accepted.recordName)
            XCTAssertEqual(persisted.first?.id, result.showID)
        }
        let completed = analytics.events.filter { $0.name == "companion_join_finished" }
        XCTAssertEqual(completed.count, 2)
        XCTAssertEqual(completed.compactMap { $0.properties["source"] as? String }, ["onboarding", "confirmation"])
        for event in completed {
            XCTAssertEqual(event.properties["outcome"] as? String, "succeeded")
            XCTAssertEqual(event.properties["stage"] as? String, "local_import")
        }
        // Correlate the owner-side share and participant join without sending record identities.
        let share = CompanionAnalyticsAttempt(.share, source: "system_sheet", sessionRecordName: session.recordName)
        share.finishSystemShare(completed: true, error: nil)
        XCTAssertEqual(analytics.events.last?.properties["session_id"] as? String, completed[0].properties["session_id"] as? String)
        XCTAssertNotEqual(completed[0].properties["session_id"] as? String, session.recordName)
    }

    func testJoinCloudAndLocalImportFailuresDoNotReportSuccess() async throws {
        let analytics = CompanionAnalyticsRecorder()
        defer { analytics.close() }
        let container = try makeContainer()
        do {
            _ = try await CompanionJoinOperation.run(
                source: "onboarding", in: container.mainContext, strategy: .automatic
            ) { attempt in
                attempt.stage = "metadata_load"
                throw CompanionSharingError.permissionDenied
            }
            XCTFail("Expected metadata failure")
        } catch {
            XCTAssertEqual(error as? CompanionSharingError, .permissionDenied)
        }
        do {
            _ = try await CompanionJoinOperation.run(
                source: "confirmation", in: container.mainContext, strategy: .automatic
            ) { _ in throw CKError(.serverRejectedRequest) }
            XCTFail("Expected CloudKit rejection")
        } catch {
            XCTAssertEqual((error as? CKError)?.code, .serverRejectedRequest)
        }
        do {
            _ = try await CompanionJoinOperation.run(
                source: "confirmation", in: container.mainContext, strategy: .mergeInto(UUID())
            ) { _ in self.makeSession() }
            XCTFail("Expected local import conflict after cloud acceptance")
        } catch {
            XCTAssertEqual(error as? CompanionSharingError, .conflict)
        }
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Show>()).isEmpty)
        let completed = analytics.events.filter { $0.name == "companion_join_finished" }
        XCTAssertEqual(completed.count, 3)
        XCTAssertEqual(completed.compactMap { $0.properties["outcome"] as? String }, ["failed", "failed", "failed"])
        XCTAssertEqual(completed.compactMap { $0.properties["stage"] as? String }, ["metadata_load", "cloud_accept", "local_import"])
        XCTAssertEqual(completed.compactMap { $0.properties["error_category"] as? String }, ["permission_denied", "accept_failed", "conflict"])
    }

    func testSystemShareCompletionDistinguishesCancelFailureAndSuccessAndDeduplicates() throws {
        let analytics = CompanionAnalyticsRecorder()
        defer { analytics.close() }
        let privateMessage = "private-invitation-url-and-name"
        for (completed, error, expected) in [
            (false, nil, "canceled"),
            (true, nil, "succeeded"),
            (true, NSError(domain: privateMessage, code: 7, userInfo: [NSLocalizedDescriptionKey: privateMessage]), "failed")
        ] as [(Bool, Error?, String)] {
            let before = analytics.events.count
            let attempt = CompanionAnalyticsAttempt(.share, source: "system_sheet")
            attempt.finishSystemShare(completed: completed, error: error)
            attempt.finishSystemShare(completed: true, error: nil)
            XCTAssertEqual(analytics.events.count, before + 2)
            let event = try XCTUnwrap(analytics.events.last)
            XCTAssertEqual(event.properties["outcome"] as? String, expected)
            XCTAssertEqual(event.properties["stage"] as? String, "system_completion")
            let encoded = try JSONSerialization.data(withJSONObject: event.properties)
            XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(privateMessage))
        }
    }

    func testShareWithoutURLReportsPresentationFailure() throws {
        let analytics = CompanionAnalyticsRecorder()
        defer { analytics.close() }
        let record = CKRecord(recordType: "CompanionSession")
        let share = CKShare(rootRecord: record)
        let data = try NSKeyedArchiver.archivedData(withRootObject: share, requiringSecureCoding: true)
        var dismissed = false
        XCTAssertFalse(SystemCloudSharePresenter.present(
            shareData: data, show: makeSession().show,
            onEvent: { _, _, _ in }, onDismiss: { _ in dismissed = true }
        ))
        XCTAssertFalse(dismissed)
        XCTAssertEqual(analytics.events.map(\.name), ["companion_share_started", "companion_share_finished"])
        XCTAssertEqual(analytics.events.last?.properties["outcome"] as? String, "failed")
        XCTAssertEqual(analytics.events.last?.properties["error_category"] as? String, "missing_share_url")
    }

    func testSDKOptOutSuppressesCompanionEventsUntilOptIn() {
        let analytics = CompanionAnalyticsRecorder()
        defer { analytics.close() }
        PostHogSDK.shared.optOut()
        let attempt = CompanionAnalyticsAttempt(.share, source: "system_sheet")
        attempt.finishSystemShare(completed: true, error: nil)
        XCTAssertTrue(analytics.events.isEmpty)
        PostHogSDK.shared.optIn()
        let next = CompanionAnalyticsAttempt(.share, source: "system_sheet")
        next.finishSystemShare(completed: false, error: nil)
        XCTAssertEqual(analytics.events.count, 2)
    }

    func testCloudDiagnosticsKeepCodesAndAttemptAcrossCallbackWithoutPrivatePayload() async throws {
        let analytics = CompanionAnalyticsRecorder()
        defer { analytics.close() }
        let privateValue = "private-owner-record-and-invitation-url"
        let error = CKError(.partialFailure, userInfo: [
            NSLocalizedDescriptionKey: privateValue,
            CKPartialErrorsByItemIDKey: [
                privateValue: CKError(.permissionFailure),
                "another-private-record": CKError(.permissionFailure)
            ]
        ])
        let container = try makeContainer()
        for source in ["onboarding", "confirmation"] {
            do {
                _ = try await CompanionJoinOperation.run(
                    source: source, in: container.mainContext, strategy: .automatic
                ) { _ in
                    // CloudKit callbacks run outside the caller's Swift task.
                    let context = CompanionCloudDiagnostics.context
                    await Task.detached {
                        XCTAssertNil(CompanionCloudDiagnostics.context)
                        context?.report(error, stage: .shareAccept)
                    }.value
                    throw CloudKitCompanionSharingService.mapError(error, fallback: .acceptFailed)
                }
                XCTFail("Expected accept failure")
            } catch {
                XCTAssertEqual(error as? CompanionSharingError, .permissionDenied)
            }
        }
        let diagnostics = analytics.events.filter { $0.name == "companion_cloud_request_failed" }
        let finished = analytics.events.filter { $0.name == "companion_join_finished" }
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(finished.count, 2)
        for (diagnostic, finish) in zip(diagnostics, finished) {
            XCTAssertEqual(diagnostic.properties["attempt_id"] as? String, finish.properties["attempt_id"] as? String)
            XCTAssertEqual(diagnostic.properties["source"] as? String, finish.properties["source"] as? String)
            XCTAssertEqual(diagnostic.properties["cloudkit_error_code"] as? Int, 2)
            XCTAssertEqual(diagnostic.properties["cloudkit_partial_error_codes"] as? [Int], [10])
            XCTAssertEqual(diagnostic.properties["stage"] as? String, "share_accept")
            let json = try JSONSerialization.data(withJSONObject: diagnostic.properties)
            XCTAssertFalse(String(decoding: json, as: UTF8.self).contains(privateValue))
        }
        XCTAssertNotEqual(diagnostics[0].properties["attempt_id"] as? String, diagnostics[1].properties["attempt_id"] as? String)
        CompanionCloudDiagnostics.report(error, stage: .metadataLoad)
        XCTAssertEqual(analytics.events.count, 6, "Background errors outside an action are suppressed")

        PostHogSDK.shared.optOut()
        let attempt = CompanionAnalyticsAttempt(.invitation, source: "create")
        await attempt.withCloudDiagnostics {
            CompanionCloudDiagnostics.report(error, stage: .invitationSave)
        }
        attempt.finish(.failed, error: error)
        XCTAssertEqual(analytics.events.count, 6, "Diagnostics honor SDK opt-out")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func makeSession() -> CompanionSessionSnapshot {
        let date = Date(timeIntervalSince1970: 2_100_000_000)
        return CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(recordName: "session-private-random-uuid", ownerName: "private-owner"),
            shareLocator: CompanionRecordLocator(recordName: "private-share-token"),
            show: CompanionShowSnapshot(
                showID: UUID().uuidString, showName: "私人现场",
                showDate: date, showStartTime: date, sourceShowDate: date
            ),
            ownerDisplayName: "私人姓名", participantDisplayName: nil, participantDisplayNames: [],
            status: .accepted, createdAt: date, acceptedAt: date, canceledAt: nil
        )
    }
}
