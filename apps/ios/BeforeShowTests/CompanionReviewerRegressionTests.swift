import CloudKit
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionReviewerRegressionTests: XCTestCase {
    func testExplicitHistoricalYesterdayRoundTripsAndNeverBecomesCurrent() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: configuration
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let yesterday = now.addingTimeInterval(-86_400)

        let ownerShow = try Show(
            name: "昨天但明确历史的现场",
            date: yesterday,
            startTime: yesterday.addingTimeInterval(19 * 3_600)
        )
        ownerShow.markAddedAsHistorical()

        let encoded = try JSONEncoder().encode(CompanionShowSnapshot(show: ownerShow))
        let decoded = try JSONDecoder().decode(CompanionShowSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.wasAddedAsHistorical, true)

        let session = makeSession(show: decoded, status: .accepted)
        let result = try CompanionAcceptedSessionImporter.apply(session, in: context, now: now)

        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(imported.wasAddedAsHistorical, true)
        XCTAssertTrue(result.wasHistorical)
        XCTAssertFalse(result.becameCurrent)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CurrentShowSelection>()).isEmpty)
    }

    func testConfirmedEndedAtRoundTripsThroughFrozenSnapshot() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showDate = now.addingTimeInterval(-86_400)
        let confirmedEnd = showDate.addingTimeInterval(22 * 3_600)
        let ownerShow = try Show(
            name: "有真实散场时间的现场",
            date: showDate,
            startTime: showDate.addingTimeInterval(19 * 3_600)
        )
        ownerShow.markEnded(at: confirmedEnd)

        let encoded = try JSONEncoder().encode(CompanionShowSnapshot(show: ownerShow))
        let decoded = try JSONDecoder().decode(CompanionShowSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.endedAt, confirmedEnd)

        let rebuilt = try CompanionAcceptedShowMapping.makeShow(from: decoded)
        XCTAssertEqual(rebuilt.endedAt, confirmedEnd)
        XCTAssertEqual(rebuilt.wasAddedAsHistorical, false)
    }

    func testRepeatReusableLinkPreviewCannotDowngradeConfirmedShowEvenIfRefreshFails() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: configuration
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showID = UUID()
        let sessionRecordName = "repeat-session"

        let local = try Show(
            id: showID,
            name: "已经加入的现场",
            date: now.addingTimeInterval(86_400),
            startTime: now.addingTimeInterval(86_400),
            companionStatus: .confirmed,
            companionName: "Alex",
            companionCloudRecordName: sessionRecordName,
            companionCloudZoneName: CompanionRecordLocator.companionZoneName,
            companionCloudOwnerName: "owner-token",
            companionIsOwner: false
        )
        context.insert(local)
        try context.save()

        let rootPendingPreview = CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(
                recordName: sessionRecordName,
                zoneName: CompanionRecordLocator.companionZoneName,
                ownerName: "owner-token"
            ),
            shareLocator: CompanionRecordLocator(
                recordName: "repeat-share",
                zoneName: CompanionRecordLocator.companionZoneName,
                ownerName: "owner-token"
            ),
            show: CompanionShowSnapshot(
                showID: showID.uuidString,
                showName: local.name,
                showDate: local.date,
                showStartTime: local.startTime,
                sourceShowDate: local.date
            ),
            ownerDisplayName: "Alex",
            participantDisplayName: nil,
            participantDisplayNames: [],
            status: .pending,
            createdAt: now.addingTimeInterval(-3_600),
            acceptedAt: nil,
            canceledAt: nil
        )

        let suiteName = "CompanionReviewerRegressionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = CompanionSharingCoordinator(
            service: AlwaysFailingRecoveryService(),
            userDefaults: defaults,
            usesKeychainCloudSyncMarker: false
        )

        XCTAssertTrue(
            coordinator.resolvePreviewedShareForExistingLocalShow(
                rootPendingPreview,
                in: context,
                now: now
            )
        )
        XCTAssertEqual(local.companionStatus, .confirmed)
        XCTAssertEqual(local.companionName, "Alex")
        XCTAssertEqual(coordinator.pendingAcceptMessage, BSLocalization.text("你已经是这场的同行"))

        await coordinator.refreshAllLinkedShows(in: context)

        XCTAssertEqual(local.companionStatus, .confirmed)
        XCTAssertEqual(local.companionCloudRecordName, sessionRecordName)
        XCTAssertEqual(coordinator.lastErrorKind, .networkFailure)
    }

    private func makeSession(
        show: CompanionShowSnapshot,
        status: CompanionCloudStatus
    ) -> CompanionSessionSnapshot {
        CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(
                recordName: "session-\(show.showID)",
                zoneName: CompanionRecordLocator.companionZoneName,
                ownerName: "owner-token"
            ),
            shareLocator: CompanionRecordLocator(
                recordName: "share-\(show.showID)",
                zoneName: CompanionRecordLocator.companionZoneName,
                ownerName: "owner-token"
            ),
            show: show,
            ownerDisplayName: "Alex",
            participantDisplayName: nil,
            participantDisplayNames: [],
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_999_999_000),
            acceptedAt: status == .accepted ? Date(timeIntervalSince1970: 2_000_000_000) : nil,
            canceledAt: nil
        )
    }
}

private struct AlwaysFailingRecoveryService: CompanionSharingService {
    func prepareInvitation(
        show _: CompanionShowSnapshot,
        ownerDisplayName _: String?,
        preferredParticipantName _: String?
    ) async throws -> CompanionPreparedShare {
        throw CompanionSharingError.networkFailure
    }

    func loadShareSystemFields(shareLocator _: CompanionRecordLocator) async throws -> Data {
        throw CompanionSharingError.networkFailure
    }

    func acceptShare(
        metadata _: CKShare.Metadata,
        participantDisplayName _: String?
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.networkFailure
    }

    func fetchSession(sessionLocator _: CompanionRecordLocator) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.networkFailure
    }

    func cancelSession(
        sessionLocator _: CompanionRecordLocator,
        shareLocator _: CompanionRecordLocator?,
        isOwner _: Bool
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.networkFailure
    }

    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot] {
        throw CompanionSharingError.networkFailure
    }

    func reconcileOwnerMembership(
        shareLocator _: CompanionRecordLocator
    ) async throws -> CompanionMembershipState {
        throw CompanionSharingError.networkFailure
    }
}
