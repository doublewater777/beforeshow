import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class MemoryMomentTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, MemoryFragment.self, MemoryMediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func photo(_ fragment: MemoryFragment, _ name: String) throws -> MemoryMediaItem {
        let item = MemoryMediaItem(
            id: UUID(), kind: .photo, relativePath: "\(fragment.showID.uuidString)/\(name).jpg",
            thumbnailRelativePath: nil, contentTypeIdentifier: "public.jpeg", videoDuration: nil, sortOrder: 0
        )
        try fragment.appendMedia(item)
        return item
    }

    func testLegacyGroupsFlattenIntoMomentsInTimeOrder() throws {
        let showID = UUID()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let group = try MemoryFragment(showID: showID, text: "整组的一句", createdAt: start.addingTimeInterval(600))
        let first = try photo(group, "a")
        let second = try photo(group, "b")
        let line = try MemoryFragment(showID: showID, text: "开场了", createdAt: start)

        let moments = MemoryMomentTimeline.moments(from: [group, line])

        XCTAssertEqual(moments.map(\.id), [line.id, first.id, second.id])
        XCTAssertTrue(moments[0].isText)
        XCTAssertEqual(moments[1].caption, "整组的一句")
        XCTAssertNil(moments[2].caption)
    }

    func testDensitySpreadsMomentsAcrossTheEvening() throws {
        let showID = UUID()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let fragments = try [0, 60, 120, 3_600].map { try MemoryFragment(showID: showID, text: "x", createdAt: start.addingTimeInterval(TimeInterval($0))) }

        let counts = MemoryMomentTimeline.density(MemoryMomentTimeline.moments(from: fragments), buckets: 4)

        XCTAssertEqual(counts, [3, 0, 0, 1])
        XCTAssertEqual(MemoryMomentTimeline.density([], buckets: 4), [])
    }

    func testCaptureDateIsTrustedOnlyNearTheShow() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let now = start.addingTimeInterval(86_400)
        XCTAssertEqual(MemoryCaptureDate.accepted(start.addingTimeInterval(3_600), showStart: start, now: now), start.addingTimeInterval(3_600))
        XCTAssertNil(MemoryCaptureDate.accepted(start.addingTimeInterval(-10 * 86_400), showStart: start, now: now))
        XCTAssertNil(MemoryCaptureDate.accepted(now.addingTimeInterval(60), showStart: start, now: now))
        XCTAssertNil(MemoryCaptureDate.accepted(nil, showStart: start, now: now))
    }

    func testExifDateHonoursRecordedOffset() {
        let withOffset = MemoryCaptureDate.exifDate("2026:11:06 21:30:00", offset: "+08:00")
        XCTAssertEqual(withOffset, ISO8601DateFormatter().date(from: "2026-11-06T13:30:00Z"))
    }

    func testDeletingOnePhotoOfAGroupKeepsTheRest() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "现场", date: start, startTime: start)
        context.insert(show)
        let group = try MemoryFragment(showID: show.id, text: "一句", createdAt: start)
        group.show = show
        let first = try photo(group, "a")
        let second = try photo(group, "b")
        context.insert(group)
        try context.save()

        let moments = MemoryMomentTimeline.moments(from: [group])
        try await MemoryMomentEditing.delete(moments[0], in: context)

        XCTAssertEqual(group.orderedMediaItems.map(\.id), [second.id])
        XCTAssertFalse(group.mediaItems.contains { $0.id == first.id })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryFragment>()), 1)

        try await MemoryMomentEditing.delete(MemoryMomentTimeline.moments(from: [group])[0], in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryFragment>()), 0)
    }

    func testCaptionCanBeClearedOnAPhotoButNotOnALine() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let showID = UUID()
        let photoFragment = try MemoryFragment(showID: showID, text: "旧的一句")
        _ = try photo(photoFragment, "a")
        let line = try MemoryFragment(showID: showID, text: "只有字")
        context.insert(photoFragment)
        context.insert(line)
        try context.save()

        let moments = MemoryMomentTimeline.moments(from: [photoFragment, line])
        try MemoryMomentEditing.setCaption("", on: moments.first { !$0.isText }!, in: context)
        XCTAssertNil(photoFragment.text)
        XCTAssertThrowsError(try MemoryMomentEditing.setCaption("", on: moments.first(where: \.isText)!, in: context))
        XCTAssertEqual(line.text, "只有字")
    }

    func testBeforeShowRangeEndsAtStartWithoutInventingABeginning() throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "Club", date: start, startTime: start)
        let clock = BSDateFormat.clock(start, timeZone: show.timingFields.eventCalendar(fallback: .current).timeZone)
        XCTAssertEqual(MemoryRollTimeRange.rangeText(for: .before, timing: show.timingFields, moments: []), "– \(clock)")
    }
}
