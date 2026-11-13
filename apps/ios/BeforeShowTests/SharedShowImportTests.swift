import SwiftData
import XCTest
@testable import BeforeShow

/// 扫到别人分享的现场：没有就打开预填好的添加现场，已经有了只提示一次。
@MainActor
final class SharedShowImportTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)

    func testNewShowOpensAddShowPrefilled() throws {
        let context = try makeContext()
        let draft = try sharedDraft()

        guard case .prefill(let prefilled) = try SharedShowImportRouting.resolve(draft, isOnboardingActive: false, in: context) else {
            return XCTFail("Expected the add-show flow")
        }
        XCTAssertEqual(prefilled, draft)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Show>()).isEmpty, "Nothing is added until the user saves")
        XCTAssertEqual(try prefilled.makeShow().creationOrigin, .user)
    }

    func testShowAlreadyHereIsNotAddedAgain() throws {
        let context = try makeContext()
        context.insert(try Show(name: "草东没有派对", date: start, startTime: start, timeZoneIdentifier: "Asia/Shanghai", city: "上海", venueName: "MAO"))
        try context.save()

        XCTAssertEqual(try SharedShowImportRouting.resolve(try sharedDraft(), isOnboardingActive: false, in: context), .alreadyAdded)
    }

    func testScanWaitsForOnboarding() throws {
        XCTAssertEqual(try SharedShowImportRouting.resolve(try sharedDraft(), isOnboardingActive: true, in: makeContext()), .deferred)
    }

    func testInboxTakesShowLinksOnly() throws {
        let inbox = SharedShowInbox()
        let link = try sharedLink()
        let now = Date()

        XCTAssertFalse(inbox.receive(try XCTUnwrap(URL(string: "beforeshow://listen")), now: now))
        XCTAssertTrue(inbox.receive(try XCTUnwrap(URL(string: "https://beforeshow.doublewaterapps.com/s/broken")), now: now))
        XCTAssertNil(inbox.pending, "A broken link opens the app and nothing else")

        XCTAssertTrue(inbox.receive(link, now: now))
        XCTAssertEqual(inbox.pending?.draft.name, "草东没有派对")
    }

    func testOneOpenDeliveredTwiceIsHandledOnceButAScanLaterCountsAgain() throws {
        let inbox = SharedShowInbox()
        let link = try sharedLink()
        let now = Date()

        inbox.receive(link, now: now)
        inbox.pending = nil
        inbox.receive(link, now: now.addingTimeInterval(0.2))
        XCTAssertNil(inbox.pending, "The scene delegate and SwiftUI deliver the same open")

        inbox.receive(link, now: now.addingTimeInterval(60))
        XCTAssertNotNil(inbox.pending, "Scanning the same code again after cancelling opens it again")
    }

    // MARK: Helpers

    private func sharedLink() throws -> URL {
        let show = try Show(name: "草东没有派对", date: start, startTime: start, timeZoneIdentifier: "Asia/Shanghai", city: "上海", venueName: "MAO")
        return ShowShareLink.url(for: show)
    }

    private func sharedDraft() throws -> ShowDraft {
        try XCTUnwrap(ShowShareLink.draft(from: sharedLink()))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        addTeardownBlock { _ = container }
        return container.mainContext
    }
}
