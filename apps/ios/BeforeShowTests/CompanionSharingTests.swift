import CloudKit
import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class CompanionSharingTests: XCTestCase {
    func testCloudStatusMapsToLocalStatus() {
        XCTAssertEqual(CompanionCloudStatus.pending.localStatus, .pending)
        XCTAssertEqual(CompanionCloudStatus.accepted.localStatus, .confirmed)
        XCTAssertEqual(CompanionCloudStatus.canceled.localStatus, .canceled)
    }

    func testCompanionDisplayNamePicksOtherParty() {
        let session = CompanionSessionSnapshot(
            recordName: "rec-1",
            shareRecordName: "share-1",
            show: CompanionShowSnapshot(
                showID: "show-1",
                showName: "现场",
                showDate: Date(timeIntervalSince1970: 2_000_000_000),
                showLocation: "上海"
            ),
            ownerDisplayName: "Alex",
            participantDisplayName: "林嘉",
            status: .accepted,
            createdAt: Date(timeIntervalSince1970: 2_000_000_000),
            acceptedAt: Date(timeIntervalSince1970: 2_000_000_100),
            canceledAt: nil
        )

        XCTAssertEqual(session.companionDisplayName(isOwner: true), "林嘉")
        XCTAssertEqual(session.companionDisplayName(isOwner: false), "Alex")
    }

    func testShowSnapshotFromLocalShow() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "同行现场",
            date: now,
            startTime: now,
            city: "南京",
            venueName: "奥体中心"
        )
        let snapshot = CompanionShowSnapshot(show: show)
        XCTAssertEqual(snapshot.showID, show.id.uuidString)
        XCTAssertEqual(snapshot.showName, "同行现场")
        XCTAssertEqual(snapshot.showLocation, "奥体中心 · 南京")
    }

    func testApplyCompanionSessionWritesCloudLinkageAndStatus() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        let session = CompanionSessionSnapshot(
            recordName: "session-abc",
            shareRecordName: "share-xyz",
            show: CompanionShowSnapshot(
                showID: show.id.uuidString,
                showName: show.name,
                showDate: now,
                showLocation: nil
            ),
            ownerDisplayName: "Alex",
            participantDisplayName: "林嘉",
            status: .accepted,
            createdAt: now,
            acceptedAt: now,
            canceledAt: nil
        )

        show.applyCompanionSession(session, isOwner: true)

        XCTAssertEqual(show.companionCloudRecordName, "session-abc")
        XCTAssertEqual(show.companionShareRecordName, "share-xyz")
        XCTAssertEqual(show.companionIsOwner, true)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionName, "林嘉")
    }

    func testApplyCompanionSessionAsParticipantUsesOwnerName() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        let session = CompanionSessionSnapshot(
            recordName: "session-abc",
            shareRecordName: "share-xyz",
            show: CompanionShowSnapshot(
                showID: "owner-show",
                showName: show.name,
                showDate: now,
                showLocation: nil
            ),
            ownerDisplayName: "Alex",
            participantDisplayName: "林嘉",
            status: .accepted,
            createdAt: now,
            acceptedAt: now,
            canceledAt: nil
        )

        show.applyCompanionSession(session, isOwner: false)
        XCTAssertEqual(show.companionIsOwner, false)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionName, "Alex")
    }

    @MainActor
    func testCoordinatorPrepareInvitationUsesServiceAndRollsBackOnFailure() async throws {
        let service = MockCompanionSharingService()
        service.prepareError = CompanionSharingError.networkFailure
        let coordinator = CompanionSharingCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        context.insert(show)
        try context.save()

        do {
            _ = try await coordinator.prepareInvitation(
                for: show,
                preferredParticipantName: "林嘉",
                ownerDisplayName: "Alex",
                in: context
            )
            XCTFail("Expected prepare to throw")
        } catch {
            XCTAssertEqual(error as? CompanionSharingError, .networkFailure)
        }

        XCTAssertEqual(show.companionStatus, .none)
        XCTAssertNil(show.companionName)
        XCTAssertNil(show.companionCloudRecordName)
    }

    @MainActor
    func testCoordinatorPrepareInvitationPersistsCloudFieldsOnSuccess() async throws {
        let service = MockCompanionSharingService()
        let coordinator = CompanionSharingCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        context.insert(show)
        try context.save()

        let prepared = try await coordinator.prepareInvitation(
            for: show,
            preferredParticipantName: "林嘉",
            ownerDisplayName: "Alex",
            in: context
        )

        XCTAssertEqual(prepared.session.status, .pending)
        XCTAssertEqual(show.companionStatus, .pending)
        XCTAssertEqual(show.companionName, "林嘉")
        XCTAssertEqual(show.companionCloudRecordName, prepared.session.recordName)
        XCTAssertEqual(show.companionShareRecordName, prepared.session.shareRecordName)
        XCTAssertEqual(show.companionIsOwner, true)
    }

    @MainActor
    func testCoordinatorRefreshUpdatesAcceptedStatus() async throws {
        let service = MockCompanionSharingService()
        let coordinator = CompanionSharingCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionShareRecordName = "share-1"
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        service.sessions["session-1"] = CompanionSessionSnapshot(
            recordName: "session-1",
            shareRecordName: "share-1",
            show: CompanionShowSnapshot(show: show),
            ownerDisplayName: "Alex",
            participantDisplayName: "林嘉",
            status: .accepted,
            createdAt: now,
            acceptedAt: now.addingTimeInterval(60),
            canceledAt: nil
        )

        await coordinator.refreshCompanion(for: show, in: context)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionName, "林嘉")
    }
}

// MARK: - Mock

private final class MockCompanionSharingService: CompanionSharingService, @unchecked Sendable {
    var prepareError: CompanionSharingError?
    var sessions: [String: CompanionSessionSnapshot] = [:]
    private var counter = 0

    func prepareInvitation(
        show: CompanionShowSnapshot,
        ownerDisplayName: String?,
        preferredParticipantName: String?
    ) async throws -> CompanionPreparedShare {
        if let prepareError { throw prepareError }
        counter += 1
        let recordName = "session-\(counter)"
        let shareName = "share-\(counter)"
        let session = CompanionSessionSnapshot(
            recordName: recordName,
            shareRecordName: shareName,
            show: show,
            ownerDisplayName: ownerDisplayName,
            participantDisplayName: preferredParticipantName,
            status: .pending,
            createdAt: Date(),
            acceptedAt: nil,
            canceledAt: nil
        )
        sessions[recordName] = session
        return CompanionPreparedShare(session: session, shareSystemFields: Data([0x01, 0x02]))
    }

    func loadShareSystemFields(shareRecordName: String) async throws -> Data {
        Data([0x01, 0x02])
    }

    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.acceptFailed
    }

    func cancelSession(recordName: String) async throws -> CompanionSessionSnapshot {
        guard var session = sessions[recordName] else {
            throw CompanionSharingError.sessionNotFound
        }
        session = CompanionSessionSnapshot(
            recordName: session.recordName,
            shareRecordName: session.shareRecordName,
            show: session.show,
            ownerDisplayName: session.ownerDisplayName,
            participantDisplayName: session.participantDisplayName,
            status: .canceled,
            createdAt: session.createdAt,
            acceptedAt: session.acceptedAt,
            canceledAt: Date()
        )
        sessions[recordName] = session
        return session
    }

    func fetchSession(recordName: String) async throws -> CompanionSessionSnapshot {
        guard let session = sessions[recordName] else {
            throw CompanionSharingError.sessionNotFound
        }
        return session
    }
}
