import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintArchiveTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testEmptyStateHidesAddActionWhenThereIsACurrentShow() {
        let withCurrentShow = FootprintEmptyStateCopy.content(hasCurrentShow: true)
        let withoutCurrentShow = FootprintEmptyStateCopy.content(hasCurrentShow: false)

        XCTAssertNil(withCurrentShow.actionTitle)
        XCTAssertEqual(withoutCurrentShow.actionTitle, "添加第一场现场")
    }

    func testArchiveIncludesOnlyEndedScheduledShows() throws {
        let ended = try makeShow("已结束", year: 2025, artist: "落日飞车", city: "上海", venue: "MAO")
        let upcoming = try makeShow("未开始", year: 2027, artist: "陈绮贞", city: "杭州", venue: "奥体")
        let canceled = try makeShow("已取消", year: 2025, artist: "新裤子", city: "南京", venue: "奥体")
        canceled.markCanceled()

        let archive = FootprintArchiveBuilder.make(
            shows: [ended, upcoming, canceled],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.shows.map(\.name), ["已结束"])
        XCTAssertEqual(archive.artists, [FootprintRankItem(name: "落日飞车", count: 1)])
    }

    func testArchiveRanksArtistsCitiesVenuesAndSplitsFestivalLineup() throws {
        let first = try makeShow("第一场", year: 2024, artist: "落日飞车、陈绮贞", city: " 上海 ", venue: "MAO")
        let second = try makeShow("第二场", year: 2025, artist: "落日飞车", city: "上海", venue: "梅奔")

        let archive = FootprintArchiveBuilder.make(
            shows: [second, first],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.artists.first, FootprintRankItem(name: "落日飞车", count: 2))
        XCTAssertEqual(archive.cities, [FootprintRankItem(name: "上海", count: 2)])
        XCTAssertEqual(archive.venues.count, 2)
        XCTAssertEqual(archive.years.map(\.year), [2025, 2024])
        XCTAssertEqual(archive.firstShow?.name, "第一场")
    }

    func testArchiveIncludesACompletedDatedPostponement() throws {
        let postponed = try makeShow("延期后实际演出", year: 2024, artist: "落日飞车", city: "上海", venue: "MAO")
        postponed.markPostponed(newDate: date(2025, 7, 1))

        let archive = FootprintArchiveBuilder.make(
            shows: [postponed],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.shows.map(\.name), ["延期后实际演出"])
    }

    func testArtistRankingTreatsSlashAsPartOfTheNameAndDeduplicatesWithinOneShow() throws {
        let show = try makeShow("艺人拆分边界", year: 2024, artist: "AC/DC、A / B、A", city: "上海", venue: "MAO")
        show.markEnded(at: date(2024, 7, 2))

        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(Set(archive.artists), Set([
            FootprintRankItem(name: "A", count: 1),
            FootprintRankItem(name: "A / B", count: 1),
            FootprintRankItem(name: "AC/DC", count: 1)
        ]))
    }

    func testHistoricalBackfillPreservesCurrentSelectionAndNotificationFocus() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let future = try makeShow("未来现场", year: 2027, artist: "未来艺人", city: "上海", venue: "MAO")
        let selection = CurrentShowSelection(selectedShowID: future.id)
        let notificationState = NotificationSchedulingState(focusedShowID: future.id)
        context.insert(future)
        context.insert(selection)
        context.insert(notificationState)
        try context.save()

        let historical = try makeShow("补录现场", year: 2024, artist: "过去艺人", city: "北京", venue: "工体")
        XCTAssertNil(
            try AddShowPersistenceCoordinator.persist(
                historical,
                intent: .historicalBackfill,
                selections: [selection],
                notificationStates: [notificationState],
                in: context
            )
        )

        XCTAssertEqual(selection.selectedShowID, future.id)
        XCTAssertEqual(notificationState.focusedShowID, future.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 2)
    }

    func testHistoricalBackfillRejectsFutureShowsWithoutChangingFocus() throws {
        let container = try ModelContainer(
            for: Show.self, CurrentShowSelection.self, NotificationSchedulingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let current = try makeShow("当前现场", year: 2027, artist: "当前艺人", city: "上海", venue: "MAO")
        let selection = CurrentShowSelection(selectedShowID: current.id)
        let notificationState = NotificationSchedulingState(focusedShowID: current.id)
        context.insert(current)
        context.insert(selection)
        context.insert(notificationState)
        try context.save()

        let future = try makeShow("误填未来现场", year: 2027, artist: "未来艺人", city: "北京", venue: "工体")
        XCTAssertThrowsError(
            try AddShowPersistenceCoordinator.persist(
                future,
                intent: .historicalBackfill,
                selections: [selection],
                notificationStates: [notificationState],
                in: context
            )
        ) { error in
            XCTAssertEqual(
                error as? AddShowPersistenceError,
                .historicalBackfillRequiresCompletedShow
            )
        }

        XCTAssertEqual(selection.selectedShowID, current.id)
        XCTAssertEqual(notificationState.focusedShowID, current.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Show>()).count, 1)
    }

    func testArchiveShareCopyIsSpecificToEveryCategory() throws {
        let first = try makeShow("第一场", year: 2024, artist: "落日飞车、陈绮贞", city: "上海", venue: "MAO")
        let second = try makeShow("第二场", year: 2025, artist: "落日飞车", city: "杭州", venue: "奥体")
        let archive = FootprintArchiveBuilder.make(
            shows: [second, first],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        let overview = FootprintArchiveShareCopy.text(for: .overview, archive: archive)
        let artist = FootprintArchiveShareCopy.text(for: .artist, archive: archive)
        let city = FootprintArchiveShareCopy.text(for: .city, archive: archive)
        let venue = FootprintArchiveShareCopy.text(for: .venue, archive: archive)

        XCTAssertEqual(Set([overview, artist, city, venue]).count, 4)
        XCTAssertTrue(overview.contains("2 场现场"))
        XCTAssertTrue(artist.contains("艺人排行：落日飞车 2 场"))
        XCTAssertTrue(city.contains("城市排行："))
        XCTAssertTrue(city.contains("上海 1 场"))
        XCTAssertTrue(city.contains("杭州 1 场"))
        XCTAssertTrue(venue.contains("场馆排行："))
        XCTAssertTrue(venue.contains("MAO 1 场"))
        XCTAssertTrue(venue.contains("奥体 1 场"))
    }

    func testDetailIdentityDynamicallyRanksShowCityAndConfirmedCompanion() throws {
        let backfilled = try makeShow("更早补录", year: 2023, artist: "A", city: "杭州", venue: "A")
        let firstTogether = try makeShow("第一次同行", year: 2024, artist: "B", city: "上海", venue: "B")
        let target = try makeShow("目标现场", year: 2025, artist: "C", city: "上海", venue: "C")

        try firstTogether.markCompanionInvitationSent(name: " 林嘉 ")
        try firstTogether.markCompanionConfirmed(name: firstTogether.companionName)
        firstTogether.markEnded(at: date(2024, 6, 1, 22))
        try target.markCompanionInvitationSent(name: "林嘉")
        try target.markCompanionConfirmed(name: target.companionName)
        target.markEnded(at: date(2025, 6, 1, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [target, firstTogether, backfilled],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )
        let identity = FootprintDetailIdentityBuilder.make(
            show: target,
            archive: archive,
            calendar: calendar
        )

        XCTAssertEqual(identity.showOrdinal, 3)
        XCTAssertEqual(identity.cityOrdinal, 2)
        XCTAssertEqual(identity.companionOrdinal, 2)
        XCTAssertEqual(identity.companionName, "林嘉")
    }

    func testDetailIdentityHidesMissingCityAndUnnamedCompanion() throws {
        let target = try makeShow("缺失身份资料", year: 2025, artist: "A", city: " ", venue: "A")
        try target.markCompanionInvitationSent(name: " ")
        try target.markCompanionConfirmed(name: target.companionName)
        target.markEnded(at: date(2025, 6, 1, 22))
        let archive = FootprintArchiveBuilder.make(
            shows: [target],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        let identity = FootprintDetailIdentityBuilder.make(
            show: target,
            archive: archive,
            calendar: calendar
        )

        XCTAssertEqual(identity.showOrdinal, 1)
        XCTAssertNil(identity.cityOrdinal)
        XCTAssertNil(identity.companionName)
        XCTAssertNil(identity.companionOrdinal)
    }

    func testShareDefaultsPreferChronologicalPhotosOverVideosAndKeepsakes() {
        let video = UUID()
        let firstPhoto = UUID()
        let secondPhoto = UUID()
        let thirdPhoto = UUID()
        let ticket = UUID()
        let candidates = [
            FootprintShareCandidate(id: ticket, kind: .ticket, recordedAt: date(2025, 6, 1, 17)),
            FootprintShareCandidate(id: video, kind: .videoCover, recordedAt: date(2025, 6, 1, 18)),
            FootprintShareCandidate(id: secondPhoto, kind: .photo, recordedAt: date(2025, 6, 1, 20)),
            FootprintShareCandidate(id: thirdPhoto, kind: .photo, recordedAt: date(2025, 6, 1, 21)),
            FootprintShareCandidate(id: firstPhoto, kind: .photo, recordedAt: date(2025, 6, 1, 19))
        ]

        XCTAssertEqual(
            FootprintShareSelectionPolicy.defaultSelection(from: candidates),
            [firstPhoto, secondPhoto, thirdPhoto]
        )
    }

    func testShareDefaultsUseVideosOnlyAfterAvailablePhotos() {
        let photo = FootprintShareCandidate(id: UUID(), kind: .photo, recordedAt: date(2025, 6, 1, 20))
        let earlyVideo = FootprintShareCandidate(id: UUID(), kind: .videoCover, recordedAt: date(2025, 6, 1, 18))
        let lateVideo = FootprintShareCandidate(id: UUID(), kind: .videoCover, recordedAt: date(2025, 6, 1, 21))
        let ticket = FootprintShareCandidate(id: UUID(), kind: .ticket, recordedAt: date(2025, 6, 1, 17))

        XCTAssertEqual(
            FootprintShareSelectionPolicy.defaultSelection(
                from: [ticket, lateVideo, photo, earlyVideo]
            ),
            [photo.id, earlyVideo.id, lateVideo.id]
        )
    }

    func testShareSelectionRejectsAFourthMaterialAcrossAllKinds() {
        let selected = Set([UUID(), UUID(), UUID()])

        XCTAssertNil(
            FootprintShareSelectionPolicy.selectionByAdding(UUID(), to: selected)
        )
        XCTAssertEqual(selected.count, 3)
    }

    func testShareOutputOrdersMemoriesBeforeTicketAndTimetable() {
        let photo = FootprintShareCandidate(id: UUID(), kind: .photo, recordedAt: date(2026, 1, 2))
        let video = FootprintShareCandidate(id: UUID(), kind: .videoCover, recordedAt: date(2026, 1, 1))
        let ticket = FootprintShareCandidate(id: UUID(), kind: .ticket, recordedAt: date(2025, 1, 1))
        let timetable = FootprintShareCandidate(id: UUID(), kind: .timetable, recordedAt: date(2024, 1, 1))

        XCTAssertEqual(
            FootprintShareSelectionPolicy.outputOrder(
                selected: Set([photo.id, video.id, ticket.id, timetable.id]),
                from: [ticket, photo, timetable, video]
            ),
            [video.id, photo.id, ticket.id, timetable.id]
        )
    }

    func testShareMaterialBuilderFiltersTextAndMapsEveryShareableKind() {
        let imageURL = URL(fileURLWithPath: "/tmp/share-source.jpg")
        let kinds: [FootprintShareSourceKind] = [
            .text, .photo, .videoCover, .ticket, .timetable
        ]
        let sources = kinds.enumerated().map { index, kind in
            FootprintShareSource(
                id: UUID(),
                kind: kind,
                recordedAt: date(2026, 1, index + 1),
                imageURL: kind == .text ? nil : imageURL
            )
        }

        let materials = FootprintShareMaterialBuilder.make(from: sources)

        XCTAssertEqual(materials.map(\.kind), [.photo, .videoCover, .ticket, .timetable])
        XCTAssertEqual(materials.map(\.title), ["照片", "视频封面", "票根", "时刻表"])
        XCTAssertFalse(materials.contains { $0.id == sources[0].id })
    }

    func testAccessibilityLabelsDistinguishMemoryAndShareItems() {
        let memoryLabel = FootprintAccessibilityPolicy.memoryLabel(
            ordinal: 2,
            kind: "照片",
            recordedAt: date(2026, 8, 1, 20).addingTimeInterval(18 * 60),
            text: "舞台灯光亮起来了"
        )
        let shareLabel = FootprintAccessibilityPolicy.shareMaterialLabel(
            title: "照片",
            ordinal: 3,
            recordedAt: date(2026, 8, 1, 20).addingTimeInterval(18 * 60),
            isSelected: false
        )

        XCTAssertEqual(memoryLabel, "打开记忆碎片，第 2 条，照片，20:18，内容：舞台灯光亮起来了")
        XCTAssertEqual(shareLabel, "照片，第 3 项，20:18，未选择")
    }

    private func makeShow(
        _ name: String,
        year: Int,
        artist: String,
        city: String,
        venue: String
    ) throws -> Show {
        try Show(
            name: name,
            date: date(year, 6, 1),
            startTime: date(year, 6, 1, 19),
            endTime: date(year, 6, 1, 22),
            city: city,
            venueName: venue,
            artist: artist
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
