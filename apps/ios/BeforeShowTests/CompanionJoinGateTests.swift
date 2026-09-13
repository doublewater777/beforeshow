import CloudKit
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionJoinGateTests: XCTestCase {
    func testInviteAccessUsesReusableReadOnlyLink() {
        XCTAssertEqual(CompanionInviteAccessPolicy.publicPermission, .readOnly)
    }

    func testPendingSharedSessionIsNotImportedBeforeJoinConfirmation() async throws {
        let suiteName = "CompanionJoinGateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: CompanionCloudSyncMarker.userDefaultsKey)

        let date = Date(timeIntervalSince1970: 2_100_000_000)
        let showSnapshot = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "等待确认的同行现场",
            showDate: date,
            showStartTime: date,
            sourceShowDate: date
        )
        let session = CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(
                recordName: "pending-session",
                ownerName: "owner-token"
            ),
            shareLocator: CompanionRecordLocator(
                recordName: "pending-share",
                ownerName: "owner-token"
            ),
            show: showSnapshot,
            ownerDisplayName: "Alex",
            participantDisplayName: nil,
            participantDisplayNames: [],
            status: .pending,
            createdAt: date.addingTimeInterval(-3_600),
            acceptedAt: nil,
            canceledAt: nil
        )
        let coordinator = CompanionSharingCoordinator(
            service: PendingDiscoveryService(session: session),
            userDefaults: defaults,
            usesKeychainCloudSyncMarker: false
        )

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: configuration
        )

        await coordinator.refreshAllLinkedShows(in: container.mainContext)

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Show>()).isEmpty)
        XCTAssertNil(coordinator.pendingAcceptResult)
        XCTAssertNil(coordinator.pendingAcceptMessage)
    }

    func testLiveAcceptedShowOffersCurrentSwitchWhenAnotherShowIsCurrent() throws {
        let (show, now) = try makeLiveShow()
        let result = CompanionAcceptedImportResult(
            showID: show.id,
            inserted: true,
            becameCurrent: false,
            wasHistorical: false
        )

        XCTAssertTrue(
            CompanionLiveCurrentPromptPolicy.shouldOffer(
                importResult: result,
                show: show,
                selectedShowID: UUID(),
                now: now
            )
        )
    }

    func testFutureAcceptedShowDoesNotOfferCurrentSwitch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2030, month: 6, day: 1, hour: 20
        )))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let show = try Show(
            name: "明天的同行现场",
            date: tomorrow,
            startTime: tomorrow,
            timeZoneIdentifier: "UTC"
        )
        let result = CompanionAcceptedImportResult(
            showID: show.id,
            inserted: true,
            becameCurrent: false,
            wasHistorical: false
        )

        XCTAssertFalse(
            CompanionLiveCurrentPromptPolicy.shouldOffer(
                importResult: result,
                show: show,
                selectedShowID: UUID(),
                now: now
            )
        )
    }

    func testLiveAcceptedShowDoesNotOfferSwitchWhenItAlreadyBecameCurrent() throws {
        let (show, now) = try makeLiveShow()
        let result = CompanionAcceptedImportResult(
            showID: show.id,
            inserted: true,
            becameCurrent: true,
            wasHistorical: false
        )

        XCTAssertFalse(
            CompanionLiveCurrentPromptPolicy.shouldOffer(
                importResult: result,
                show: show,
                selectedShowID: show.id,
                now: now
            )
        )
    }

    private func makeLiveShow() throws -> (Show, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2030, month: 6, day: 1, hour: 12
        )))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2030, month: 6, day: 1, hour: 19
        )))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2030, month: 6, day: 1, hour: 20
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2030, month: 6, day: 1, hour: 22
        )))
        let show = try Show(
            name: "正在进行的同行现场",
            date: date,
            startTime: start,
            endDate: date,
            endTime: end,
            timeZoneIdentifier: "UTC",
            endTimeZoneIdentifier: "UTC"
        )
        return (show, now)
    }
}

private struct PendingDiscoveryService: CompanionSharingService {
    let session: CompanionSessionSnapshot

    func prepareInvitation(
        show _: CompanionShowSnapshot,
        ownerDisplayName _: String?,
        preferredParticipantName _: String?
    ) async throws -> CompanionPreparedShare {
        throw CompanionSharingError.sharePreparationFailed
    }

    func loadShareSystemFields(shareLocator _: CompanionRecordLocator) async throws -> Data {
        throw CompanionSharingError.sessionNotFound
    }

    func acceptShare(
        metadata _: CKShare.Metadata,
        participantDisplayName _: String?
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.acceptFailed
    }

    func cancelSession(
        sessionLocator _: CompanionRecordLocator,
        shareLocator _: CompanionRecordLocator?,
        isOwner _: Bool
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.sessionNotFound
    }

    func fetchSession(sessionLocator _: CompanionRecordLocator) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.sessionNotFound
    }

    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot] {
        [session]
    }

    func reconcileOwnerMembership(
        shareLocator _: CompanionRecordLocator
    ) async throws -> CompanionMembershipState {
        .healthy
    }
}
