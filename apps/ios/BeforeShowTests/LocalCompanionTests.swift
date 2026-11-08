import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class LocalCompanionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    // MARK: - Domain operations

    func testAddTrimsSkipsBlanksAndDuplicates() throws {
        let show = try Show(name: "现场", date: now, startTime: now)

        XCTAssertTrue(show.addCompanion("  林嘉 "))
        XCTAssertFalse(show.addCompanion("林嘉"))
        XCTAssertFalse(show.addCompanion("   "))
        XCTAssertTrue(show.addCompanion("王宁"))

        XCTAssertEqual(show.companionNames, ["林嘉", "王宁"])
        XCTAssertTrue(show.hasCompanions)
    }

    func testRemoveIsTheOnlyWayOut() throws {
        let show = try Show(name: "现场", date: now, startTime: now)
        show.addCompanion("林嘉")
        show.addCompanion("王宁")

        show.removeCompanion("林嘉")

        XCTAssertEqual(show.companionNames, ["王宁"])
        show.removeCompanion("王宁")
        XCTAssertFalse(show.hasCompanions)
    }

    func testRenameFixesTypoAndMergesIntoExistingName() throws {
        let show = try Show(name: "现场", date: now, startTime: now)
        show.addCompanion("林佳")
        show.addCompanion("王宁")

        show.renameCompanion("林佳", to: " 林嘉 ")
        XCTAssertEqual(show.companionNames, ["林嘉", "王宁"])

        show.renameCompanion("林嘉", to: "王宁")
        XCTAssertEqual(show.companionNames, ["王宁"])

        show.renameCompanion("王宁", to: "  ")
        XCTAssertEqual(show.companionNames, ["王宁"])
    }

    func testPastFootprintCanBeBackfilledAndCountsImmediately() throws {
        let past = try endedShow("补填的足迹", daysAgo: 30, companions: [])
        XCTAssertTrue(CompanionHistory.shows(with: "林嘉", from: [past], now: now).isEmpty)

        past.addCompanion("林嘉")

        XCTAssertEqual(CompanionHistory.shows(with: "林嘉", from: [past], now: now).map(\.id), [past.id])
    }

    func testRecentNamesComeFromAllShowsNewestFirstWithoutCurrentNames() throws {
        let older = try endedShow("更早", daysAgo: 40, companions: ["林嘉", "阿树"])
        let newer = try endedShow("更近", daysAgo: 5, companions: ["王宁", "林嘉"])

        XCTAssertEqual(
            CompanionHistory.recentNames(from: [older, newer], excluding: ["阿树"]),
            ["王宁", "林嘉"]
        )
    }

    // MARK: - Counting

    func testCountWithPersonIncludesShowsSharedWithOthers() throws {
        let alone = try endedShow("只和 A", daysAgo: 20, companions: ["A"])
        let group = try endedShow("A 和 B", daysAgo: 10, companions: ["A", "B"])
        let future = try Show(name: "还没去", date: now.addingTimeInterval(86_400), startTime: now.addingTimeInterval(86_400))
        future.addCompanion("A")
        let all = [alone, group, future]

        XCTAssertEqual(CompanionHistory.shows(with: "A", from: all, now: now).count, 2)
        XCTAssertEqual(CompanionHistory.shows(with: "B", from: all, now: now).count, 1)

        let archive = FootprintArchiveBuilder.make(shows: all, now: now)
        let identity = FootprintDetailIdentityBuilder.make(show: group, archive: archive)
        XCTAssertEqual(
            identity.companions,
            [FootprintCompanionIdentity(name: "A", ordinal: 2), FootprintCompanionIdentity(name: "B", ordinal: 1)]
        )
        // The editor sheet and footprint detail read the same history.
        XCTAssertEqual(
            identity.companions.first { $0.name == "A" }?.ordinal,
            CompanionHistory.shows(with: "A", from: archive.shows, now: now).count
        )
    }

    func testLegacyStatusNoLongerGatesCounting() throws {
        let show = try endedShow("老数据", daysAgo: 3, companions: ["A"], legacyStatus: .none)
        XCTAssertEqual(CompanionHistory.shows(with: "A", from: [show], now: now).count, 1)
    }

    // MARK: - Migration

    func testMigrationKeepsConfirmedAndClearsPendingAndCanceledOnce() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let confirmed = try legacyShow("confirmed", status: .confirmed, names: ["林嘉"])
        let pending = try legacyShow("pending", status: .pending, names: ["王宁"])
        let canceled = try legacyShow("canceled", status: .canceled, names: ["阿树"])
        let untouched = try legacyShow("none", status: .none, names: [])
        let imported = try legacyShow("imported", status: .confirmed, names: ["Alex"], origin: .companionImport)
        [confirmed, pending, canceled, untouched, imported].forEach(context.insert)
        try context.save()
        let pendingUpdatedAt = pending.updatedAt

        LocalCompanionMigration.migrateIfNeeded(in: context, defaults: defaults)

        XCTAssertEqual(confirmed.companionNames, ["林嘉"])
        XCTAssertEqual(pending.companionNames, [])
        XCTAssertEqual(canceled.companionNames, [])
        XCTAssertEqual(untouched.companionNames, [])
        XCTAssertEqual(imported.companionNames, ["Alex"])
        XCTAssertEqual(imported.creationOrigin, .companionImport)
        XCTAssertFalse(imported.countsTowardFreeShowCapacity)
        XCTAssertEqual(pending.updatedAt, pendingUpdatedAt)

        // A second run never touches names the user wrote after upgrading.
        pending.addCompanion("新写的人")
        LocalCompanionMigration.migrateIfNeeded(in: context, defaults: defaults)
        XCTAssertEqual(pending.companionNames, ["新写的人"])
    }

    // MARK: - Old invite links

    func testOldLinkAddsInviterToExistingShowWithoutDuplicating() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let existing = try Show(
            name: "草东没有派对",
            date: start,
            startTime: start,
            timeZoneIdentifier: "Asia/Shanghai",
            venueName: "MAO",
            creationOrigin: .user
        )
        context.insert(existing)
        try context.save()
        let snapshot = try XCTUnwrap(CompanionInviteWebLink.snapshot(from: inviteURL(name: "草东没有派对", owner: "Alex")))

        let outcome = try LegacyCompanionInviteRouting.resolve(snapshot, isOnboardingActive: false, in: context)

        XCTAssertEqual(outcome, .addedCompanion(showID: existing.id, name: "Alex"))
        XCTAssertEqual(existing.companionNames, ["Alex"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 1)
        XCTAssertEqual(existing.creationOrigin, .user)
    }

    func testOldLinkWithoutLocalShowPrefillsAddFlowAsCompanionImport() throws {
        let context = try makeContext()
        let snapshot = try XCTUnwrap(CompanionInviteWebLink.snapshot(
            from: inviteURL(name: "新现场", owner: "Alex", location: "MAO Livehouse · 上海")
        ))

        let outcome = try LegacyCompanionInviteRouting.resolve(snapshot, isOnboardingActive: false, in: context)

        guard case .prefillAddShow(let draft) = outcome else {
            return XCTFail("Expected prefill, got \(outcome)")
        }
        XCTAssertEqual(draft.name, "新现场")
        XCTAssertEqual(draft.venueName, "MAO Livehouse")
        XCTAssertEqual(draft.city, "上海")
        XCTAssertEqual(draft.startTime, Date(timeIntervalSince1970: 1_900_000_000))
        let show = try draft.makeShow()
        XCTAssertEqual(show.companionNames, ["Alex"])
        XCTAssertEqual(show.creationOrigin, .companionImport)
        XCTAssertFalse(show.countsTowardFreeShowCapacity)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Show>()).isEmpty)
    }

    func testOldLinkWaitsForOnboarding() throws {
        let context = try makeContext()
        let snapshot = try XCTUnwrap(CompanionInviteWebLink.snapshot(from: inviteURL(name: "新现场", owner: "Alex")))

        XCTAssertEqual(
            try LegacyCompanionInviteRouting.resolve(snapshot, isOnboardingActive: true, in: context),
            .deferred
        )
    }

    func testInvalidAndCloudKitLinksAreSwallowedSilently() throws {
        let inbox = LegacyCompanionInviteInbox()
        let urls = [
            "https://beforeshow.doublewaterapps.com/join/not-base64",
            "beforeshow://join/%%%",
            "https://www.icloud.com/share/abc123#CompanionSessions",
            "https://www.icloud.com.cn/share/07eSuMIaRuOnwy6KE2DNkgH_w",
        ]
        for raw in urls {
            XCTAssertTrue(inbox.receive(try XCTUnwrap(URL(string: raw))), raw)
            XCTAssertNil(inbox.pending, raw)
        }
        XCTAssertFalse(inbox.receive(try XCTUnwrap(URL(string: "beforeshow://listen"))))
        XCTAssertFalse(inbox.receive(try XCTUnwrap(URL(string: "https://example.com/join/abc"))))
    }

    func testInboxKeepsValidLinkAndIgnoresRepeatDelivery() throws {
        let inbox = LegacyCompanionInviteInbox()
        let url = inviteURL(name: "新现场", owner: "Alex")
        let token = String(url.path.dropFirst(CompanionInviteWebLink.path.count))

        XCTAssertTrue(inbox.receive(url))
        XCTAssertEqual(inbox.pending?.showName, "新现场")
        XCTAssertEqual(inbox.pending?.ownerName, "Alex")
        inbox.pending = nil
        XCTAssertTrue(inbox.receive(try XCTUnwrap(URL(string: "beforeshow://join/\(token)"))))
        XCTAssertNil(inbox.pending)

        let wechat = try XCTUnwrap(URL(string: "\(inviteURL(name: "另一场", owner: nil).absoluteString)?from=singlemessage"))
        XCTAssertTrue(inbox.receive(wechat))
        XCTAssertEqual(inbox.pending?.showName, "另一场")
        XCTAssertNil(inbox.pending?.ownerName)
    }

    func testNameListDropsBlanksAndJoinsWithDunhao() {
        XCTAssertEqual(CompanionNameList.normalized([" 林嘉 ", "", "王宁", "林嘉"]), ["林嘉", "王宁"])
        XCTAssertEqual(CompanionNameList.joined(["林嘉", "王宁"]), "林嘉、王宁")
        XCTAssertNil(CompanionNameList.joined([" ", ""]))
    }

    func testEntryTitleNamesWhoCame() {
        XCTAssertEqual(CompanionQuickActionPresentation(companionNames: []).displayTitle, BSLocalization.text("和谁去"))
        XCTAssertFalse(CompanionQuickActionPresentation(companionNames: []).showsAvatars)
        XCTAssertEqual(
            CompanionQuickActionPresentation(companionNames: ["林嘉"]).displayTitle,
            BSLocalization.format("与%@同行", "林嘉")
        )
        let group = CompanionQuickActionPresentation(companionNames: ["林嘉", " 王宁 "])
        XCTAssertEqual(group.displayTitle, BSLocalization.format("%lld 人同行", Int64(3)))
        XCTAssertEqual(group.companionName, "林嘉、王宁")
        XCTAssertTrue(group.showsAvatars)
    }

    func testCompanionCopyExistsInThreeLanguages() throws {
        let catalog = try StringCatalog("Localizable")
        let keys = [
            "和谁去", "同行，和谁去", "同行，%@", "与%@同行", "%lld 人同行", "名字", "添加",
            "移除%@", "一起 %lld 场", "已记下与%@同行", "记下和谁一起去",
            "和谁一起去？记下来，散场后会留在足迹里。",
        ]
        for locale in ["zh-Hans", "zh-Hant", "en"] {
            let values = catalog.table(locale)
            for key in keys {
                XCTAssertFalse(values[key]?.isEmpty ?? true, "Missing \(locale): \(key)")
            }
        }
    }

    func testUniversalLinkConfigurationStillMatchesWebsiteAssociation() throws {
        let appsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementData = try Data(contentsOf: appsRoot.appendingPathComponent("ios/BeforeShow/BeforeShow.entitlements"))
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: entitlementData, format: nil) as? [String: Any]
        )
        let domains = try XCTUnwrap(entitlements["com.apple.developer.associated-domains"] as? [String])
        XCTAssertTrue(domains.contains("applinks:\(CompanionInviteWebLink.host)"))

        let associationData = try Data(
            contentsOf: appsRoot.appendingPathComponent("web/public/.well-known/apple-app-site-association")
        )
        let association = try XCTUnwrap(JSONSerialization.jsonObject(with: associationData) as? [String: Any])
        let applinks = try XCTUnwrap(association["applinks"] as? [String: Any])
        let details = try XCTUnwrap(applinks["details"] as? [[String: Any]])
        XCTAssertTrue(details.contains {
            ($0["paths"] as? [String])?.contains(CompanionInviteWebLink.path) == true
        })
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Show.self,
            CurrentShowSelection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        addTeardownBlock { _ = container }
        return container.mainContext
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "LocalCompanionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func endedShow(
        _ name: String,
        daysAgo: Double,
        companions: [String],
        legacyStatus: ShowCompanionStatus = .none
    ) throws -> Show {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let show = try Show(
            name: name,
            date: date,
            startTime: date,
            legacyCompanionStatus: legacyStatus,
            companionNames: companions
        )
        show.markEnded(at: date.addingTimeInterval(7_200))
        return show
    }

    private func legacyShow(
        _ name: String,
        status: ShowCompanionStatus,
        names: [String],
        origin: ShowCreationOrigin = .user
    ) throws -> Show {
        try Show(
            name: name,
            date: now,
            startTime: now,
            legacyCompanionStatus: status,
            companionNames: names,
            creationOrigin: origin,
            updatedAt: now.addingTimeInterval(-3_600)
        )
    }

    private func inviteURL(name: String, owner: String?, location: String? = nil) -> URL {
        var payload: [String: Any] = [
            "v": 1,
            "u": "https://www.icloud.com/share/legacy-\(UUID().uuidString.prefix(8))",
            "n": name,
            "t": 1_900_000_000,
            "z": "Asia/Shanghai",
        ]
        payload["o"] = owner
        payload["l"] = location
        let token = try! JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "https://\(CompanionInviteWebLink.host)\(CompanionInviteWebLink.path)\(token)")!
    }
}
