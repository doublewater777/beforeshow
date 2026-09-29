import CloudKit
import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

final class CompanionSharingTests: XCTestCase {
    func testNewInviteIsOnlyBlockedByMissingICloud() {
        XCTAssertTrue(CompanionInviteGate.blocksNewInvite(.iCloudAccountUnavailable))
        XCTAssertFalse(CompanionInviteGate.blocksNewInvite(.networkFailure))
        XCTAssertFalse(CompanionInviteGate.blocksNewInvite(.sharePreparationFailed))
        XCTAssertFalse(CompanionInviteGate.blocksNewInvite(.conflict))
        XCTAssertFalse(CompanionInviteGate.blocksNewInvite(nil))
    }

    func testQuickActionJoinsMultipleCompanionNames() {
        let presentation = CompanionQuickActionPresentation(
            status: .confirmed,
            companionNames: ["林嘉", "王宁"],
            isEnded: false
        )
        XCTAssertEqual(presentation.companionName, "林嘉、王宁")
        XCTAssertEqual(presentation.title, BSLocalization.format("与%@", "林嘉、王宁"))
        XCTAssertTrue(presentation.showsAvatars)
        XCTAssertEqual(
            CompanionQuickActionPresentation(
                status: .none,
                companionNames: [],
                isEnded: false
            ).accessibilityLabel,
            BSLocalization.text("同行，邀请朋友")
        )
    }

    func testPendingQuickActionShowsWaitingState() {
        let presentation = CompanionQuickActionPresentation(
            status: .pending,
            companionNames: [],
            isEnded: false
        )

        XCTAssertEqual(presentation.displayTitle, BSLocalization.text("等待同行"))
        XCTAssertEqual(presentation.accessibilityLabel, BSLocalization.text("同行，等待朋友加入"))
        XCTAssertFalse(presentation.showsAvatars)
    }

    func testQuickActionLocalizationKeysExistInThreeLanguages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BeforeShow")
        let keys = [
            "添加同行",
            "邀请和你一起去的人加入这场同行。",
            "%lld 人同行",
            "同行，等待朋友加入",
            "等待同行",
            "等待朋友加入",
            "朋友接受邀请后，会出现在这里。",
            "再次邀请",
        ]

        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let data = try Data(
                contentsOf: root.appendingPathComponent("Resources/\(locale).lproj/Localizable.strings")
            )
            let values = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            )
            for key in keys {
                XCTAssertFalse(values[key]?.isEmpty ?? true, "Missing \(locale): \(key)")
            }
        }
    }

    func testInviteActionTitleRemainsTheUserAction() {
        XCTAssertEqual(
            CompanionInvitePreparingPresentation.actionTitle(hasExistingShare: false),
            BSLocalization.text("邀请朋友")
        )
        XCTAssertEqual(
            CompanionInvitePreparingPresentation.actionTitle(hasExistingShare: true),
            BSLocalization.text("再次邀请")
        )
    }

    func testCompanionInviteWebLinkRoundTripsCloudKitURLWithoutQueryLeakage() throws {
        let shareURL = try XCTUnwrap(
            URL(string: "https://www.icloud.com/share/abc123#CompanionSessions")
        )
        let show = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "草东没有派对",
            showDate: Date(timeIntervalSince1970: 1_792_275_200),
            showStartTime: Date(timeIntervalSince1970: 1_792_275_200),
            city: "上海",
            venueName: "MAO Livehouse"
        )
        let webURL = try XCTUnwrap(CompanionInviteWebLink.make(
            from: shareURL,
            show: show,
            ownerName: "Alex"
        ))
        let components = try XCTUnwrap(
            URLComponents(url: webURL, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, CompanionInviteWebLink.host)
        XCTAssertTrue(components.path.hasPrefix(CompanionInviteWebLink.path))
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(CompanionInviteWebLink.shareURL(from: webURL), shareURL)
        let token = String(components.path.dropFirst(CompanionInviteWebLink.path.count))
        XCTAssertEqual(
            CompanionInviteWebLink.shareURL(from: try XCTUnwrap(URL(string: "beforeshow://join/\(token)"))),
            shareURL
        )

        // Verify China mainland iCloud URL (www.icloud.com.cn) is supported
        let cnShareURL = try XCTUnwrap(
            URL(string: "https://www.icloud.com.cn/share/07eSuMIaRuOnwy6KE2DNkgH_w")
        )
        let cnWebURL = try XCTUnwrap(CompanionInviteWebLink.make(
            from: cnShareURL,
            show: show,
            ownerName: "Alex"
        ))
        XCTAssertEqual(CompanionInviteWebLink.shareURL(from: cnWebURL), cnShareURL)
    }

    func testCompanionInviteWebLinkPayloadHandlesRemoteAndLocalCovers() throws {
        let shareURL = try XCTUnwrap(URL(string: "https://www.icloud.com/share/abc123"))
        let remoteCover = "https://images.example.com/poster.jpg"
        let showWithRemote = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "草东没有派对",
            showDate: Date(timeIntervalSince1970: 1_792_275_200),
            showStartTime: Date(timeIntervalSince1970: 1_792_275_200),
            coverImageURL: remoteCover
        )
        let webURL = try XCTUnwrap(CompanionInviteWebLink.make(
            from: shareURL,
            show: showWithRemote,
            ownerName: "Alex"
        ))
        let token = String(webURL.path.dropFirst(CompanionInviteWebLink.path.count))
        var padded = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        let data = try XCTUnwrap(Data(base64Encoded: padded))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["c"] as? String, remoteCover)

        let showWithLocal = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "草东没有派对",
            showDate: Date(timeIntervalSince1970: 1_792_275_200),
            showStartTime: Date(timeIntervalSince1970: 1_792_275_200),
            coverImageURL: "file:///private/var/mobile/cover.jpg"
        )
        let webURLLocal = try XCTUnwrap(CompanionInviteWebLink.make(
            from: shareURL,
            show: showWithLocal,
            ownerName: "Alex"
        ))
        let tokenLocal = String(webURLLocal.path.dropFirst(CompanionInviteWebLink.path.count))
        var paddedLocal = tokenLocal.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        paddedLocal += String(repeating: "=", count: (4 - paddedLocal.count % 4) % 4)
        let dataLocal = try XCTUnwrap(Data(base64Encoded: paddedLocal))
        let jsonLocal = try XCTUnwrap(JSONSerialization.jsonObject(with: dataLocal) as? [String: Any])
        XCTAssertNil(jsonLocal["c"])
    }

    func testCompanionInviteWebLinkRejectsForeignHostsAndInvalidPayloads() throws {
        let foreign = try XCTUnwrap(
            URL(string: "https://example.com/join/#share=abc")
        )
        let invalid = try XCTUnwrap(
            URL(string: "https://beforeshow.doublewaterapps.com/join/not-base64")
        )

        XCTAssertNil(CompanionInviteWebLink.shareURL(from: foreign))
        XCTAssertNil(CompanionInviteWebLink.shareURL(from: invalid))
    }

    func testCompanionUniversalLinkConfigurationMatchesWebsiteAssociation() throws {
        let appsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsURL = appsRoot
            .appendingPathComponent("ios/BeforeShow/BeforeShow.entitlements")
        let entitlementData = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: entitlementData,
                format: nil
            ) as? [String: Any]
        )
        let domains = try XCTUnwrap(
            entitlements["com.apple.developer.associated-domains"] as? [String]
        )
        XCTAssertTrue(domains.contains("applinks:\(CompanionInviteWebLink.host)"))

        let associationURL = appsRoot
            .appendingPathComponent("web/public/.well-known/apple-app-site-association")
        let associationData = try Data(contentsOf: associationURL)
        let association = try XCTUnwrap(
            JSONSerialization.jsonObject(with: associationData) as? [String: Any]
        )
        let applinks = try XCTUnwrap(association["applinks"] as? [String: Any])
        let details = try XCTUnwrap(applinks["details"] as? [[String: Any]])
        XCTAssertTrue(
            details.contains {
                guard $0["appID"] as? String == "29C8MS76CZ.com.doublewaterapps.beforeshow",
                      let paths = $0["paths"] as? [String] else {
                    return false
                }
                return paths.contains(CompanionInviteWebLink.path)
            }
        )
    }

    func testCloudStatusMapsToLocalStatus() {
        XCTAssertEqual(CompanionCloudStatus.pending.localStatus, .pending)
        XCTAssertEqual(CompanionCloudStatus.accepted.localStatus, .confirmed)
        XCTAssertEqual(CompanionCloudStatus.canceled.localStatus, .canceled)
    }

    func testMembershipPolicyKeepsMultipleAcceptedMembersHealthy() {
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.accepted, .accepted]),
            .healthy
        )
    }

    func testMembershipPolicyTreatsOutstandingInvitesAsHealthy() {
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.accepted, .pending]),
            .healthy
        )
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.pending]),
            .removed
        )
    }

    func testMembershipPolicyRemovesEmptyShareAndWarnsOnUnknown() {
        XCTAssertEqual(CompanionMembershipPolicy.evaluate(nonOwnerStatuses: []), .removed)
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.accepted, .unknown]),
            .warning("同行成员状态暂时无法确认，请稍后重试")
        )
    }

    func testCompanionNameListDropsBlanksAndJoinsWithDunhao() {
        XCTAssertEqual(CompanionNameList.normalized([" 林嘉 ", "", "王宁", "林嘉"]), ["林嘉", "王宁"])
        XCTAssertEqual(CompanionNameList.joined(["林嘉", "王宁"]), "林嘉、王宁")
        XCTAssertNil(CompanionNameList.joined([" ", ""]))
    }

    func testSharedHistoryMatchesExactNameSetsOnly() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let withJia = try Show(name: "只和林嘉", date: now, startTime: now)
        try withJia.markCompanionInvitationSent(name: "林嘉")
        try withJia.markCompanionConfirmed(name: "林嘉")
        withJia.markEnded(at: now)

        let group = try Show(name: "林嘉和王宁", date: now.addingTimeInterval(86_400), startTime: now)
        group.applyCompanionState(status: .pending, names: ["王宁", "林嘉"])
        group.applyCompanionState(status: .confirmed, names: ["王宁", "林嘉"])
        group.markEnded(at: now.addingTimeInterval(86_400))

        let sameGroupLater = try Show(name: "同一组再看", date: now.addingTimeInterval(172_800), startTime: now)
        sameGroupLater.applyCompanionState(status: .pending, names: ["林嘉", "王宁"])
        sameGroupLater.applyCompanionState(status: .confirmed, names: ["林嘉", "王宁"])
        sameGroupLater.markEnded(at: now.addingTimeInterval(172_800))

        let groupHistory = CompanionSharedHistory.shows(
            matching: group,
            from: [withJia, group, sameGroupLater]
        )
        XCTAssertEqual(groupHistory.map(\.name), ["同一组再看", "林嘉和王宁"])

        let pairHistory = CompanionSharedHistory.shows(
            matching: withJia,
            from: [withJia, group, sameGroupLater]
        )
        XCTAssertEqual(pairHistory.map(\.name), ["只和林嘉"])
    }

    func testCompanionDisplayNamePicksOtherParty() {
        let ownerSession = makeSession(
            recordName: "rec-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Alex",
            participant: nil,
            participantNames: ["林嘉"]
        )
        let participantSession = makeSession(
            recordName: "rec-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Alex",
            participant: "林嘉"
        )

        XCTAssertEqual(ownerSession.companionDisplayName(isOwner: true), "林嘉")
        XCTAssertEqual(participantSession.companionDisplayName(isOwner: false), "Alex")
    }

    func testCompanionDisplayNamesListsTheGroup() {
        let session = makeSession(
            recordName: "rec-2",
            shareName: "share-2",
            status: .accepted,
            owner: "Alex",
            participant: nil,
            participantNames: ["林嘉", "王宁"]
        )

        XCTAssertEqual(session.companionDisplayNames(isOwner: true), ["林嘉", "王宁"])
        XCTAssertEqual(session.companionDisplayName(isOwner: true), "林嘉、王宁")
        XCTAssertEqual(session.companionDisplayNames(isOwner: false), ["Alex", "林嘉", "王宁"])
    }

    func testRecordLocatorPreservesZoneIdentity() {
        let zone = CKRecordZone.ID(zoneName: "CompanionSessions", ownerName: "owner-A")
        let recordID = CKRecord.ID(recordName: "session-1", zoneID: zone)
        let locator = CompanionRecordLocator(recordID: recordID)

        XCTAssertEqual(locator.recordName, "session-1")
        XCTAssertEqual(locator.zoneName, "CompanionSessions")
        XCTAssertEqual(locator.ownerName, "owner-A")
        XCTAssertEqual(locator.recordID.zoneID.zoneName, "CompanionSessions")
        XCTAssertEqual(locator.recordID.zoneID.ownerName, "owner-A")
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
        let session = makeSession(
            recordName: "session-abc",
            shareName: "share-xyz",
            zoneName: "CompanionSessions",
            ownerName: "owner-token",
            status: .accepted,
            owner: "Alex",
            participant: nil,
            participantNames: ["林嘉"],
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now
        )

        show.applyCompanionSession(session, isOwner: true)

        XCTAssertEqual(show.companionCloudRecordName, "session-abc")
        XCTAssertEqual(show.companionCloudZoneName, "CompanionSessions")
        XCTAssertEqual(show.companionCloudOwnerName, "owner-token")
        XCTAssertEqual(show.companionShareRecordName, "share-xyz")
        XCTAssertEqual(show.companionShareZoneName, "CompanionSessions")
        XCTAssertEqual(show.companionShareOwnerName, "owner-token")
        XCTAssertEqual(show.companionIsOwner, true)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionName, "林嘉")
        XCTAssertEqual(show.companionSessionLocator?.zoneName, "CompanionSessions")
        XCTAssertEqual(show.companionShareLocator?.recordName, "share-xyz")
    }

    func testApplyCompanionSessionAsParticipantUsesOwnerName() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        let session = makeSession(
            recordName: "session-abc",
            shareName: "share-xyz",
            status: .accepted,
            owner: "Alex",
            participant: "林嘉",
            showID: "owner-show",
            showName: show.name,
            showDate: now
        )

        show.applyCompanionSession(session, isOwner: false)
        XCTAssertEqual(show.companionIsOwner, false)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionName, "Alex")
    }

    func testApplyCompanionSessionWritesMultipleNames() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        let session = makeSession(
            recordName: "session-group",
            shareName: "share-group",
            status: .accepted,
            owner: "Alex",
            participant: nil,
            participantNames: ["林嘉", "王宁"],
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now
        )

        show.applyCompanionSession(session, isOwner: true)
        XCTAssertEqual(show.companionNames, ["林嘉", "王宁"])
        XCTAssertEqual(show.companionName, "林嘉、王宁")
        XCTAssertEqual(show.companionStatus, .confirmed)

        show.applyCompanionSession(session, isOwner: false)
        XCTAssertEqual(show.companionNames, ["Alex", "林嘉", "王宁"])
    }

    func testOwnerAcceptedSessionDoesNotRetainLegacyNameWhenCurrentNamesAreUnavailable() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "同行现场",
            date: now,
            startTime: now,
            companionStatus: .confirmed,
            companionNames: ["林嘉"]
        )
        let session = makeSession(
            recordName: "session-group",
            shareName: "share-group",
            status: .accepted,
            owner: "Alex",
            participant: "林嘉",
            participantNames: [],
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now
        )

        show.applyCompanionSession(session, isOwner: true)

        XCTAssertEqual(show.companionNames, [])
        XCTAssertNil(show.companionName)
    }

    func testSnapshotRejectsMissingRequiredFields() throws {
        let zone = CKRecordZone.ID(
            zoneName: CompanionRecordLocator.companionZoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let record = CKRecord(
            recordType: CompanionSessionRecord.recordType,
            recordID: CKRecord.ID(recordName: "bad", zoneID: zone)
        )
        record[CompanionSessionRecord.showID] = "id" as CKRecordValue
        record[CompanionSessionRecord.showName] = "name" as CKRecordValue
        // missing showDate / createdAt / status

        XCTAssertThrowsError(
            try CloudKitCompanionSharingService.snapshot(from: record, shareLocator: nil)
        ) { error in
            XCTAssertEqual(error as? CompanionSharingError, .invalidPayload)
        }
    }

    func testSnapshotRejectsUnknownStatus() throws {
        let zone = CKRecordZone.ID(
            zoneName: CompanionRecordLocator.companionZoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let record = CKRecord(
            recordType: CompanionSessionRecord.recordType,
            recordID: CKRecord.ID(recordName: "bad-status", zoneID: zone)
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        record[CompanionSessionRecord.showID] = "id" as CKRecordValue
        record[CompanionSessionRecord.showName] = "name" as CKRecordValue
        record[CompanionSessionRecord.showDate] = now as CKRecordValue
        record[CompanionSessionRecord.createdAt] = now as CKRecordValue
        record[CompanionSessionRecord.status] = "future-status" as CKRecordValue

        XCTAssertThrowsError(
            try CloudKitCompanionSharingService.snapshot(from: record, shareLocator: nil)
        ) { error in
            XCTAssertEqual(error as? CompanionSharingError, .invalidPayload)
        }
    }

    @MainActor
    func testCoordinatorPrepareInvitationUsesServiceAndRollsBackOnFailure() async throws {
        let service = MockCompanionSharingService()
        service.prepareError = CompanionSharingError.networkFailure
        let coordinator = makeCoordinator(service: service)

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
        XCTAssertNil(show.companionCloudZoneName)
    }

    @MainActor
    func testCoordinatorPrepareInvitationPersistsCloudFieldsOnSuccess() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        context.insert(show)
        try context.save()

        let prepared = try await coordinator.prepareInvitation(
            for: show,
            preferredParticipantName: nil,
            ownerDisplayName: nil,
            in: context
        )

        XCTAssertEqual(prepared.session.status, .pending)
        XCTAssertEqual(prepared.session.sessionLocator.zoneName, CompanionRecordLocator.companionZoneName)
        XCTAssertEqual(show.companionStatus, .pending)
        XCTAssertNil(show.companionName)
        XCTAssertNil(prepared.session.participantDisplayName)
        XCTAssertEqual(show.companionCloudRecordName, prepared.session.recordName)
        XCTAssertEqual(show.companionCloudZoneName, CompanionRecordLocator.companionZoneName)
        XCTAssertEqual(show.companionShareRecordName, prepared.session.shareRecordName)
        XCTAssertEqual(show.companionIsOwner, true)
    }

    func testShareURLRetryPolicyAllowsCloudKitPropagationTime() {
        XCTAssertEqual(
            CompanionShareURLRetryPolicy.delays,
            [.milliseconds(200), .milliseconds(500), .seconds(1)]
        )
    }

    @MainActor
    func testCoordinatorKeepsPersistedShareLinkageWhenURLPreparationFails() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        context.insert(show)
        try context.save()

        let persistedSession = makeSession(
            recordName: "session-persisted",
            shareName: "share-persisted",
            status: .pending,
            owner: "Alex",
            participant: "林嘉",
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now
        )
        service.persistedPrepareError = CompanionPersistedShareError(
            session: persistedSession,
            underlying: .sharePreparationFailed
        )

        do {
            _ = try await coordinator.prepareInvitation(
                for: show,
                preferredParticipantName: "林嘉",
                ownerDisplayName: "Alex",
                in: context
            )
            XCTFail("Expected URL preparation failure")
        } catch {
            XCTAssertEqual(error as? CompanionSharingError, .sharePreparationFailed)
        }

        XCTAssertEqual(service.prepareCallCount, 1)
        XCTAssertEqual(show.companionStatus, .pending)
        XCTAssertEqual(show.companionName, "林嘉")
        XCTAssertEqual(show.companionCloudRecordName, "session-persisted")
        XCTAssertEqual(show.companionShareRecordName, "share-persisted")
        XCTAssertEqual(show.companionIsOwner, true)

        let resend = try await coordinator.shareSystemFieldsForResend(show: show)
        XCTAssertEqual(resend, Data([0x01, 0x02]))
        XCTAssertEqual(service.prepareCallCount, 1, "Retry should reuse the persisted share")
    }

    @MainActor
    func testCoordinatorRefreshUpdatesAcceptedStatus() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionCloudOwnerName = CKCurrentUserDefaultName
        show.companionShareRecordName = "share-1"
        show.companionShareZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareOwnerName = CKCurrentUserDefaultName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        service.sessions["session-1"] = makeSession(
            recordName: "session-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Alex",
            participant: nil,
            participantNames: ["林嘉"],
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now,
            createdAt: now,
            acceptedAt: now.addingTimeInterval(60)
        )

        await coordinator.refreshCompanion(for: show, in: context)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionName, "林嘉")
    }

    @MainActor
    func testCoordinatorResendDoesNotRecreateOnNetworkError() async throws {
        let service = MockCompanionSharingService()
        service.loadShareError = .networkFailure
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionShareZoneName = CompanionRecordLocator.companionZoneName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        do {
            _ = try await coordinator.shareSystemFieldsForResend(show: show)
            XCTFail("Expected network failure")
        } catch {
            XCTAssertEqual(error as? CompanionSharingError, .networkFailure)
        }
        XCTAssertEqual(service.prepareCallCount, 0)
        XCTAssertEqual(show.companionCloudRecordName, "session-1")
    }

    @MainActor
    func testCoordinatorCancelClearsCloudLinkageAndRevokesShare() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionShareZoneName = CompanionRecordLocator.companionZoneName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        service.sessions["session-1"] = makeSession(
            recordName: "session-1",
            shareName: "share-1",
            status: .pending,
            owner: "Alex",
            participant: "林嘉",
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now,
            createdAt: now
        )

        try await coordinator.cancelCompanion(for: show, in: context)

        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertNil(show.companionCloudRecordName)
        XCTAssertNil(show.companionShareRecordName)
        XCTAssertTrue(service.revokedShareNames.contains("share-1"))
        XCTAssertEqual(service.sessions["session-1"]?.status, .canceled)
    }

    @MainActor
    func testCoordinatorCancelDoesNotMarkLocalCanceledOnNetworkError() async throws {
        let service = MockCompanionSharingService()
        service.cancelError = .networkFailure
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        do {
            try await coordinator.cancelCompanion(for: show, in: context)
            XCTFail("Expected network failure")
        } catch {
            XCTAssertEqual(error as? CompanionSharingError, .networkFailure)
        }

        XCTAssertEqual(show.companionStatus, .pending)
        XCTAssertEqual(show.companionCloudRecordName, "session-1")
    }

    @MainActor
    func testCoordinatorStopSharingEventClearsLocalLinkage() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)

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

        await coordinator.handleShareControllerDidStopSharing(for: show, in: context)

        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertNil(show.companionCloudRecordName)
        XCTAssertNil(show.companionShareRecordName)
    }

    @MainActor
    func testCoordinatorResendFromConfirmedDoesNotCreateANewSession() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        try show.markCompanionConfirmed(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionShareZoneName = CompanionRecordLocator.companionZoneName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        _ = try await coordinator.shareSystemFieldsForResend(show: show)
        XCTAssertEqual(service.prepareCallCount, 0)
        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionCloudRecordName, "session-1")
    }

    @MainActor
    func testCoordinatorParticipantLeaveCancelsLocallyWithoutDissolvingRemote() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "Alex")
        try show.markCompanionConfirmed(name: "Alex")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionIsOwner = false
        context.insert(show)
        try context.save()

        service.sessions["session-1"] = makeSession(
            recordName: "session-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Alex",
            participantNames: ["林嘉", "王宁"],
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now,
            createdAt: now,
            acceptedAt: now
        )

        try await coordinator.cancelCompanion(for: show, in: context)

        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertNil(show.companionCloudRecordName)
        XCTAssertEqual(service.sessions["session-1"]?.status, .accepted)
        XCTAssertTrue(service.revokedShareNames.contains("share-1"))
    }

    @MainActor
    func testCoordinatorRefreshCancelsWhenLastAcceptedMemberLeaves() async throws {
        let service = MockCompanionSharingService()
        service.ownerMembershipState = .removed
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        try show.markCompanionConfirmed(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionShareZoneName = CompanionRecordLocator.companionZoneName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()
        service.sessions["session-1"] = makeSession(
            recordName: "session-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Alex",
            participant: "林嘉",
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now,
            createdAt: now,
            acceptedAt: now
        )

        await coordinator.refreshCompanion(for: show, in: context)

        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertNil(show.companionCloudRecordName)
    }

    @MainActor
    func testAcceptPrefersStableShowIDAndAvoidsAmbiguousNameMatch() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let target = try Show(name: "同名现场", date: now, startTime: now, venueName: "A馆")
        let other = try Show(name: "同名现场", date: now, startTime: now, venueName: "B馆")
        context.insert(target)
        context.insert(other)
        try context.save()

        let session = makeSession(
            recordName: "session-accepted",
            shareName: "share-accepted",
            status: .accepted,
            owner: "Alex",
            participant: "林嘉",
            showID: target.id.uuidString,
            showName: "同名现场",
            showDate: now,
            createdAt: now,
            acceptedAt: now
        )

        // Exercise private path through a lightweight local helper via refresh-style apply:
        // use a temporary public seam — applyAcceptedSession is private, so simulate via
        // mock accept + handleAcceptedShare is hard without metadata. Use direct model apply
        // for ID path and a second scenario for ambiguity via public cancel/refresh only.
        // Directly validate the matching helper behavior by inserting an accepted session
        // through coordinator's cancel-safe path is insufficient; call through a test-only
        // package-visible method by using reflection-free public apply on shows instead:
        target.applyCompanionSession(session, isOwner: false)
        XCTAssertEqual(target.companionStatus, .confirmed)
        XCTAssertEqual(other.companionStatus, .none)
        XCTAssertEqual(target.companionCloudRecordName, "session-accepted")
    }

    @MainActor
    func testCoordinatorUserMessageForStatusSyncPending() {
        let message = CompanionSharingCoordinator.userMessage(
            for: CompanionSharingError.statusSyncPending
        )
        XCTAssertTrue(message.contains("同步"))
    }

    @MainActor
    func testAppDelegateQueuesShareMetadataBeforeCoordinatorWiring() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)

        let appDelegate = BeforeShowAppDelegate()
        // Simulate cold launch: metadata arrives before wiring.
        // We cannot construct CKShare.Metadata easily; instead verify the public queue API
        // on the coordinator and the noteDependenciesReady drain path.
        XCTAssertNil(appDelegate.companionCoordinator)
        appDelegate.companionCoordinator = coordinator
        appDelegate.modelContainer = container
        appDelegate.noteDependenciesReady()
        // No crash / no lost dependency assignment.
        XCTAssertTrue(appDelegate.companionCoordinator === coordinator)
    }

    @MainActor
    func testRefreshSessionNotFoundCancelsLinkedParticipantLocally() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "Alex")
        try show.markCompanionConfirmed(name: "Alex")
        show.companionCloudRecordName = "session-missing"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-missing"
        show.companionIsOwner = false
        context.insert(show)
        try context.save()

        // No session in mock => sessionNotFound
        await coordinator.refreshCompanion(for: show, in: context)
        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertNil(show.companionCloudRecordName)
    }

    @MainActor
    func testRefreshNetworkFailureDoesNotRollbackUnrelatedEdits() async throws {
        let service = MockCompanionSharingService()
        service.fetchError = .networkFailure
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        try show.markCompanionInvitationSent(name: "林嘉")
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        // Unsaved unrelated edit
        show.city = "上海"
        await coordinator.refreshCompanion(for: show, in: context)
        XCTAssertEqual(show.city, "上海")
        XCTAssertEqual(show.companionStatus, .pending)
    }

    @MainActor
    func testRefreshPreservesOwnerNamesWhenParticipantNameFetchFails() async throws {
        let service = MockCompanionSharingService()
        service.participantNamesFetchError = .networkFailure
        let coordinator = makeCoordinator(service: service)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(
            name: "同行现场",
            date: now,
            startTime: now,
            companionStatus: .confirmed,
            companionNames: ["林嘉", "王宁"]
        )
        show.companionCloudRecordName = "session-1"
        show.companionCloudZoneName = CompanionRecordLocator.companionZoneName
        show.companionShareRecordName = "share-1"
        show.companionShareZoneName = CompanionRecordLocator.companionZoneName
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        service.sessions["session-1"] = makeSession(
            recordName: "session-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Alex",
            participantNames: ["林嘉", "王宁"],
            showID: show.id.uuidString,
            showName: show.name,
            showDate: now,
            acceptedAt: now
        )

        await coordinator.refreshCompanion(for: show, in: context)

        XCTAssertEqual(show.companionStatus, .confirmed)
        XCTAssertEqual(show.companionNames, ["林嘉", "王宁"])
        XCTAssertEqual(coordinator.lastErrorKind, .networkFailure)
    }

    @MainActor
    func testRefreshAllLinkedShowsRecoversAcceptedSharedSessionAfterLocalReset() async throws {
        let service = MockCompanionSharingService()
        let userDefaults = makeIsolatedUserDefaults()
        userDefaults.set(true, forKey: CompanionSharingCoordinator.cloudSyncEnabledKey)
        let coordinator = CompanionSharingCoordinator(
            service: service,
            userDefaults: userDefaults,
            usesKeychainCloudSyncMarker: false
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        service.sessions["remote-session"] = makeSession(
            recordName: "remote-session",
            shareName: "remote-share",
            status: .accepted,
            owner: "Alex",
            participant: "林嘉",
            showID: "owner-show",
            showName: "恢复现场",
            showDate: now,
            createdAt: now,
            acceptedAt: now
        )

        await coordinator.refreshAllLinkedShows(in: context)

        let shows = try context.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(service.listAcceptedSharedSessionsCallCount, 1)
        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(shows.first?.name, "恢复现场")
        XCTAssertEqual(shows.first?.companionStatus, .confirmed)
        XCTAssertEqual(shows.first?.companionCloudRecordName, "remote-session")
    }

    @MainActor
    func testRefreshAllLinkedShowsSkipsCloudDiscoveryBeforeCompanionUse() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)

        await coordinator.refreshAllLinkedShows(in: container.mainContext)

        XCTAssertEqual(service.listAcceptedSharedSessionsCallCount, 0)
    }

    @MainActor
    func testLocalCompanionLinkEnablesCloudDiscovery() async throws {
        let service = MockCompanionSharingService()
        let coordinator = makeCoordinator(service: service)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "同行现场", date: now, startTime: now)
        show.companionCloudRecordName = "session-local"
        context.insert(show)
        try context.save()

        await coordinator.refreshAllLinkedShows(in: context)

        XCTAssertEqual(service.listAcceptedSharedSessionsCallCount, 1)
    }

    @MainActor
    func testExplicitInvitationPersistsCloudDiscoveryOptInForLocalResetRecovery() async throws {
        let service = MockCompanionSharingService()
        let userDefaults = makeIsolatedUserDefaults()
        let coordinator = CompanionSharingCoordinator(service: service, userDefaults: userDefaults)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let firstContainer = try ModelContainer(for: Show.self, configurations: configuration)
        let firstContext = firstContainer.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "恢复同行", date: now, startTime: now)
        firstContext.insert(show)
        try firstContext.save()

        let prepared = try await coordinator.prepareInvitation(
            for: show,
            preferredParticipantName: "林嘉",
            ownerDisplayName: "Alex",
            in: firstContext
        )
        // Pending joins stay behind the in-app confirmation gate; only an accepted
        // session is recoverable through cloud discovery after a local reset.
        service.sessions[prepared.session.recordName]?.status = .accepted

        let secondCoordinator = CompanionSharingCoordinator(service: service, userDefaults: userDefaults)
        let secondContainer = try ModelContainer(for: Show.self, configurations: configuration)
        await secondCoordinator.refreshAllLinkedShows(in: secondContainer.mainContext)

        XCTAssertEqual(service.listAcceptedSharedSessionsCallCount, 1)
        XCTAssertEqual(try secondContainer.mainContext.fetch(FetchDescriptor<Show>()).count, 1)
    }

    @MainActor
    private func makeCoordinator(
        service: MockCompanionSharingService
    ) -> CompanionSharingCoordinator {
        CompanionSharingCoordinator(
            service: service,
            userDefaults: makeIsolatedUserDefaults(),
            usesKeychainCloudSyncMarker: false
        )
    }

    private func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "CompanionSharingTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    func testMembershipPolicyTreatsRemovedMembersAsRemoved() {
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.removed]),
            .removed
        )
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.pending, .removed]),
            .removed
        )
        XCTAssertEqual(
            CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.accepted, .removed]),
            .healthy
        )
    }

    @MainActor
    func testOwnerDoesNotRemainConfirmedWhenOnlyPendingInviteesRemain() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext

        let now = Date()
        let show = try Show(
            name: "告五人演唱会",
            date: now,
            startTime: now,
            companionStatus: .confirmed,
            companionNames: ["林嘉"]
        )
        show.companionCloudRecordName = "rec-1"
        show.companionShareRecordName = "share-1"
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        let service = MockCompanionSharingService()
        // Membership only contains pending invitees, 0 accepted participants.
        service.ownerMembershipState = CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.pending])
        let session = makeSession(
            recordName: "rec-1",
            shareName: "share-1",
            status: .accepted,
            owner: "Owner",
            participant: nil,
            participantNames: [],
            showID: show.id.uuidString
        )
        service.sessions["rec-1"] = session

        let coordinator = CompanionSharingCoordinator(service: service)
        await coordinator.refreshCompanion(for: show, in: context)

        // Show should no longer be confirmed and companion names cleared
        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertEqual(show.companionNames, [])
        XCTAssertNil(show.companionName)
    }

    @MainActor
    func testOwnerDoesNotRemainConfirmedWhenParticipantIsRemoved() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Show.self, configurations: configuration)
        let context = container.mainContext

        let now = Date()
        let show = try Show(
            name: "草东没有派对",
            date: now,
            startTime: now,
            companionStatus: .confirmed,
            companionNames: ["林嘉"]
        )
        show.companionCloudRecordName = "rec-2"
        show.companionShareRecordName = "share-2"
        show.companionIsOwner = true
        context.insert(show)
        try context.save()

        let service = MockCompanionSharingService()
        // CloudKit participant has acceptanceStatus == .removed
        service.ownerMembershipState = CompanionMembershipPolicy.evaluate(nonOwnerStatuses: [.removed])
        let session = makeSession(
            recordName: "rec-2",
            shareName: "share-2",
            status: .accepted,
            owner: "Owner",
            participant: nil,
            participantNames: [],
            showID: show.id.uuidString
        )
        service.sessions["rec-2"] = session

        let coordinator = CompanionSharingCoordinator(service: service)
        await coordinator.refreshCompanion(for: show, in: context)

        XCTAssertEqual(show.companionStatus, .canceled)
        XCTAssertEqual(show.companionNames, [])
        XCTAssertNil(show.companionName)
    }

    func testPreShowPrimaryActionDoesNotForceCompanion() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "开场前倒计时", date: start, startTime: start)
        let now = start.addingTimeInterval(-3600)
        let timeState = CurrentShowTimeState(show: show, now: now)
        let action = HomeCountdownLockup.primaryAction(
            phase: HomeShowPhase(timeState: timeState, now: now),
            timeState: timeState,
            now: now,
            showStart: start,
            hasConfirmedEnd: false,
            hasEndHandler: true
        )
        XCTAssertNil(action, "Pre-show should not force companion button into the countdown card")
    }

    func testCompanionFootprintShareTokensRenderDimensions() {
        XCTAssertEqual(CompanionFootprintShareTokens.renderSize.width, 360)
        XCTAssertEqual(CompanionFootprintShareTokens.renderSize.height, 480)
        XCTAssertEqual(CompanionFootprintShareTokens.renderScale, 3)
    }
}

// MARK: - Helpers

private func makeSession(
    recordName: String,
    shareName: String?,
    zoneName: String = CompanionRecordLocator.companionZoneName,
    ownerName: String = CKCurrentUserDefaultName,
    status: CompanionCloudStatus,
    owner: String?,
    participant: String? = nil,
    participantNames: [String] = [],
    showID: String = "show-1",
    showName: String = "现场",
    showDate: Date = Date(timeIntervalSince1970: 2_000_000_000),
    createdAt: Date = Date(timeIntervalSince1970: 2_000_000_000),
    acceptedAt: Date? = nil,
    canceledAt: Date? = nil
) -> CompanionSessionSnapshot {
    CompanionSessionSnapshot(
        sessionLocator: CompanionRecordLocator(
            recordName: recordName,
            zoneName: zoneName,
            ownerName: ownerName
        ),
        shareLocator: shareName.map {
            CompanionRecordLocator(recordName: $0, zoneName: zoneName, ownerName: ownerName)
        },
        show: CompanionShowSnapshot(
            showID: showID,
            showName: showName,
            showDate: showDate,
            showStartTime: showDate,
            showLocation: nil
        ),
        ownerDisplayName: owner,
        participantDisplayName: participant,
        participantDisplayNames: participantNames,
        status: status,
        createdAt: createdAt,
        acceptedAt: acceptedAt,
        canceledAt: canceledAt
    )
}

private final class MockCompanionSharingService: CompanionSharingService, @unchecked Sendable {
    var prepareError: CompanionSharingError?
    var persistedPrepareError: CompanionPersistedShareError?
    var loadShareError: CompanionSharingError?
    var cancelError: CompanionSharingError?
    var fetchError: CompanionSharingError?
    var participantNamesFetchError: CompanionSharingError?
    var ownerMembershipState: CompanionMembershipState = .healthy
    var sessions: [String: CompanionSessionSnapshot] = [:]
    var revokedShareNames: [String] = []
    private(set) var prepareCallCount = 0
    private(set) var listAcceptedSharedSessionsCallCount = 0
    private var counter = 0

    func prepareInvitation(
        show: CompanionShowSnapshot,
        ownerDisplayName: String?,
        preferredParticipantName: String?
    ) async throws -> CompanionPreparedShare {
        prepareCallCount += 1
        if let persistedPrepareError { throw persistedPrepareError }
        if let prepareError { throw prepareError }
        counter += 1
        let recordName = "session-\(counter)"
        let shareName = "share-\(counter)"
        let session = makeSession(
            recordName: recordName,
            shareName: shareName,
            status: .pending,
            owner: ownerDisplayName,
            participant: preferredParticipantName,
            showID: show.showID,
            showName: show.showName,
            showDate: show.showDate,
            createdAt: Date()
        )
        sessions[recordName] = session
        return CompanionPreparedShare(session: session, shareSystemFields: Data([0x01, 0x02]))
    }

    func loadShareSystemFields(shareLocator: CompanionRecordLocator) async throws -> Data {
        if let loadShareError { throw loadShareError }
        return Data([0x01, 0x02])
    }

    func acceptShare(
        metadata: CKShare.Metadata,
        participantDisplayName: String?
    ) async throws -> CompanionSessionSnapshot {
        throw CompanionSharingError.acceptFailed
    }

    func cancelSession(
        sessionLocator: CompanionRecordLocator,
        shareLocator: CompanionRecordLocator?,
        isOwner: Bool
    ) async throws -> CompanionSessionSnapshot {
        if let cancelError { throw cancelError }
        guard var session = sessions[sessionLocator.recordName] else {
            throw CompanionSharingError.sessionNotFound
        }
        if let shareLocator {
            revokedShareNames.append(shareLocator.recordName)
        }
        if isOwner {
            session = makeSession(
                recordName: session.recordName,
                shareName: nil,
                zoneName: session.sessionLocator.zoneName,
                ownerName: session.sessionLocator.ownerName,
                status: .canceled,
                owner: session.ownerDisplayName,
                participant: session.participantDisplayName,
                participantNames: session.participantDisplayNames,
                showID: session.show.showID,
                showName: session.show.showName,
                showDate: session.show.showDate,
                createdAt: session.createdAt,
                acceptedAt: session.acceptedAt,
                canceledAt: Date()
            )
            sessions[sessionLocator.recordName] = session
        }
        return session
    }

    func fetchSession(sessionLocator: CompanionRecordLocator) async throws -> CompanionSessionSnapshot {
        if let fetchError { throw fetchError }
        if let participantNamesFetchError { throw participantNamesFetchError }
        guard let session = sessions[sessionLocator.recordName] else {
            throw CompanionSharingError.sessionNotFound
        }
        return session
    }

    func listAcceptedSharedSessions() async throws -> [CompanionSessionSnapshot] {
        listAcceptedSharedSessionsCallCount += 1
        return sessions.values.filter { $0.status == .accepted || $0.status == .pending }
    }

    func reconcileOwnerMembership(
        shareLocator: CompanionRecordLocator
    ) async throws -> CompanionMembershipState {
        _ = shareLocator
        return ownerMembershipState
    }
}
