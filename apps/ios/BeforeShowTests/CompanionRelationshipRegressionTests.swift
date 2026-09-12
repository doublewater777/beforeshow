import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionRelationshipRegressionTests: XCTestCase {
    func testAmbiguousAcceptedImportCanMergeIntoChosenLocalShowAndTransfersCurrentSelection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let date = now.addingTimeInterval(86_400)

        let first = try Show(
            name: "重复现场",
            date: date,
            startTime: date,
            city: "上海",
            venueName: "体育馆",
            creationOrigin: .user
        )
        let second = try Show(
            name: "重复现场",
            date: date,
            startTime: date,
            city: "上海",
            venueName: "体育馆",
            creationOrigin: .user
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let snapshot = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "重复现场",
            showDate: date,
            showStartTime: date,
            sourceShowDate: date,
            city: "上海",
            venueName: "体育馆"
        )
        let session = makeSession(show: snapshot)
        let result = try CompanionAcceptedSessionImporter.apply(session, in: context, now: now)

        XCTAssertTrue(result.inserted)
        let imported = try XCTUnwrap(
            context.fetch(FetchDescriptor<Show>()).first(where: {
                $0.companionCloudRecordName == session.sessionLocator.recordName
            })
        )
        XCTAssertEqual(
            try CurrentShowSelectionStore(modelContext: context).canonicalSelection()?.selectedShowID,
            imported.id
        )

        let suiteName = "CompanionDuplicateResolutionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resolution = try XCTUnwrap(
            CompanionDuplicateResolutionFinder.first(
                in: context.fetch(FetchDescriptor<Show>()),
                userDefaults: defaults
            )
        )
        XCTAssertEqual(Set(resolution.candidates.map(\.id)), Set([first.id, second.id]))

        try CompanionDuplicateMerger.merge(imported: imported, into: second, in: context)

        let shows = try context.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(shows.count, 2)
        XCTAssertFalse(shows.contains(where: { $0.id == imported.id }))
        XCTAssertEqual(second.companionStatus, .confirmed)
        XCTAssertEqual(second.companionName, "Alex")
        XCTAssertEqual(second.companionCloudRecordName, session.sessionLocator.recordName)
        XCTAssertEqual(first.companionStatus, .none)
        XCTAssertEqual(
            try CurrentShowSelectionStore(modelContext: context).canonicalSelection()?.selectedShowID,
            second.id
        )
    }

    func testKeepingAmbiguousImportedShowSeparateSuppressesFuturePrompt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let date = now.addingTimeInterval(86_400)

        for _ in 0..<2 {
            context.insert(try Show(
                name: "重复现场",
                date: date,
                startTime: date,
                city: "上海",
                venueName: "体育馆",
                creationOrigin: .user
            ))
        }
        let session = makeSession(show: CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "重复现场",
            showDate: date,
            showStartTime: date,
            sourceShowDate: date,
            city: "上海",
            venueName: "体育馆"
        ))
        _ = try CompanionAcceptedSessionImporter.apply(session, in: context, now: now)

        let suiteName = "CompanionDuplicateIgnoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shows = try context.fetch(FetchDescriptor<Show>())
        XCTAssertNotNil(CompanionDuplicateResolutionFinder.first(in: shows, userDefaults: defaults))

        CompanionDuplicateResolutionStore.ignore(
            sessionRecordName: session.sessionLocator.recordName,
            userDefaults: defaults
        )
        XCTAssertNil(CompanionDuplicateResolutionFinder.first(in: shows, userDefaults: defaults))
    }

    func testPairwiseHistoryIncludesShowsFromDifferentGroupCompositions() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let first = try endedShow(
            name: "只和林嘉",
            date: now.addingTimeInterval(-3 * 86_400),
            companions: ["林嘉"]
        )
        let group = try endedShow(
            name: "林嘉和王宁",
            date: now.addingTimeInterval(-2 * 86_400),
            companions: ["林嘉", "王宁"]
        )
        let other = try endedShow(
            name: "只和王宁",
            date: now.addingTimeInterval(-86_400),
            companions: ["王宁"]
        )
        let future = try Show(
            name: "还没发生",
            date: now.addingTimeInterval(86_400),
            startTime: now.addingTimeInterval(86_400)
        )
        future.applyCompanionState(status: .confirmed, names: ["林嘉"])

        let withJia = CompanionPairHistory.shows(
            with: "林嘉",
            from: [first, group, other, future],
            now: now
        )
        XCTAssertEqual(Set(withJia.map(\.id)), Set([first.id, group.id]))

        let withNing = CompanionPairHistory.shows(
            with: "王宁",
            from: [first, group, other, future],
            now: now
        )
        XCTAssertEqual(Set(withNing.map(\.id)), Set([group.id, other.id]))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
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

    private func endedShow(
        name: String,
        date: Date,
        companions: [String]
    ) throws -> Show {
        let show = try Show(name: name, date: date, startTime: date)
        show.applyCompanionState(status: .confirmed, names: companions)
        show.markEnded(at: date.addingTimeInterval(7_200))
        return show
    }
}
