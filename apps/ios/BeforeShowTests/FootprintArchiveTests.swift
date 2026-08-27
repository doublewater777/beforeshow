import SwiftData
import SwiftUI
import UIKit
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

    func testArchiveGroupsShowsByVenueLocalYear() throws {
        var venueCalendar = Calendar(identifier: .gregorian)
        venueCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        let show = try Show(
            name: "洛杉矶跨年现场",
            date: venueCalendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!,
            startTime: venueCalendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 20))!,
            endTime: venueCalendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23))!,
            timeZoneSecondsFromGMT: -8 * 3_600,
            city: "Los Angeles",
            venueName: "跨年场馆"
        )
        show.markEnded(at: venueCalendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 1))!)

        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2027, 1, 2, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.years.map(\.year), [2026])
        XCTAssertEqual(archive.years.first?.shows.map(\.name), ["洛杉矶跨年现场"])
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
        XCTAssertEqual(identity.companions.map(\.name), ["林嘉"])
    }

    func testDetailIdentityListsEachCompanionWithoutASingleGroupOrdinal() throws {
        let withJia = try makeShow("只和林嘉", year: 2024, artist: "A", city: "上海", venue: "A")
        try withJia.markCompanionInvitationSent(name: "林嘉")
        try withJia.markCompanionConfirmed(name: withJia.companionName)
        withJia.markEnded(at: date(2024, 6, 1, 22))

        let group = try makeShow("林嘉和王宁", year: 2025, artist: "B", city: "上海", venue: "B")
        try group.markCompanionInvitationSent(name: nil)
        group.applyCompanionState(status: .pending, names: ["林嘉", "王宁"])
        group.applyCompanionState(status: .confirmed, names: ["林嘉", "王宁"])
        group.markEnded(at: date(2025, 6, 1, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [group, withJia],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )
        let identity = FootprintDetailIdentityBuilder.make(
            show: group,
            archive: archive,
            calendar: calendar
        )

        XCTAssertEqual(
            identity.companions,
            [
                FootprintCompanionIdentity(name: "林嘉", ordinal: 2),
                FootprintCompanionIdentity(name: "王宁", ordinal: 1)
            ]
        )
        XCTAssertEqual(identity.companionName, "林嘉、王宁")
        XCTAssertNil(identity.companionOrdinal)
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

    func testExportPolicyCapsTimelineYearGroupsAndReportsRemaining() {
        XCTAssertEqual(FootprintExportContentPolicy.timelineShowLimit, 12)
        XCTAssertEqual(FootprintExportContentPolicy.memoryCardLimit, 4)
        XCTAssertEqual(FootprintExportContentPolicy.remainingCount(total: 20, limit: 12), 8)
        XCTAssertNil(FootprintExportContentPolicy.remainingText(total: 4, limit: 12, style: .shows))
        XCTAssertEqual(
            FootprintExportContentPolicy.remainingText(total: 20, limit: 12, style: .shows),
            "还有 8 场现场"
        )
        XCTAssertEqual(
            FootprintExportContentPolicy.remainingText(total: 16, limit: 4, style: .memories),
            "还有 12 个画面"
        )
    }

    func testExportPolicyKeepsNewestShowsWhenCappingYearGroups() throws {
        let newer = try makeShow("新", year: 2026, artist: "A", city: "上海", venue: "MAO")
        let older = try makeShow("旧", year: 2025, artist: "A", city: "上海", venue: "MAO")
        let mid = try makeShow("中", year: 2026, artist: "A", city: "杭州", venue: "MAO")
        let years = [
            FootprintYearGroup(year: 2026, shows: [newer, mid]),
            FootprintYearGroup(year: 2025, shows: [older])
        ]
        let capped = FootprintExportContentPolicy.cappedYearGroups(years, limit: 2)
        XCTAssertEqual(capped.map(\.year), [2026])
        XCTAssertEqual(capped.first?.shows.map(\.name), ["新", "中"])
        XCTAssertEqual(FootprintExportContentPolicy.remainingCount(total: 3, limit: 2), 1)
    }

    func testDetailShareRouteFallsBackToDispersalCardWhenNoMaterials() {
        XCTAssertEqual(
            FootprintDetailShareRoute.resolve(hasShareMaterials: true, rating: 5, note: "顶"),
            .composer
        )
        XCTAssertEqual(
            FootprintDetailShareRoute.resolve(hasShareMaterials: false, rating: 5, note: nil),
            .dispersalCard
        )
        XCTAssertEqual(
            FootprintDetailShareRoute.resolve(hasShareMaterials: false, rating: nil, note: "灯亮得很慢"),
            .dispersalCard
        )
        XCTAssertEqual(
            FootprintDetailShareRoute.resolve(hasShareMaterials: false, rating: nil, note: "   "),
            .none
        )
    }

    func testMemoryShareIdentitiesPreferCompanionAndCapAtTwo() {
        let withCompanion = FootprintDetailIdentity(
            showOrdinal: 12,
            cityOrdinal: 3,
            companions: [FootprintCompanionIdentity(name: "林嘉", ordinal: 2)]
        )
        XCTAssertEqual(
            FootprintMemoryShareCopy.identities(from: withCompanion),
            ["第 12 场现场", "与林嘉第 2 次见面"]
        )

        let withGroup = FootprintDetailIdentity(
            showOrdinal: 12,
            cityOrdinal: 3,
            companions: [
                FootprintCompanionIdentity(name: "林嘉", ordinal: 2),
                FootprintCompanionIdentity(name: "王宁", ordinal: 1)
            ]
        )
        XCTAssertEqual(
            FootprintMemoryShareCopy.identities(from: withGroup),
            ["第 12 场现场", "与林嘉、王宁同行"]
        )

        let solo = FootprintDetailIdentity(showOrdinal: 4, cityOrdinal: 2, companions: [])
        XCTAssertEqual(
            FootprintMemoryShareCopy.identities(from: solo),
            ["第 4 场现场", "城市第 2 场"]
        )
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

    func testArchiveCategoryShareCardIsShorterThanOverviewWhenRankingIsSparse() throws {
        let show = try makeShow("一场", year: 2025, artist: "陈绮贞", city: "杭州", venue: "MAO")
        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        guard let overview = FootprintShareImageExport.renderLong(
            FootprintArchiveShareCard(archive: archive, category: .overview),
            width: FootprintArchiveShareExportLayout.width,
            scale: 3
        )?.cgImage,
              let artist = FootprintShareImageExport.renderLong(
                FootprintArchiveShareCard(archive: archive, category: .artist),
                width: FootprintArchiveShareExportLayout.width,
                scale: 3
              )?.cgImage else {
            XCTFail("archive share card export produced no image")
            return
        }

        XCTAssertEqual(overview.width, 1080)
        XCTAssertEqual(artist.width, 1080)
        XCTAssertLessThan(artist.height, overview.height)
    }

    func testArchiveCardExportFillsGeometryReaderAtExportSize() {
        let size = FootprintArchiveShareExportLayout.size
        let probe = GeometryReader { geometry in
            Color.white.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)

        guard let image = FootprintShareImageExport.render(probe, size: size, scale: 3),
              let cgImage = image.cgImage else {
            XCTFail("archive card export produced no image")
            return
        }

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1100)
        XCTAssertEqual(luminance(atX: 540, y: 550, in: cgImage), 255)
        XCTAssertEqual(luminance(atX: 2, y: 2, in: cgImage), 255)
        XCTAssertEqual(luminance(atX: 1077, y: 1097, in: cgImage), 255)
    }

    func testLongShareExportUsesIntegerRetinaScale() {
        XCTAssertEqual(FootprintDashboardExportView.exportScale, 3)
        XCTAssertEqual(
            Int(FootprintDashboardExportView.layoutWidth * FootprintDashboardExportView.exportScale),
            1260
        )
    }

    func testPageSharePreviewShrinksForShortImagesAndCapsLongImages() {
        XCTAssertEqual(FootprintPageSharePreviewLayout.height(for: nil), 368)
        XCTAssertEqual(FootprintPageSharePreviewLayout.height(for: 241.2), 242)
        XCTAssertEqual(FootprintPageSharePreviewLayout.height(for: 640), 368)
        XCTAssertEqual(FootprintPageSharePreviewLayout.sheetHeight(for: 241.2), 390)
        XCTAssertEqual(FootprintPageSharePreviewLayout.sheetHeight(for: 640), 516)
    }

    func testLongShareExportRejectsStitchedBitmapBeyondMemoryBudget() {
        // 420pt × 3x = 1260px 宽,预算 50M px ≈ 高度上限约 13_227pt。
        XCTAssertTrue(FootprintShareImageExport.fitsStitchedMemoryBudget(width: 420, height: 5_000, scale: 3))
        XCTAssertTrue(FootprintShareImageExport.fitsStitchedMemoryBudget(width: 420, height: 13_000, scale: 3))
        XCTAssertFalse(FootprintShareImageExport.fitsStitchedMemoryBudget(width: 420, height: 20_000, scale: 3))
        XCTAssertFalse(FootprintShareImageExport.fitsStitchedMemoryBudget(width: 420, height: 100_000, scale: 3))
        XCTAssertFalse(FootprintShareImageExport.fitsStitchedMemoryBudget(width: 0, height: 100, scale: 3))
    }

    func testLongShareExportKeepsTileBoundarySharpAndOpaque() {
        let content = VStack(spacing: 0) {
            Color.black.frame(height: 2_333)
            Color.white.frame(height: 1)
            Color.black.frame(height: 100)
        }
        .frame(width: 20)

        guard let image = FootprintShareImageExport.renderLong(content, width: 20, scale: 3),
              let cgImage = image.cgImage,
              let pixels = rgbaBytes(in: cgImage) else {
            XCTFail("long share export produced no readable image")
            return
        }

        XCTAssertEqual(cgImage.width, 60)
        XCTAssertEqual(cgImage.height, 7_302)

        let x = cgImage.width / 2
        var whiteRows = 0
        var intermediateRows = 0
        var transparentRows = 0
        var firstWhiteRow: Int?
        for y in 0..<cgImage.height {
            let offset = (y * cgImage.width + x) * 4
            let red = pixels[offset]
            let alpha = pixels[offset + 3]
            if red == 255 {
                if firstWhiteRow == nil { firstWhiteRow = y }
                whiteRows += 1
            } else if red != 0 {
                intermediateRows += 1
            }
            if alpha != 255 {
                transparentRows += 1
            }
        }

        // The 1pt white line starts exactly at the 2333pt tile seam, so its
        // 3px must begin at pixel 2333*3: tile boundaries stay pixel-aligned.
        XCTAssertEqual(whiteRows, 3)
        XCTAssertEqual(firstWhiteRow, 6_999)
        XCTAssertEqual(intermediateRows, 0)
        XCTAssertEqual(transparentRows, 0)
    }

    private func luminance(atX x: Int, y: Int, in image: CGImage) -> UInt8 {
        precondition(x >= 0 && y >= 0 && x < image.width && y < image.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return pixel[0]
    }

    private func rgbaBytes(in image: CGImage) -> [UInt8]? {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func makeShow(
        _ name: String,
        year: Int,
        artist: String,
        city: String,
        venue: String
    ) throws -> Show {
        // 测试 fixture 允许写 `"落日飞车、陈绮贞"`,内部分隔符后用 slot 数组。
        let slots = artist
            .components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ArtistSlot(name: $0, avatarURL: nil) }
        return try Show(
            name: name,
            date: date(year, 6, 1),
            startTime: date(year, 6, 1, 19),
            endTime: date(year, 6, 1, 22),
            city: city,
            venueName: venue,
            artists: slots
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

/// 新增 UI 文案必须在三套语言(en / zh-Hans / zh-Hant)都有条目,
/// 否则非中文用户会看到 source key(中文原文)直接上屏。
final class LocalizableCompletenessTests: XCTestCase {
    private let requiredKeys = [
        "回忆",
        "留念",
        "归档",
        "场回忆",
        "照片",
        "视频",
        "暂无回忆",
        "照片和视频都留在对应的那一晚里。这里按时间把它们重新铺开。",
        "散场后留下照片或视频记忆，在这里筑造你的现场回忆。",
        "记录最完整的一晚",
        "weatherReminderLegalTitle",
        "ICP备案号",
        "法律信息"
    ]

    func testRequiredKeysExistInEveryLocalization() {
        for localization in ["en", "zh-Hans", "zh-Hant"] {
            let table = strings(localization)
            for key in requiredKeys {
                XCTAssertNotNil(table?[key], "\(localization).lproj 缺少 key: \(key)")
            }
        }
    }

    private func strings(_ localization: String) -> [String: String]? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BeforeShow/Resources/\(localization).lproj/Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }
}
