import CloudKit
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionAcceptedImportRegressionTests: XCTestCase {
    func testAcceptedFutureShareCreatesCompleteShowAndBecomesCurrentWhenNoneExists() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showID = UUID()
        let showDate = now.addingTimeInterval(86_400)
        let snapshot = CompanionShowSnapshot(
            showID: showID.uuidString,
            showName: "完整同行现场",
            showDate: showDate,
            showStartTime: showDate.addingTimeInterval(19 * 3_600 + 30 * 60),
            showLocation: "体育馆 · 上海",
            sourceShowDate: showDate,
            timeZoneSecondsFromGMT: 8 * 3_600,
            timeZoneIdentifier: "Asia/Shanghai",
            city: "上海",
            venueName: "体育馆",
            venueAddress: "测试路 1 号",
            artists: [
                CompanionArtistSnapshot(
                    name: "测试艺人",
                    avatarURL: "https://example.com/avatar.jpg",
                    appleMusicURL: "https://music.apple.com/artist/test/123",
                    appleMusicArtistID: "123",
                    albumArtworkURL: "https://example.com/album.jpg"
                )
            ],
            coverImageURL: "https://example.com/cover.jpg"
        )

        let result = try CompanionAcceptedSessionImporter.apply(
            makeSession(show: snapshot),
            in: context,
            now: now
        )

        let shows = try context.fetch(FetchDescriptor<Show>())
        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        XCTAssertEqual(shows.count, 1)
        let imported = try XCTUnwrap(shows.first)
        XCTAssertEqual(imported.id, showID)
        XCTAssertEqual(imported.name, "完整同行现场")
        XCTAssertEqual(imported.city, "上海")
        XCTAssertEqual(imported.venueName, "体育馆")
        XCTAssertEqual(imported.venueAddress, "测试路 1 号")
        XCTAssertEqual(imported.coverImageURL, "https://example.com/cover.jpg")
        XCTAssertEqual(imported.artists.count, 1)
        XCTAssertEqual(imported.artists.first?.appleMusicArtistID, "123")
        XCTAssertEqual(imported.creationOrigin.rawValue, ShowCreationOrigin.companionImport.rawValue)
        XCTAssertEqual(imported.companionStatus, .confirmed)
        XCTAssertEqual(imported.companionName, "Alex")
        XCTAssertEqual(selections.first?.selectedShowID, showID)
        XCTAssertTrue(result.inserted)
        XCTAssertTrue(result.becameCurrent)
        XCTAssertFalse(result.wasHistorical)
    }

    func testAcceptedShareDoesNotReplaceExistingCurrentShow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        let current = try Show(
            name: "原来的当前现场",
            date: now.addingTimeInterval(172_800),
            startTime: now.addingTimeInterval(172_800)
        )
        context.insert(current)
        context.insert(CurrentShowSelection(selectedShowID: current.id))
        try context.save()

        let incomingDate = now.addingTimeInterval(86_400)
        let incoming = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "同行现场",
            showDate: incomingDate,
            showStartTime: incomingDate,
            sourceShowDate: incomingDate
        )

        let result = try CompanionAcceptedSessionImporter.apply(
            makeSession(show: incoming),
            in: context,
            now: now
        )

        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        XCTAssertEqual(selections.first?.selectedShowID, current.id)
        XCTAssertFalse(result.becameCurrent)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 2)
    }

    func testAcceptedShareMergesIntoExistingLocalShowAndOnlyFillsMissingData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showDate = now.addingTimeInterval(86_400)
        let start = showDate.addingTimeInterval(19 * 3_600)

        let local = try Show(
            name: "同一场现场",
            date: showDate,
            startTime: start,
            city: "上海",
            artists: [ArtistSlot(name: "测试艺人", avatarURL: nil)],
            coverImageURL: "https://local.example/cover.jpg",
            creationOrigin: .user
        )
        context.insert(local)
        try context.save()

        let incoming = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "同一场现场",
            showDate: showDate,
            showStartTime: start,
            showLocation: "体育馆 · 上海",
            sourceShowDate: showDate,
            city: "上海",
            venueName: "体育馆",
            venueAddress: "测试路 1 号",
            artists: [
                CompanionArtistSnapshot(
                    name: "测试艺人",
                    avatarURL: "https://example.com/avatar.jpg",
                    appleMusicURL: nil,
                    appleMusicArtistID: "123",
                    albumArtworkURL: nil
                )
            ],
            coverImageURL: "https://invite.example/cover.jpg"
        )

        let result = try CompanionAcceptedSessionImporter.apply(
            makeSession(show: incoming),
            in: context,
            now: now
        )

        let shows = try context.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(result.showID, local.id)
        XCTAssertFalse(result.inserted)
        XCTAssertEqual(local.creationOrigin.rawValue, ShowCreationOrigin.user.rawValue)
        XCTAssertEqual(local.venueName, "体育馆")
        XCTAssertEqual(local.venueAddress, "测试路 1 号")
        XCTAssertEqual(local.coverImageURL, "https://local.example/cover.jpg")
        XCTAssertEqual(local.artists.count, 1)
        XCTAssertEqual(local.artists.first?.appleMusicArtistID, "123")
        XCTAssertEqual(local.artists.first?.avatarURL, "https://example.com/avatar.jpg")
        XCTAssertEqual(local.companionStatus, .confirmed)
    }

    func testAcceptedHistoricalShareGoesToFootprintsAndDoesNotCreateCurrentSelection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let historicalDate = now.addingTimeInterval(-400 * 86_400)
        let incoming = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "很久以前的同行现场",
            showDate: historicalDate,
            showStartTime: historicalDate,
            sourceShowDate: historicalDate
        )

        let result = try CompanionAcceptedSessionImporter.apply(
            makeSession(show: incoming),
            in: context,
            now: now
        )

        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(imported.wasAddedAsHistorical, true)
        XCTAssertTrue(result.wasHistorical)
        XCTAssertFalse(result.becameCurrent)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CurrentShowSelection>()).isEmpty)
    }

    func testRepeatedAcceptedSessionIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showDate = now.addingTimeInterval(86_400)
        let snapshot = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "幂等现场",
            showDate: showDate,
            showStartTime: showDate,
            sourceShowDate: showDate
        )
        let session = makeSession(show: snapshot)

        _ = try CompanionAcceptedSessionImporter.apply(session, in: context, now: now)
        _ = try CompanionAcceptedSessionImporter.apply(session, in: context, now: now)

        let shows = try context.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(shows.count, 1)
        XCTAssertEqual(shows.first?.companionCloudRecordName, session.sessionLocator.recordName)
    }

    func testSnapshotDropsDeviceLocalCoverButKeepsRemoteCover() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let local = try Show(
            name: "本地封面现场",
            date: now,
            startTime: now,
            coverImageURL: "file:///private/var/mobile/Containers/Data/cover.jpg"
        )
        XCTAssertNil(CompanionShowSnapshot(show: local).coverImageURL)

        let remote = try Show(
            name: "远程封面现场",
            date: now,
            startTime: now,
            coverImageURL: "https://example.com/cover.jpg"
        )
        XCTAssertEqual(
            CompanionShowSnapshot(show: remote).coverImageURL,
            "https://example.com/cover.jpg"
        )
    }

    func testUndatedPostponedSnapshotStaysUndatedAndDoesNotBecomeCurrent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let originalDate = now.addingTimeInterval(30 * 86_400)
        let snapshot = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "延期待定现场",
            showDate: originalDate,
            showStartTime: originalDate,
            sourceShowDate: originalDate,
            showChangeStatusRawValue: ShowChangeStatus.postponed.rawValue,
            postponedDate: nil
        )

        let result = try CompanionAcceptedSessionImporter.apply(
            makeSession(show: snapshot),
            in: context,
            now: now
        )

        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(imported.changeStatus, .postponed)
        XCTAssertNil(imported.postponedDate)
        XCTAssertEqual(CurrentShowTimeState(show: imported, now: now).kind, .postponed)
        XCTAssertFalse(result.becameCurrent)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CurrentShowSelection>()).isEmpty)
    }

    func testCloudSnapshotDecoderPrefersFrozenFullPayloadAndKeepsLegacyFieldsCompatible() throws {
        let zone = CKRecordZone.ID(
            zoneName: CompanionRecordLocator.companionZoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let record = CKRecord(
            recordType: CompanionSessionRecord.recordType,
            recordID: CKRecord.ID(recordName: "session-full", zoneID: zone)
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let frozen = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "完整快照",
            showDate: now,
            showStartTime: now,
            showLocation: "场馆 · 城市",
            sourceShowDate: now,
            city: "城市",
            venueName: "场馆",
            artists: [
                CompanionArtistSnapshot(
                    name: "艺人",
                    avatarURL: nil,
                    appleMusicURL: nil,
                    appleMusicArtistID: "artist-id",
                    albumArtworkURL: nil
                )
            ]
        )
        record[CompanionSessionRecord.showID] = frozen.showID as CKRecordValue
        record[CompanionSessionRecord.showName] = frozen.showName as CKRecordValue
        record[CompanionSessionRecord.showDate] = now as CKRecordValue
        record[CompanionSessionRecord.showStartTime] = now as CKRecordValue
        record[CompanionSessionRecord.showSnapshotV1] = try JSONEncoder().encode(frozen) as CKRecordValue
        record[CompanionSessionRecord.createdAt] = now as CKRecordValue
        record[CompanionSessionRecord.status] = CompanionCloudStatus.accepted.rawValue as CKRecordValue

        let decoded = try CloudKitCompanionSharingService.snapshot(from: record, shareLocator: nil)
        XCTAssertEqual(decoded.show.venueName, "场馆")
        XCTAssertEqual(decoded.show.city, "城市")
        XCTAssertEqual(decoded.show.artists.first?.appleMusicArtistID, "artist-id")
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: configuration
        )
    }

    private func makeSession(show: CompanionShowSnapshot) -> CompanionSessionSnapshot {
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
            status: .accepted,
            createdAt: Date(timeIntervalSince1970: 1_999_999_000),
            acceptedAt: Date(timeIntervalSince1970: 2_000_000_000),
            canceledAt: nil
        )
    }
}
