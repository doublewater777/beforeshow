import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CompanionPostShowImportTests: XCTestCase {
    func testAcceptedShareAfterShowEndedWithinRetentionStaysInMyShows() throws {
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let showDate = now.addingTimeInterval(-86_400)
        let snapshot = CompanionShowSnapshot(
            showID: UUID().uuidString,
            showName: "刚散场的同行现场",
            showDate: showDate,
            showStartTime: showDate,
            sourceShowDate: showDate
        )
        let session = CompanionSessionSnapshot(
            sessionLocator: CompanionRecordLocator(
                recordName: "session-post-show",
                zoneName: CompanionRecordLocator.companionZoneName,
                ownerName: "owner-token"
            ),
            shareLocator: CompanionRecordLocator(
                recordName: "share-post-show",
                zoneName: CompanionRecordLocator.companionZoneName,
                ownerName: "owner-token"
            ),
            show: snapshot,
            ownerDisplayName: "Alex",
            participantDisplayName: nil,
            participantDisplayNames: [],
            status: .accepted,
            createdAt: now,
            acceptedAt: now,
            canceledAt: nil
        )

        let result = try CompanionAcceptedSessionImporter.apply(
            session,
            in: context,
            now: now
        )

        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(CurrentShowTimeState(show: imported, now: now).kind, .postShow)
        XCTAssertNotEqual(imported.wasAddedAsHistorical, true)
        XCTAssertFalse(result.wasHistorical)
        XCTAssertTrue(result.becameCurrent)

        let selection = try XCTUnwrap(
            CurrentShowSelectionStore(modelContext: context).canonicalSelection()
        )
        XCTAssertEqual(selection.selectedShowID, imported.id)
    }
}
