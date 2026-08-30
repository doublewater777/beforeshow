import XCTest
import SwiftData
@testable import BeforeShow

@MainActor
final class FootprintArchiveEnhancementTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testMapZoomClampsPinchScaleToMapBounds() {
        XCTAssertEqual(FootprintMapZoom.settledScale(current: 1, gesture: 1.4), 1.4, accuracy: 0.001)
        XCTAssertEqual(FootprintMapZoom.settledScale(current: 1.6, gesture: 1.4), 1.7, accuracy: 0.001)
        XCTAssertEqual(FootprintMapZoom.settledScale(current: 1.1, gesture: 0.5), 1, accuracy: 0.001)
    }

    func testYearActivityProvidesAllMonthsAndAccumulatesDuration() throws {
        let first = try makeShow("一月现场", year: 2026, month: 1, durationHours: 2)
        let second = try makeShow("三月现场", year: 2026, month: 3, durationHours: 3)
        first.markEnded(at: date(2026, 1, 10, 22))
        second.markEnded(at: date(2026, 3, 10, 23))

        let archive = FootprintArchiveBuilder.make(
            shows: [first, second],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        let activity = try XCTUnwrap(archive.yearActivity(for: 2026))

        XCTAssertEqual(activity.months.count, 12)
        XCTAssertEqual(activity.months.map(\.month), Array(1...12))
        XCTAssertEqual(activity.months[0].showCount, 1)
        XCTAssertEqual(activity.months[2].showCount, 1)
        XCTAssertEqual(activity.months[1].showCount, 0)
        XCTAssertEqual(activity.months[0].durationMinutes, 120)
        XCTAssertEqual(activity.months[2].durationMinutes, 180)
        XCTAssertEqual(activity.peakMonth?.month, 1)
        XCTAssertEqual(activity.peakMonth?.showCount, 1)
    }

    func testArchiveItemsExposeContextAndChronologicalShowIDs() throws {
        let latest = try makeShow("最近一场", year: 2026, month: 6, durationHours: 2, artist: "A", venue: "场馆一")
        let first = try makeShow("最早一场", year: 2024, month: 6, durationHours: 2, artist: "A", venue: "场馆二")
        latest.markEnded(at: date(2026, 6, 10, 22))
        first.markEnded(at: date(2024, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [latest, first],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        let artist = try XCTUnwrap(archive.artistArchiveItems.first)
        let city = try XCTUnwrap(archive.cityArchiveItems.first)
        let venue = try XCTUnwrap(archive.venueArchiveItems.first)

        XCTAssertEqual(artist.showIDs, [first.id, latest.id])
        XCTAssertEqual(artist.yearSpan, FootprintYearSpan(first: 2024, latest: 2026))
        XCTAssertEqual(city.venueCount, 2)
        XCTAssertEqual(venue.cities, ["上海"])
        XCTAssertTrue(venue.isRevisited == false)
    }

    func testArtistArchiveKeepsRecognizedArtworkURL() throws {
        let show = try makeShow(
            "有头像的现场",
            year: 2026,
            month: 6,
            durationHours: 2,
            artist: "陈奕迅",
            venue: "场馆"
        )
        show.artists = [ArtistSlot(name: "陈奕迅", avatarURL: "https://example.com/eason.jpg")]
        show.markEnded(at: date(2026, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(
            archive.artistArchiveItems.first?.artworkURL,
            URL(string: "https://example.com/eason.jpg")
        )
    }

    func testArtistArtworkPolicyPrefersAvatarAndSkipsAlbumResolution() {
        let avatar = URL(string: "https://example.com/avatar.jpg")!
        let persistedAlbum = URL(string: "https://example.com/persisted-album.jpg")!
        let resolvedAlbum = URL(string: "https://example.com/resolved-album.jpg")!

        XCTAssertEqual(
            FootprintArtistArtworkPolicy.displayURL(
                avatarURL: avatar,
                persistedAlbumURL: persistedAlbum,
                resolvedAlbumURL: resolvedAlbum
            ),
            avatar
        )
        XCTAssertFalse(
            FootprintArtistArtworkPolicy.shouldResolveAlbumArtwork(
                avatarURL: avatar,
                persistedAlbumURL: persistedAlbum
            )
        )
    }

    func testArtistArtworkPolicyFallsBackToPersistedThenResolvedAlbum() {
        let persistedAlbum = URL(string: "https://example.com/persisted-album.jpg")!
        let resolvedAlbum = URL(string: "https://example.com/resolved-album.jpg")!

        XCTAssertEqual(
            FootprintArtistArtworkPolicy.displayURL(
                avatarURL: nil,
                persistedAlbumURL: persistedAlbum,
                resolvedAlbumURL: resolvedAlbum
            ),
            persistedAlbum
        )
        XCTAssertFalse(
            FootprintArtistArtworkPolicy.shouldResolveAlbumArtwork(
                avatarURL: nil,
                persistedAlbumURL: persistedAlbum
            )
        )
        XCTAssertEqual(
            FootprintArtistArtworkPolicy.displayURL(
                avatarURL: nil,
                persistedAlbumURL: nil,
                resolvedAlbumURL: resolvedAlbum
            ),
            resolvedAlbum
        )
        XCTAssertTrue(
            FootprintArtistArtworkPolicy.shouldResolveAlbumArtwork(
                avatarURL: nil,
                persistedAlbumURL: nil
            )
        )
    }

    func testSameVenueNameInDifferentCitiesAreSeparateIdentities() throws {
        let beijing = try makeShow("北馆", year: 2026, month: 1, durationHours: 2, venue: "体育馆")
        let shanghai = try makeShow("南馆", year: 2026, month: 3, durationHours: 2, venue: "体育馆")
        beijing.city = "北京"
        shanghai.city = "上海"
        beijing.markEnded(at: date(2026, 1, 10, 22))
        shanghai.markEnded(at: date(2026, 3, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [beijing, shanghai],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.venueArchiveItems.count, 2)
        XCTAssertEqual(Set(archive.venueArchiveItems.map(\.id)).count, 2)
        XCTAssertEqual(archive.venues.count, 2)
        XCTAssertTrue(archive.venueArchiveItems.allSatisfy { $0.count == 1 && $0.isRevisited == false })
    }

    func testSamePhysicalVenueAcrossShowsIsOneRevisitedIdentity() throws {
        let first = try makeShow("第一场", year: 2025, month: 6, durationHours: 2, venue: "MAO")
        let second = try makeShow("第二场", year: 2026, month: 6, durationHours: 2, venue: "MAO")
        first.markEnded(at: date(2025, 6, 10, 22))
        second.markEnded(at: date(2026, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [first, second],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        let venue = try XCTUnwrap(archive.venueArchiveItems.first)
        XCTAssertEqual(archive.venueArchiveItems.count, 1)
        XCTAssertEqual(venue.count, 2)
        XCTAssertTrue(venue.isRevisited)
        XCTAssertEqual(venue.cities, ["上海"])
        XCTAssertEqual(archive.venues.count, archive.venueArchiveItems.count)
    }

    func testArtistArchiveUsesLaterPersistedAlbumArtworkWhenEarliestSlotIsNil() throws {
        let first = try makeShow("早场", year: 2024, month: 6, durationHours: 2, artist: "A")
        let later = try makeShow("晚场", year: 2026, month: 6, durationHours: 2, artist: "A")
        first.artists = [ArtistSlot(name: "A", avatarURL: nil, albumArtworkURL: nil)]
        later.artists = [ArtistSlot(name: "A", avatarURL: nil, albumArtworkURL: "https://example.com/later.jpg")]
        first.markEnded(at: date(2024, 6, 10, 22))
        later.markEnded(at: date(2026, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [later, first],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(
            archive.artistArchiveItems.first?.albumArtworkURL,
            URL(string: "https://example.com/later.jpg")
        )
    }

    func testAlbumArtworkWritebackPersistsOntoMatchingNilSlots() throws {
        let show = try makeShow("待写回", year: 2026, month: 6, durationHours: 2, artist: "陈奕迅")
        show.markEnded(at: date(2026, 6, 10, 22))
        let url = URL(string: "https://example.com/eason-album.jpg")!

        let changed = FootprintAlbumArtworkWriteback.persist(
            url,
            artistName: "陈奕迅",
            showIDs: [show.id],
            in: [show]
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(show.artists.first?.albumArtworkURL, url.absoluteString)
    }

    func testArtistArchiveBreaksCountTiesByLatestShow() throws {
        let earlier = try makeShow("早看", year: 2025, month: 1, durationHours: 2, artist: "回声")
        let later = try makeShow("晚看", year: 2026, month: 6, durationHours: 2, artist: "极光")
        earlier.markEnded(at: date(2025, 1, 10, 22))
        later.markEnded(at: date(2026, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [earlier, later],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.artistArchiveItems.map(\.name), ["极光", "回声"])
        // Hero / 分享 / seed card 都消费 archive.artists,必须跟档案页同源。
        XCTAssertEqual(archive.artists.first?.name, archive.artistArchiveItems.first?.name)
    }

    func testRankingCacheInvalidatesAfterArtistMutation() throws {
        let show = try makeShow("缓存现场", year: 2026, month: 6, durationHours: 2, artist: "旧艺人")
        show.markEnded(at: date(2026, 6, 10, 22))
        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.artistArchiveItems.map(\.name), ["旧艺人"])
        // Read twice first so the second read is definitely served from the cache.
        XCTAssertEqual(archive.artistArchiveItems.map(\.name), ["旧艺人"])

        show.artists = [ArtistSlot(name: "新艺人", avatarURL: nil)]

        XCTAssertEqual(
            archive.artistArchiveItems.map(\.name),
            ["新艺人"],
            "A cached ranking must invalidate when the underlying artist identity changes."
        )
    }

    func testArtistArchiveKeepsPersistedAlbumArtworkURL() throws {
        let show = try makeShow(
            "有专辑封面的现场",
            year: 2026,
            month: 6,
            durationHours: 2,
            artist: "陈奕迅",
            venue: "场馆"
        )
        show.artists = [ArtistSlot(name: "陈奕迅", avatarURL: nil, albumArtworkURL: "https://example.com/eason-album.jpg")]
        show.markEnded(at: date(2026, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(
            archive.artistArchiveItems.first?.albumArtworkURL,
            URL(string: "https://example.com/eason-album.jpg")
        )
    }

    func testCoordinateProjectorPreservesGeographicOrdering() {
        let cities = [
            FootprintCityCoordinate(name: "西南", latitude: 22, longitude: 104),
            FootprintCityCoordinate(name: "东北", latitude: 40, longitude: 122)
        ]

        let projected = FootprintCoordinateProjector.project(cities)

        XCTAssertLessThan(try! XCTUnwrap(projected["西南"]?.x), try! XCTUnwrap(projected["东北"]?.x))
        XCTAssertGreaterThan(try! XCTUnwrap(projected["西南"]?.y), try! XCTUnwrap(projected["东北"]?.y))
    }

    func testYearArchiveSummaryDerivesNewArtistsCitiesAndDuration() throws {
        let first = try makeShow("第一场", year: 2025, month: 12, durationHours: 2, artist: "旧艺人", venue: "场馆一")
        let second = try makeShow("年度现场", year: 2026, month: 2, durationHours: 3, artist: "新艺人", venue: "场馆二")
        let repeatArtist = try makeShow("再次相遇", year: 2026, month: 4, durationHours: 1, artist: "旧艺人", venue: "场馆一")
        for show in [first, second, repeatArtist] {
            show.markEnded(at: show.startTime.addingTimeInterval(3 * 60 * 60))
        }
        second.city = "杭州"
        repeatArtist.city = "上海"

        let archive = FootprintArchiveBuilder.make(
            shows: [first, second, repeatArtist],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(
            archive.yearArchiveSummary(for: 2026),
            FootprintYearArchiveSummary(year: 2026, showCount: 2, durationMinutes: 360)
        )
    }

    func testVisibilityEnablesTrendWithOneShow() throws {
        let show = try makeShow("唯一现场", year: 2026, month: 1, durationHours: 2)
        show.markEnded(at: date(2026, 1, 10, 22))
        let archive = FootprintArchiveBuilder.make(
            shows: [show],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertTrue(archive.visibility.isSeed)
        XCTAssertTrue(archive.visibility.showsTrend)
        XCTAssertFalse(archive.visibility.showsYearComparison)
    }

    func testCoverResolverPrefersOfficialCoverThenMemoryThenTicketThenArchive() throws {
        let memoryShow = try makeShow("有记忆", year: 2026, month: 1, durationHours: 2)
        let ticketShow = try makeShow("有票根", year: 2026, month: 2, durationHours: 2)
        let archiveShow = try makeShow("纯档案", year: 2026, month: 3, durationHours: 2)
        for show in [memoryShow, ticketShow, archiveShow] {
            show.markEnded(at: date(2026, 8, 1, 22))
        }
        archiveShow.coverImageURL = "https://example.com/cover.jpg"

        let fragment = try MemoryFragment(showID: memoryShow.id)
        try fragment.appendMedia(MemoryMediaItem(
            id: UUID(),
            kind: .photo,
            relativePath: "\(memoryShow.id.uuidString)/photo.jpg",
            thumbnailRelativePath: nil,
            contentTypeIdentifier: "public.jpeg",
            videoDuration: nil,
            sortOrder: 0
        ))
        let ticket = ShowAsset(
            showID: ticketShow.id,
            kind: .ticket,
            relativePath: "\(ticketShow.id.uuidString)/ticket/ticket.jpg"
        )

        let covers = FootprintCoverResolver.resolve(
            shows: [memoryShow, ticketShow, archiveShow],
            fragments: [fragment],
            assets: [ticket]
        )

        XCTAssertEqual(covers[memoryShow.id]?.badge, .memory)
        XCTAssertEqual(covers[ticketShow.id]?.badge, .keepsake)
        XCTAssertEqual(covers[archiveShow.id]?.badge, .archive)
        XCTAssertNotEqual(covers[memoryShow.id]?.ordinal, covers[archiveShow.id]?.ordinal)
        XCTAssertEqual(
            FootprintArchiveCoverLayout.variant(for: archiveShow.id),
            FootprintArchiveCoverLayout.variant(for: archiveShow.id)
        )
    }

    func testCoverResolverPrefersRemoteCoverOverDynamicCoverPoster() throws {
        let container = try makeCoverContainer()
        let show = try makeShow("动态封面", year: 2026, month: 4, durationHours: 2)
        show.coverImageURL = "https://example.com/cover.jpg"
        let posterPath = "\(show.id.uuidString)/video-poster.jpg"
        attachDynamicCover(to: show, posterRelativePath: posterPath, in: container)

        let covers = FootprintCoverResolver.resolve(shows: [show], fragments: [], assets: [])

        guard case let .remote(url) = covers[show.id]?.source else {
            return XCTFail("coverImageURL 应优先于动态封面海报")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com/cover.jpg")
        XCTAssertEqual(covers[show.id]?.badge, .archive)
    }

    func testCoverResolverUsesRemoteCoverWhenPosterMissing() throws {
        let container = try makeCoverContainer()
        let show = try makeShow("无海报", year: 2026, month: 5, durationHours: 2)
        show.coverImageURL = "https://example.com/cover.jpg"
        attachDynamicCover(to: show, posterRelativePath: nil, in: container)

        let covers = FootprintCoverResolver.resolve(shows: [show], fragments: [], assets: [])

        guard case let .remote(url) = covers[show.id]?.source else {
            return XCTFail("海报缺失时应落到 coverImageURL")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com/cover.jpg")
        XCTAssertEqual(covers[show.id]?.badge, .archive)
    }

    func testCoverResolverKeepsMemoryAndTicketAheadOfDynamicCover() throws {
        let container = try makeCoverContainer()
        let memoryShow = try makeShow("有记忆", year: 2026, month: 1, durationHours: 2)
        let ticketShow = try makeShow("有票根", year: 2026, month: 2, durationHours: 2)
        attachDynamicCover(
            to: memoryShow,
            posterRelativePath: "\(memoryShow.id.uuidString)/video-poster.jpg",
            in: container
        )
        attachDynamicCover(
            to: ticketShow,
            posterRelativePath: "\(ticketShow.id.uuidString)/video-poster.jpg",
            in: container
        )

        let fragment = try MemoryFragment(showID: memoryShow.id)
        try fragment.appendMedia(MemoryMediaItem(
            id: UUID(),
            kind: .photo,
            relativePath: "\(memoryShow.id.uuidString)/photo.jpg",
            thumbnailRelativePath: nil,
            contentTypeIdentifier: "public.jpeg",
            videoDuration: nil,
            sortOrder: 0
        ))
        let ticket = ShowAsset(
            showID: ticketShow.id,
            kind: .ticket,
            relativePath: "\(ticketShow.id.uuidString)/ticket/ticket.jpg"
        )

        let covers = FootprintCoverResolver.resolve(
            shows: [memoryShow, ticketShow],
            fragments: [fragment],
            assets: [ticket]
        )

        XCTAssertEqual(covers[memoryShow.id]?.badge, .memory)
        XCTAssertEqual(covers[ticketShow.id]?.badge, .keepsake)
    }

    func testCoverResolverMarksVideoMemoryFlagFromSourceMedia() throws {
        let videoShow = try makeShow("视频记忆", year: 2026, month: 1, durationHours: 2)
        let photoShow = try makeShow("照片记忆", year: 2026, month: 2, durationHours: 2)

        let videoFragment = try MemoryFragment(showID: videoShow.id)
        try videoFragment.appendMedia(MemoryMediaItem(
            id: UUID(),
            kind: .video,
            relativePath: "\(videoShow.id.uuidString)/video.mov",
            thumbnailRelativePath: nil,
            contentTypeIdentifier: "public.movie",
            videoDuration: 12,
            sortOrder: 0
        ))
        let photoFragment = try MemoryFragment(showID: photoShow.id)
        try photoFragment.appendMedia(MemoryMediaItem(
            id: UUID(),
            kind: .photo,
            relativePath: "\(photoShow.id.uuidString)/photo.jpg",
            thumbnailRelativePath: nil,
            contentTypeIdentifier: "public.jpeg",
            videoDuration: nil,
            sortOrder: 0
        ))

        let covers = FootprintCoverResolver.resolve(
            shows: [videoShow, photoShow],
            fragments: [videoFragment, photoFragment],
            assets: []
        )

        XCTAssertEqual(covers[videoShow.id]?.isVideoMemory, true)
        XCTAssertEqual(covers[photoShow.id]?.isVideoMemory, false)
    }

    func testVenueArchiveBreaksCountTiesByLatestShow() throws {
        let earlier = try makeShow("早场", year: 2025, month: 4, durationHours: 2, venue: "滇池草坪")
        let later = try makeShow("晚场", year: 2026, month: 6, durationHours: 2, venue: "奥体中心体育馆")
        earlier.city = "昆明"
        later.city = "南京"
        earlier.markEnded(at: date(2025, 4, 10, 22))
        later.markEnded(at: date(2026, 6, 10, 22))

        let archive = FootprintArchiveBuilder.make(
            shows: [earlier, later],
            now: date(2026, 8, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(archive.venueArchiveItems.map(\.name), ["奥体中心体育馆", "滇池草坪"])
    }

    func testVenueRankItemIDsKeepCityIdentity() {
        let shanghai = FootprintVenueArchiveItem(
            name: "体育馆",
            count: 1,
            cities: ["上海"],
            showIDs: [UUID()],
            latestShowDate: date(2026, 6, 10),
            yearSpan: FootprintYearSpan(first: 2026, latest: 2026)
        )
        let beijing = FootprintVenueArchiveItem(
            name: "体育馆",
            count: 1,
            cities: ["北京"],
            showIDs: [UUID()],
            latestShowDate: date(2026, 3, 10),
            yearSpan: FootprintYearSpan(first: 2026, latest: 2026)
        )

        XCTAssertEqual(shanghai.rankItem.name, beijing.rankItem.name)
        XCTAssertNotEqual(shanghai.rankItem.id, beijing.rankItem.id)
    }

    private func makeCoverContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private func attachDynamicCover(
        to show: Show,
        posterRelativePath: String?,
        in container: ModelContainer
    ) {
        let cover = DynamicCover(
            showID: show.id,
            relativePath: "\(show.id.uuidString)/video.mov",
            posterRelativePath: posterRelativePath,
            contentTypeIdentifier: "public.movie",
            videoDuration: 3
        )
        cover.show = show
        show.dynamicCover = cover
        container.mainContext.insert(show)
        container.mainContext.insert(cover)
    }

    private func makeShow(_ name: String, year: Int, month: Int, durationHours: Int, artist: String = "艺人", venue: String = "MAO") throws -> Show {
        try Show(
            name: name,
            date: date(year, month, 10),
            startTime: date(year, month, 10, 20),
            endTime: date(year, month, 10, 20 + durationHours),
            city: "上海",
            venueName: venue,
            artists: [ArtistSlot(name: artist, avatarURL: nil)]
        )
    }

    // MARK: - FootprintsPreparationFingerprint regression

    func testFingerprintChangesWhenFragmentTextIsEditedWithoutChangingCount() throws {
        let show = try makeShow("有碎片的现场", year: 2026, month: 5, durationHours: 2)
        let fragment = try MemoryFragment(showID: show.id, text: "原始文字")

        let before = FootprintsPreparationFingerprint.make(
            shows: [show],
            fragments: [fragment],
            assets: []
        )

        // Sleep 5ms so updatedAt is observably different.
        Thread.sleep(forTimeInterval: 0.005)
        try fragment.updateText("更新后文字")

        let after = FootprintsPreparationFingerprint.make(
            shows: [show],
            fragments: [fragment],
            assets: []
        )

        XCTAssertNotEqual(before, after, "Editing fragment text must change the fingerprint even though fragment count is unchanged.")
    }

    func testFingerprintChangesWhenAssetImageIsReplacedWithoutChangingCount() throws {
        let show = try makeShow("有票根的现场", year: 2026, month: 5, durationHours: 2)
        let asset = ShowAsset(
            showID: show.id,
            kind: .ticket,
            relativePath: "\(show.id.uuidString)/ticket/original.jpg"
        )

        let before = FootprintsPreparationFingerprint.make(
            shows: [show],
            fragments: [],
            assets: [asset]
        )

        // Sleep 5ms so updatedAt is observably different.
        Thread.sleep(forTimeInterval: 0.005)
        asset.replaceImage(relativePath: "\(show.id.uuidString)/ticket/dirty.jpg")

        let after = FootprintsPreparationFingerprint.make(
            shows: [show],
            fragments: [],
            assets: [asset]
        )

        XCTAssertNotEqual(before, after, "Replacing an asset image must change the fingerprint even though asset count is unchanged.")
    }

    func testFingerprintIsStableWhenNothingMeaningfulChanges() throws {
        let show = try makeShow("稳定现场", year: 2026, month: 5, durationHours: 2)
        let fragment = try MemoryFragment(showID: show.id, text: "静止")
        let asset = ShowAsset(
            showID: show.id,
            kind: .ticket,
            relativePath: "\(show.id.uuidString)/ticket/a.jpg"
        )

        let first = FootprintsPreparationFingerprint.make(
            shows: [show],
            fragments: [fragment],
            assets: [asset]
        )
        let second = FootprintsPreparationFingerprint.make(
            shows: [show],
            fragments: [fragment],
            assets: [asset]
        )

        XCTAssertEqual(first, second, "Same inputs must produce the same fingerprint, otherwise .task(id:) will re-run spuriously.")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
