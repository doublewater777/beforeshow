import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ShowRecordPersistenceTests: XCTestCase {
    private func onDiskConfiguration() throws -> (ModelConfiguration, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ModelConfiguration(url: directory.appendingPathComponent("BeforeShow.store"), cloudKitDatabase: .none), directory)
    }

    private func makeShow(_ name: String = "Show") throws -> Show {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        return try Show(name: name, date: start, startTime: start)
    }

    func testSpendingAndMerchSurviveReopeningStore() throws {
        let (configuration, directory) = try onDiskConfiguration()
        defer { try? FileManager.default.removeItem(at: directory) }
        let show = try makeShow()
        let showID = show.id
        do {
            let container = try ModelContainerFactory.make(configuration: configuration)
            container.mainContext.insert(show)
            try show.setSpending(ticketPrice: Decimal(string: "380.5"), travelCost: 0, currencyCode: "CNY")
            let item = MerchItem(showID: showID, kind: .tee, name: "巡演 T 恤", relativePath: "\(showID.uuidString)/merch/a.jpg", cutoutRelativePath: "\(showID.uuidString)/merch/a.png")
            item.show = show
            container.mainContext.insert(item)
            try container.mainContext.save()
        }

        let reopened = try ModelContainerFactory.make(configuration: configuration)
        let loaded = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Show>()).first)
        XCTAssertEqual(loaded.ticketPrice, Decimal(string: "380.5"))
        XCTAssertEqual(loaded.travelCost, 0)
        XCTAssertEqual(loaded.currencyCode, "CNY")
        let merch = try reopened.mainContext.fetch(FetchDescriptor<MerchItem>())
        XCTAssertEqual(merch.count, 1)
        XCTAssertEqual(merch.first?.kind, .tee)
        XCTAssertEqual(merch.first?.displayName, "巡演 T 恤")
        XCTAssertEqual(merch.first?.show?.id, showID)
        XCTAssertEqual(loaded.merchItems.count, 1)
    }

    func testShowWithoutNewFieldsReadsAsUnrecorded() throws {
        let show = try makeShow()
        XCTAssertNil(show.ticketPrice)
        XCTAssertNil(show.travelCost)
        XCTAssertNil(show.currencyCode)
        XCTAssertFalse(show.hasAnySpending)
        XCTAssertEqual(show.spendingCurrencyCode, Show.defaultCurrencyCode)
        XCTAssertTrue(show.merchItems.isEmpty)
    }

    func testDeletingShowCascadesMerch() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)
        let item = MerchItem(showID: show.id, relativePath: "\(show.id.uuidString)/merch/a.jpg")
        item.show = show
        context.insert(item)
        try context.save()

        context.delete(show)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<MerchItem>()).isEmpty)
    }

    func testSpendingRejectsNegativeAndClearsCurrencyWhenEmpty() throws {
        let show = try makeShow()
        XCTAssertThrowsError(try show.setSpending(ticketPrice: -1, travelCost: nil)) {
            XCTAssertEqual($0 as? ShowSpendingError, .negativeAmount)
        }
        try show.setSpending(ticketPrice: 100, travelCost: nil)
        XCTAssertEqual(show.currencyCode, Show.defaultCurrencyCode)
        XCTAssertTrue(show.hasAnySpending)
        XCTAssertFalse(show.hasCompleteSpending)
        try show.setSpending(ticketPrice: nil, travelCost: nil)
        XCTAssertNil(show.currencyCode)
    }

    func testMerchPathValidationStaysInsideShowMerchFolder() {
        let id = UUID()
        XCTAssertTrue(MerchItem.isValidRelativePath("\(id.uuidString)/merch/x.jpg", showID: id))
        XCTAssertFalse(MerchItem.isValidRelativePath("\(id.uuidString)/ticket/x.jpg", showID: id))
        XCTAssertFalse(MerchItem.isValidRelativePath("\(UUID().uuidString)/merch/x.jpg", showID: id))
        XCTAssertFalse(MerchItem.isValidRelativePath("\(id.uuidString)/merch/..", showID: id))
    }

    func testSetlistRecordingTogglesAndDedupesManualSongs() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let showID = UUID()
        let song = ShowSetlistRecording.Song(catalogSongID: "s1", title: "云烟成雨", artistName: "房东的猫")

        XCTAssertTrue(try ShowSetlistRecording.toggle(song, showID: showID, in: context))
        let stored = try ShowSetlistRecording.memories(showID: showID, in: context)
        XCTAssertEqual(stored.map(\.catalogSongID), ["s1"])
        XCTAssertEqual(stored.first?.manualTitle, "云烟成雨")

        try ShowSetlistRecording.addManual(title: " 安可 ", artistName: "房东的猫", showID: showID, in: context)
        try ShowSetlistRecording.addManual(title: "安可", artistName: "房东的猫", showID: showID, in: context)
        try ShowSetlistRecording.addManual(title: "  ", artistName: "房东的猫", showID: showID, in: context)
        XCTAssertEqual(try ShowSetlistRecording.memories(showID: showID, in: context).count, 2)

        XCTAssertFalse(try ShowSetlistRecording.toggle(song, showID: showID, in: context))
        XCTAssertEqual(try ShowSetlistRecording.memories(showID: showID, in: context).map(\.manualTitle), ["安可"])
    }

    func testMerchReconcileKeepsLiveFilesAndDropsOrphanRecords() throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try makeShow()
        context.insert(show)
        let photo = "\(show.id.uuidString)/merch/a.jpg"
        let cutout = "\(show.id.uuidString)/merch/a-cutout.png"
        let kept = MerchItem(showID: show.id, relativePath: photo, cutoutRelativePath: cutout)
        kept.show = show
        let missingFile = MerchItem(showID: show.id, relativePath: "\(show.id.uuidString)/merch/gone.jpg")
        let orphanID = UUID()
        let orphan = MerchItem(showID: orphanID, relativePath: "\(orphanID.uuidString)/merch/x.jpg")
        [kept, missingFile, orphan].forEach(context.insert)
        try context.save()

        let valid = try reconcileMerchShowBoundary(in: context, existingRelativePaths: [photo, cutout, "\(orphanID.uuidString)/merch/x.jpg"])
        XCTAssertEqual(valid, [photo, cutout])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MerchItem>()).map(\.id), [kept.id])
    }
}
