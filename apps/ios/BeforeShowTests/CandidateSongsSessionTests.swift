import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class CandidateSongsSessionTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testReplaceGeneratedPreservesUserAddedSongsAndRenumbers() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let oldGroup = try CandidateSongGroup(
            showID: show.id,
            uncertaintyNote: "旧组",
            isUserCurated: false
        )
        let generated = try CandidateSong(
            groupID: oldGroup.id,
            songName: "旧生成",
            artist: "A",
            order: 0,
            isUserAdded: false
        )
        let userSong = try CandidateSong(
            groupID: oldGroup.id,
            songName: "手加",
            artist: "用户",
            order: 1,
            isUserAdded: true
        )
        context.insert(oldGroup)
        context.insert(generated)
        context.insert(userSong)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.replaceGenerated(
            with: [
                CandidateSongInput(songName: "新歌1", artist: "艺人甲", confidence: .high),
                CandidateSongInput(songName: "新歌2", artist: "艺人甲", confidence: .mid)
            ],
            existingGroups: [oldGroup],
            existingSongs: [generated, userSong],
            artistInterests: [],
            in: context
        )

        let groups = try context.fetch(FetchDescriptor<CandidateSongGroup>())
        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
            .sorted { $0.order < $1.order }

        XCTAssertEqual(songs.map(\.songName), ["新歌1", "新歌2", "手加"])
        XCTAssertEqual(songs.map(\.isUserAdded), [false, false, true])
        XCTAssertEqual(songs.map(\.confidence), [.high, .mid, .mid])
        XCTAssertEqual(songs.map(\.order), [0, 1, 2])
        XCTAssertTrue(groups.contains(where: \.isUserCurated))
        XCTAssertFalse(groups.contains(where: { $0.id == oldGroup.id }))
    }

    func testReplaceGeneratedPreservesAllMostWantedSongsIncludingMissingFromNewList() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let oldGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let keptStar = try CandidateSong(
            groupID: oldGroup.id,
            songName: "保留星标",
            artist: "艺人甲",
            order: 0,
            isStarred: true,
            confidence: .high
        )
        let missingStar = try CandidateSong(
            groupID: oldGroup.id,
            songName: "失踪星标",
            artist: "艺人甲",
            order: 1,
            hint: "安可位的老熟人",
            isStarred: true,
            confidence: .mid
        )
        let plain = try CandidateSong(
            groupID: oldGroup.id,
            songName: "普通",
            artist: "艺人甲",
            order: 2
        )
        context.insert(oldGroup)
        context.insert(keptStar)
        context.insert(missingStar)
        context.insert(plain)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.replaceGenerated(
            with: [
                CandidateSongInput(songName: "保留星标", artist: "艺人甲", tier: .guest, hint: "给北京场的彩蛋"),
                CandidateSongInput(songName: "全新歌", artist: "艺人甲", tier: .mid)
            ],
            existingGroups: [oldGroup],
            existingSongs: [keptStar, missingStar, plain],
            artistInterests: [],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
            .sorted { $0.order < $1.order }

        XCTAssertEqual(songs.map(\.songName), ["保留星标", "全新歌", "失踪星标"])
        XCTAssertEqual(songs.map(\.isMostWanted), [true, false, true])
        XCTAssertEqual(songs.map(\.tier), [.guest, .mid, .mid])
        XCTAssertEqual(songs.map(\.hint), ["给北京场的彩蛋", nil, "安可位的老熟人"])
        XCTAssertTrue(songs.allSatisfy { !$0.isUserAdded })
    }

    func testReplaceGeneratedPreservesMostWantedOnUserAddedAndToggleDoesNotImplyUserAdded() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let oldGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let userStarred = try CandidateSong(
            groupID: oldGroup.id,
            songName: "手加星标",
            artist: "用户",
            order: 0,
            isUserAdded: true,
            isStarred: true
        )
        let generated = try CandidateSong(
            groupID: oldGroup.id,
            songName: "生成",
            artist: "A",
            order: 1,
            isStarred: false
        )
        generated.isStarred = true
        XCTAssertTrue(generated.isStarred)
        XCTAssertFalse(generated.isUserAdded)

        context.insert(oldGroup)
        context.insert(userStarred)
        context.insert(generated)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.replaceGenerated(
            with: [CandidateSongInput(songName: "新生成", artist: "A")],
            existingGroups: [oldGroup],
            existingSongs: [userStarred, generated],
            artistInterests: [],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
            .sorted { $0.order < $1.order }
        // missing starred "生成" re-inserted; user-added preserved with star
        XCTAssertEqual(songs.map(\.songName), ["新生成", "生成", "手加星标"])
        let user = try XCTUnwrap(songs.first { $0.songName == "手加星标" })
        XCTAssertTrue(user.isUserAdded)
        XCTAssertTrue(user.isMostWanted)
        let reinserted = try XCTUnwrap(songs.first { $0.songName == "生成" })
        XCTAssertFalse(reinserted.isUserAdded)
        XCTAssertTrue(reinserted.isMostWanted)
    }

    func testSetMostWantedAllowsMultipleSongsWithoutChangingUserAdded() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "仅供参考")
        let generated = try CandidateSong(groupID: group.id, songName: "生成", artist: "A", order: 0)
        let userAdded = try CandidateSong(
            groupID: group.id,
            songName: "手加",
            artist: "A",
            order: 1,
            isUserAdded: true
        )
        context.insert(group)
        context.insert(generated)
        context.insert(userAdded)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.setMostWanted(generated, isMostWanted: true, in: context)
        try session.setMostWanted(userAdded, isMostWanted: true, in: context)

        XCTAssertTrue(generated.isMostWanted)
        XCTAssertTrue(userAdded.isMostWanted)
        XCTAssertFalse(generated.isUserAdded)
        XCTAssertTrue(userAdded.isUserAdded)
    }

    func testAddRemoveAndMoveThroughSession() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let session = CandidateSongsSession(show: show)
        try session.addUserSong(
            name: "一",
            artist: "A",
            groups: [],
            currentSongs: [],
            in: context
        )
        var songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.count, 1)

        try session.addUserSong(
            name: "二",
            artist: "B",
            groups: try context.fetch(FetchDescriptor<CandidateSongGroup>()),
            currentSongs: songs,
            in: context
        )
        songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["一", "二"])

        try session.move(previouslyOrdered: songs, from: IndexSet(integer: 0), to: 2, in: context)
        songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["二", "一"])

        try session.moveDown(songs[0], previouslyOrdered: songs, in: context)
        songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["一", "二"])

        try session.moveUp(songs[1], previouslyOrdered: songs, in: context)
        songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["二", "一"])

        try session.remove(songs[0], previouslyOrdered: songs, in: context)
        songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["一"])
        XCTAssertEqual(songs[0].order, 0)
    }

    func testAddUserSongRejectsDuplicateSongArtistPair() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let session = CandidateSongsSession(show: show)
        try session.addUserSong(
            name: "晴天",
            artist: "周杰伦",
            groups: [],
            currentSongs: [],
            in: context
        )
        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }

        XCTAssertThrowsError(
            try session.addUserSong(
                name: " 晴天 ",
                artist: "周杰伦",
                groups: try context.fetch(FetchDescriptor<CandidateSongGroup>()),
                currentSongs: songs,
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? CandidateSongValidationError, .duplicateSong)
        }
    }

    func testFestivalAddSongInsertsIntoSelectedArtistGroup() throws {
        let show = try Show(
            name: "音乐节",
            date: DateComponents(calendar: calendar, year: 2026, month: 8, day: 1).date!,
            startTime: DateComponents(calendar: calendar, year: 2026, month: 8, day: 1, hour: 20).date!,
            artist: "甲、乙",
            type: .musicFestival
        )
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let groupA = try CandidateSongGroup(showID: show.id, artistName: "甲", uncertaintyNote: "猜想")
        let groupB = try CandidateSongGroup(showID: show.id, artistName: "乙", uncertaintyNote: "猜想")
        let firstA = try CandidateSong(groupID: groupA.id, songName: "甲一", artist: "甲", order: 0)
        let firstB = try CandidateSong(groupID: groupB.id, songName: "乙一", artist: "乙", order: 1)
        context.insert(groupA)
        context.insert(groupB)
        context.insert(firstA)
        context.insert(firstB)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.addUserSong(
            name: "甲手加",
            artist: "甲",
            groups: [groupA, groupB],
            currentSongs: [firstA, firstB],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["甲一", "甲手加", "乙一"])
        XCTAssertEqual(songs[1].groupID, groupA.id)
        XCTAssertTrue(songs[1].isUserAdded)
    }

    func testDeduplicateSongsKeepsUserAddedAndMostWantedState() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let generatedGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "生成")
        let userGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "手加", isUserCurated: true)
        let generated = try CandidateSong(
            groupID: generatedGroup.id,
            songName: "晴天",
            artist: "周杰伦",
            order: 0
        )
        let userAdded = try CandidateSong(
            groupID: userGroup.id,
            songName: "晴天",
            artist: " 周杰伦 ",
            order: 1,
            isUserAdded: true,
            isMostWanted: true
        )
        context.insert(generatedGroup)
        context.insert(userGroup)
        context.insert(generated)
        context.insert(userAdded)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.deduplicateSongs(
            songs: [generated, userAdded],
            groups: [generatedGroup, userGroup],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.count, 1)
        XCTAssertTrue(songs[0].isUserAdded)
        XCTAssertTrue(songs[0].isMostWanted)
        XCTAssertEqual(songs[0].order, 0)
    }

    func testDeduplicateSongsDoesNotDeleteAnotherShowsSongs() throws {
        let show = try makeShow()
        let otherShow = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)
        context.insert(otherShow)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "本场")
        let otherGroup = try CandidateSongGroup(showID: otherShow.id, uncertaintyNote: "另一场")
        let song = try CandidateSong(groupID: group.id, songName: "晴天", artist: "周杰伦", order: 0)
        let otherSong = try CandidateSong(
            groupID: otherGroup.id,
            songName: "晴天",
            artist: "周杰伦",
            order: 0
        )
        context.insert(group)
        context.insert(otherGroup)
        context.insert(song)
        context.insert(otherSong)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.deduplicateSongs(
            songs: [song, otherSong],
            groups: [group, otherGroup],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
        XCTAssertEqual(songs.count, 2)
        XCTAssertTrue(songs.contains { $0.groupID == group.id })
        XCTAssertTrue(songs.contains { $0.groupID == otherGroup.id })
    }

    func testDeduplicateSongsKeepsUserAddedDuplicateAtItsOriginalPosition() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "本场")
        let generated = try CandidateSong(groupID: group.id, songName: "重复歌", artist: "艺人", order: 0)
        let other = try CandidateSong(groupID: group.id, songName: "中间歌", artist: "艺人", order: 1)
        let userAdded = try CandidateSong(
            groupID: group.id,
            songName: "重复歌",
            artist: "艺人",
            order: 2,
            isUserAdded: true
        )
        context.insert(group)
        context.insert(generated)
        context.insert(other)
        context.insert(userAdded)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.deduplicateSongs(
            songs: [generated, other, userAdded],
            groups: [group],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["中间歌", "重复歌"])
        XCTAssertTrue(songs.last?.isUserAdded == true)
    }

    func testCopyTextUsesResolverStylePlaylistBody() throws {
        let show = try makeShow()
        let session = CandidateSongsSession(show: show)
        let groupID = UUID()
        let songs = [
            try CandidateSong(groupID: groupID, songName: "晴天", artist: "周杰伦", order: 0),
            try CandidateSong(groupID: groupID, songName: "七里香", artist: "周杰伦", order: 1)
        ]
        let text = session.copyText(headline: "演唱会", scope: "全部", songs: songs)
        XCTAssertTrue(text.contains("1. 晴天 - 周杰伦"))
        XCTAssertTrue(text.contains("2. 七里香 - 周杰伦"))
        XCTAssertTrue(text.contains("歌单猜想 · 全部（非官方）"))
        XCTAssertTrue(text.contains("非官方"))
        XCTAssertFalse(text.contains("官方 setlist"))
    }

    func testPlaylistBodyMarksMostWantedSongs() throws {
        let show = try makeShow()
        let session = CandidateSongsSession(show: show)
        let groupID = UUID()
        let wanted = try CandidateSong(
            groupID: groupID,
            songName: "晴天",
            artist: "周杰伦",
            order: 0,
            isMostWanted: true
        )
        let plain = try CandidateSong(groupID: groupID, songName: "七里香", artist: "周杰伦", order: 1)
        let body = session.playlistBody(for: [wanted, plain])
        XCTAssertTrue(body.contains("（最想看）"))
        XCTAssertTrue(body.contains("七里香"))
    }

    func testRepairLegacyTiersAndHintsFillsAllMidEmptyCatalog() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        context.insert(group)
        for index in 0..<6 {
            let song = try CandidateSong(
                groupID: group.id,
                songName: "歌\(index)",
                artist: "艺人",
                order: index,
                isUserAdded: false
            )
            context.insert(song)
        }
        let userAdded = try CandidateSong(
            groupID: group.id,
            songName: "手加",
            artist: "用户",
            order: 6,
            isUserAdded: true
        )
        context.insert(userAdded)
        try context.save()

        let session = CandidateSongsSession(show: show)
        let before = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        try session.repairLegacyTiersAndHintsIfNeeded(songs: before, in: context)

        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        let generated = songs.filter { !$0.isUserAdded }
        XCTAssertTrue(generated.contains { $0.tier == .high })
        XCTAssertTrue(generated.contains { $0.tier == .encore })
        XCTAssertTrue(generated.allSatisfy { ($0.hint?.isEmpty ?? true) == false })
        // User-added rows are left alone.
        XCTAssertEqual(songs.last?.songName, "手加")
        XCTAssertEqual(songs.last?.tier, .mid)
        XCTAssertNil(songs.last?.hint)
    }

    func testRepairLegacyTiersAndHintsSkipsWhenAlreadyEnriched() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let high = try CandidateSong(
            groupID: group.id,
            songName: "A",
            artist: "艺人",
            order: 0,
            tier: .high,
            hint: "这轮巡演主题曲"
        )
        let mid = try CandidateSong(
            groupID: group.id,
            songName: "B",
            artist: "艺人",
            order: 1,
            tier: .mid,
            hint: "近期巡演常演"
        )
        context.insert(group)
        context.insert(high)
        context.insert(mid)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.repairLegacyTiersAndHintsIfNeeded(songs: [high, mid], in: context)

        XCTAssertEqual(high.tier, .high)
        XCTAssertEqual(high.hint, "这轮巡演主题曲")
        XCTAssertEqual(mid.tier, .mid)
        XCTAssertEqual(mid.hint, "近期巡演常演")
    }

    func testParseLineupNamesSplitsCommonSeparators() {
        XCTAssertEqual(
            CandidateSongsSession.parseLineupNames(from: "薛之谦、毛不易，单依纯/陈粒"),
            ["薛之谦", "毛不易", "单依纯", "陈粒"]
        )
        // Damai / ShowStart join style
        XCTAssertEqual(
            CandidateSongsSession.parseLineupNames(from: "刘雨昕, 姚琛, 二手玫瑰, DOUDOU"),
            ["刘雨昕", "姚琛", "二手玫瑰", "DOUDOU"]
        )
        XCTAssertEqual(
            CandidateSongsSession.parseLineupNames(from: "A · B · C"),
            ["A", "B", "C"]
        )
        XCTAssertEqual(
            CandidateSongsSession.parseLineupNames(from: "The 1975"),
            ["The 1975"]
        )
        XCTAssertEqual(
            CandidateSongsSession.parseLineupNames(from: "  唯一  "),
            ["唯一"]
        )
        XCTAssertEqual(CandidateSongsSession.parseLineupNames(from: nil), [])
        XCTAssertEqual(CandidateSongsSession.parseLineupNames(from: "  "), [])
    }

    func testSeedFestivalInterestsFromShowArtist() throws {
        let show = try Show(
            name: "音乐节",
            date: DateComponents(calendar: calendar, year: 2026, month: 8, day: 1).date!,
            startTime: DateComponents(calendar: calendar, year: 2026, month: 8, day: 1, hour: 20).date!,
            artist: "A、B，C",
            type: .musicFestival
        )
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)
        try context.save()

        let session = CandidateSongsSession(show: show)
        let seeded = try session.seedFestivalInterestsIfNeeded(existing: [], in: context)
        XCTAssertEqual(seeded.map(\.artistName), ["A", "B", "C"])
        XCTAssertTrue(seeded.allSatisfy { $0.status == .wantToSee })
        XCTAssertTrue(seeded.allSatisfy { !$0.isHeadliner })

        // Second call is no-op when interests already exist.
        let again = try session.seedFestivalInterestsIfNeeded(existing: seeded, in: context)
        XCTAssertEqual(again.count, 3)
    }

    func testGenerateAndReplaceEnrichesLegacyGeneratorPayload() async throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)
        try context.save()

        let stub = StubCandidateSongGenerator(inputs: [
            CandidateSongInput(songName: "一", artist: "甲"),
            CandidateSongInput(songName: "二", artist: "甲"),
            CandidateSongInput(songName: "三", artist: "甲"),
            CandidateSongInput(songName: "四", artist: "甲"),
            CandidateSongInput(songName: "五", artist: "甲")
        ])
        let session = CandidateSongsSession(show: show, generationService: stub)
        try await session.generateAndReplace(
            artistInterests: [],
            existingGroups: [],
            existingSongs: [],
            in: context
        )

        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.count, 5)
        XCTAssertTrue(songs.contains { $0.tier == .high })
        XCTAssertEqual(songs.last?.tier, .encore)
        XCTAssertTrue(songs.allSatisfy { ($0.hint?.isEmpty ?? true) == false })
    }

    func testGenerateAndReplaceAppliesProgressiveSnapshotsOnlyOnFinalPersist() async throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)
        try context.save()

        let stub = ProgressiveStubCandidateSongGenerator(snapshots: [
            [CandidateSongInput(songName: "一", artist: "甲")],
            [
                CandidateSongInput(songName: "一", artist: "甲"),
                CandidateSongInput(songName: "二", artist: "乙")
            ],
            [
                CandidateSongInput(songName: "一", artist: "甲"),
                CandidateSongInput(songName: "二", artist: "乙"),
                CandidateSongInput(songName: "三", artist: "丙")
            ]
        ])
        let session = CandidateSongsSession(show: show, generationService: stub)
        var snapshotProgressiveCounts: [Int] = []
        var persistedDuringProgressive: [Int] = []
        try await session.generateAndReplace(
            artistInterests: [],
            existingGroups: [],
            existingSongs: [],
            in: context,
            onSnapshot: { progressive in
                snapshotProgressiveCounts.append(progressive.count)
                let count = (try? context.fetch(FetchDescriptor<CandidateSong>()).count) ?? 0
                persistedDuringProgressive.append(count)
            }
        )

        XCTAssertEqual(snapshotProgressiveCounts, [1, 2, 3])
        // Progressive rows are temporary UI only — not written until stream completes.
        XCTAssertEqual(persistedDuringProgressive, [0, 0, 0])
        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["一", "二", "三"])
    }

    func testGenerateAndReplaceThrowsOnPartialStreamFailureWithoutOverwritingCatalog() async throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let oldGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let oldSong = try CandidateSong(
            groupID: oldGroup.id,
            songName: "旧完整",
            artist: "甲",
            order: 0,
            tier: .high,
            hint: "近巡必唱"
        )
        let userSong = try CandidateSong(
            groupID: oldGroup.id,
            songName: "手加",
            artist: "用户",
            order: 1,
            isUserAdded: true,
            isMostWanted: true,
            tier: .mid
        )
        context.insert(oldGroup)
        context.insert(oldSong)
        context.insert(userSong)
        try context.save()

        let oldIDs = Set([oldSong.id, userSong.id])
        let failing = PartialThenFailGenerator(first: [
            CandidateSongInput(songName: "残缺一首", artist: "乙", tier: .mid)
        ])
        let session = CandidateSongsSession(show: show, generationService: failing)

        do {
            try await session.generateAndReplace(
                artistInterests: [],
                existingGroups: [oldGroup],
                existingSongs: [oldSong, userSong],
                in: context
            )
            XCTFail("expected partial stream failure to throw")
        } catch {
            XCTAssertEqual(error as? CandidateSongGenerationError, .invalidResponse)
        }

        let songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["旧完整", "手加"])
        XCTAssertEqual(songs.map(\.id), [oldSong.id, userSong.id])
        XCTAssertEqual(songs.map(\.tier), [.high, .mid])
        XCTAssertEqual(songs.map(\.hint), ["近巡必唱", nil])
        XCTAssertEqual(songs.map(\.isMostWanted), [false, true])
        XCTAssertEqual(songs.map(\.isUserAdded), [false, true])
        XCTAssertEqual(Set(songs.map(\.id)), oldIDs)
        XCTAssertFalse(songs.contains { $0.songName == "残缺一首" })
    }

    func testGenerateAndReplaceRejectsCleanlyFinishedProgressWithoutFinal() async throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let oldGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let oldSong = try CandidateSong(
            groupID: oldGroup.id,
            songName: "旧完整",
            artist: "甲",
            order: 0,
            tier: .high,
            hint: "近巡必唱"
        )
        context.insert(oldGroup)
        context.insert(oldSong)
        try context.save()

        let session = CandidateSongsSession(
            show: show,
            generationService: ProgressThenFinishGenerator(progress: [
                CandidateSongInput(songName: "残缺一首", artist: "乙")
            ])
        )

        do {
            try await session.generateAndReplace(
                artistInterests: [],
                existingGroups: [oldGroup],
                existingSongs: [oldSong],
                in: context
            )
            XCTFail("expected missing final snapshot to fail")
        } catch {
            XCTAssertEqual(error as? CandidateSongGenerationError, .invalidResponse)
        }

        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
        XCTAssertEqual(songs.map(\.id), [oldSong.id])
        XCTAssertFalse(songs.contains { $0.songName == "残缺一首" })
    }

    func testGenerateAndReplaceCancellationDoesNotWriteOrReplaceCatalog() async throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let oldGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let oldSong = try CandidateSong(
            groupID: oldGroup.id,
            songName: "保留",
            artist: "甲",
            order: 0,
            tier: .encore,
            hint: "安可位常客"
        )
        context.insert(oldGroup)
        context.insert(oldSong)
        try context.save()

        let gate = CancellableGeneratorGate()
        let cancellable = CancellableStubCandidateSongGenerator(
            gate: gate,
            final: [CandidateSongInput(songName: "新歌", artist: "甲", tier: .high, hint: "主题曲")]
        )
        let session = CandidateSongsSession(show: show, generationService: cancellable)

        let task = Task { @MainActor in
            try await session.generateAndReplace(
                artistInterests: [],
                existingGroups: [oldGroup],
                existingSongs: [oldSong],
                in: context
            )
        }

        await gate.waitUntilStarted()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        // Give the producer a beat to observe cancel via onTermination.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(gate.observedCancellation)
        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].songName, "保留")
        XCTAssertEqual(songs[0].id, oldSong.id)
        XCTAssertEqual(songs[0].tier, .encore)
        XCTAssertFalse(songs.contains { $0.songName == "新歌" })
    }

    func testRepairLegacyTiersAndHintsFillsSingleGeneratedMidWithoutHint() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组")
        let only = try CandidateSong(
            groupID: group.id,
            songName: "唯一生成",
            artist: "艺人",
            order: 0,
            isUserAdded: false
        )
        XCTAssertEqual(only.tier, .mid)
        XCTAssertNil(only.hint)
        context.insert(group)
        context.insert(only)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.repairLegacyTiersAndHintsIfNeeded(songs: [only], in: context)

        XCTAssertEqual(only.tier, .high)
        XCTAssertFalse(only.hint?.isEmpty ?? true)
    }

    func testRepairLegacyTiersAndHintsNoOpsOnEmptyList() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.repairLegacyTiersAndHintsIfNeeded(songs: [], in: context)
        let songs = try context.fetch(FetchDescriptor<CandidateSong>())
        XCTAssertTrue(songs.isEmpty)
    }

    func testRepairLegacyTiersAndHintsDoesNotTouchUserAddedOnlyCatalog() throws {
        let show = try makeShow()
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)

        let group = try CandidateSongGroup(showID: show.id, uncertaintyNote: "旧组", isUserCurated: true)
        let user = try CandidateSong(
            groupID: group.id,
            songName: "手加",
            artist: "用户",
            order: 0,
            isUserAdded: true
        )
        context.insert(group)
        context.insert(user)
        try context.save()

        let session = CandidateSongsSession(show: show)
        try session.repairLegacyTiersAndHintsIfNeeded(songs: [user], in: context)

        XCTAssertEqual(user.tier, .mid)
        XCTAssertNil(user.hint)
    }

    func testDefaultLineupPickSelectionRespectsNotInterested() throws {
        let showID = UUID()
        let want = try ArtistInterestItem(showID: showID, artistName: "想看", status: .wantToSee, order: 0)
        let undecided = try ArtistInterestItem(showID: showID, artistName: "待定", status: .undecided, order: 1)
        let no = try ArtistInterestItem(showID: showID, artistName: "不看", status: .notInterested, order: 2)

        let selection = CandidateSongsSession.defaultLineupPickSelection(
            interests: [want, undecided, no]
        )
        XCTAssertEqual(selection, Set([want.id, undecided.id]))
        XCTAssertFalse(selection.contains(no.id))
    }

    func testDefaultLineupPickSelectionSelectsAllNewSeedWantToSee() throws {
        let showID = UUID()
        let a = try ArtistInterestItem(showID: showID, artistName: "A", status: .wantToSee, order: 0)
        let b = try ArtistInterestItem(showID: showID, artistName: "B", status: .wantToSee, order: 1)
        let selection = CandidateSongsSession.defaultLineupPickSelection(interests: [a, b])
        XCTAssertEqual(selection, Set([a.id, b.id]))
    }

    func testDefaultLineupPickSelectionEmptyWhenAllNotInterested() throws {
        let showID = UUID()
        let no = try ArtistInterestItem(showID: showID, artistName: "不看", status: .notInterested, order: 0)
        let selection = CandidateSongsSession.defaultLineupPickSelection(interests: [no])
        XCTAssertTrue(selection.isEmpty)
    }

    func testFestivalArtistDraftIsNotPersistedUntilCallerConfirms() throws {
        let show = try Show(
            name: "音乐节",
            date: Date(),
            startTime: Date(),
            type: .musicFestival
        )
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(show)
        try context.save()

        let session = CandidateSongsSession(show: show)
        let draft = try session.makeFestivalArtistDraft(name: "新艺人", existing: [])

        XCTAssertEqual(draft.artistName, "新艺人")
        XCTAssertEqual(draft.status, .wantToSee)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ArtistInterestItem>()).isEmpty)
    }

    func testDropDestinationIndexMovesDownAndUpCorrectly() {
        // [A,B,C,D]: A→C → destination after C so result [B,C,A,D]
        XCTAssertEqual(
            CandidateSongEditingService.dropDestinationIndex(source: 0, target: 2),
            3
        )
        // C→A → [C,A,B,D]
        XCTAssertEqual(
            CandidateSongEditingService.dropDestinationIndex(source: 2, target: 0),
            0
        )
        // A down one slot → [B,A,C,D]
        XCTAssertEqual(
            CandidateSongEditingService.dropDestinationIndex(source: 0, target: 1),
            2
        )
        // self drop is no-op
        XCTAssertNil(CandidateSongEditingService.dropDestinationIndex(source: 1, target: 1))
    }

    func testMoveWithDropDestinationProducesExpectedOrder() {
        func names(from source: Int, to target: Int) -> [String] {
            var songs = ["A", "B", "C", "D"]
            guard let dest = CandidateSongEditingService.dropDestinationIndex(source: source, target: target) else {
                return songs
            }
            songs.move(fromOffsets: IndexSet(integer: source), toOffset: dest)
            return songs
        }

        XCTAssertEqual(names(from: 0, to: 2), ["B", "C", "A", "D"])
        XCTAssertEqual(names(from: 2, to: 0), ["C", "A", "B", "D"])
        XCTAssertEqual(names(from: 0, to: 1), ["B", "A", "C", "D"])
        XCTAssertEqual(names(from: 1, to: 1), ["A", "B", "C", "D"])
    }

    func testEndedSetlistHomeCopyIsGuessNotActualSetlist() {
        let copy = HomeFeatureCopySource.copy(for: .setlist, phase: .ended)
        XCTAssertEqual(copy.badge, "歌单猜想")
        XCTAssertEqual(copy.note, "回看开场前的猜想")
        XCTAssertEqual(copy.cta, "回看猜想")

        let surfaces = [copy.badge, copy.note, copy.cta]
        for text in surfaces {
            XCTAssertFalse(text.contains("今晚唱了什么"))
            XCTAssertFalse(text.contains("实际歌单"))
            XCTAssertFalse(text.contains("已唱"))
            XCTAssertFalse(text.contains("官方"))
            XCTAssertTrue(text.contains("猜想"), "expected 猜想 in: \(text)")
        }
    }

    private func makeShow() throws -> Show {
        try Show(
            name: "Session 测试现场",
            date: DateComponents(calendar: calendar, year: 2026, month: 8, day: 1).date!,
            startTime: DateComponents(calendar: calendar, year: 2026, month: 8, day: 1, hour: 20).date!,
            type: .concert
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self, CandidateSongGroup.self, CandidateSong.self, ArtistInterestItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
private struct StubCandidateSongGenerator: CandidateSongGenerating {
    let inputs: [CandidateSongInput]

    func generate(for show: Show, artistInterests: [ArtistInterestItem]) async throws -> [CandidateSongInput] {
        inputs
    }
}

@MainActor
private struct ProgressiveStubCandidateSongGenerator: CandidateSongGenerating {
    let snapshots: [[CandidateSongInput]]

    func generate(for show: Show, artistInterests: [ArtistInterestItem]) async throws -> [CandidateSongInput] {
        guard let last = snapshots.last else {
            throw CandidateSongGenerationError.invalidResponse
        }
        return last
    }

    func generateCumulativeSnapshots(
        for show: Show,
        artistInterests: [ArtistInterestItem]
    ) -> AsyncThrowingStream<CandidateSongGenerationSnapshot, Error> {
        let snapshots = snapshots
        return AsyncThrowingStream { continuation in
            let task = Task {
                for (index, snapshot) in snapshots.enumerated() {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    if index == snapshots.count - 1 {
                        continuation.yield(.final(snapshot))
                    } else {
                        continuation.yield(.progress(snapshot))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@MainActor
private struct PartialThenFailGenerator: CandidateSongGenerating {
    let first: [CandidateSongInput]

    func generate(for show: Show, artistInterests: [ArtistInterestItem]) async throws -> [CandidateSongInput] {
        throw CandidateSongGenerationError.invalidResponse
    }

    func generateCumulativeSnapshots(
        for show: Show,
        artistInterests: [ArtistInterestItem]
    ) -> AsyncThrowingStream<CandidateSongGenerationSnapshot, Error> {
        let first = first
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.progress(first))
                continuation.finish(throwing: CandidateSongGenerationError.invalidResponse)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

@MainActor
private struct ProgressThenFinishGenerator: CandidateSongGenerating {
    let progress: [CandidateSongInput]

    func generate(for show: Show, artistInterests: [ArtistInterestItem]) async throws -> [CandidateSongInput] {
        throw CandidateSongGenerationError.invalidResponse
    }

    func generateCumulativeSnapshots(
        for show: Show,
        artistInterests: [ArtistInterestItem]
    ) -> AsyncThrowingStream<CandidateSongGenerationSnapshot, Error> {
        let progress = progress
        return AsyncThrowingStream { continuation in
            continuation.yield(.progress(progress))
            continuation.finish()
        }
    }
}

/// Blocks until the consumer cancels, then reports whether cancellation was observed.
@MainActor
private final class CancellableGeneratorGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private(set) var observedCancellation = false

    func markStarted() {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func markCancelled() {
        observedCancellation = true
    }
}

@MainActor
private struct CancellableStubCandidateSongGenerator: CandidateSongGenerating {
    let gate: CancellableGeneratorGate
    let final: [CandidateSongInput]

    func generate(for show: Show, artistInterests: [ArtistInterestItem]) async throws -> [CandidateSongInput] {
        final
    }

    func generateCumulativeSnapshots(
        for show: Show,
        artistInterests: [ArtistInterestItem]
    ) -> AsyncThrowingStream<CandidateSongGenerationSnapshot, Error> {
        let gate = gate
        let final = final
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                gate.markStarted()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                gate.markCancelled()
                // If not cancelled in time, would yield final — but cancellation path must not write.
                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else {
                    continuation.yield(.final(final))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
