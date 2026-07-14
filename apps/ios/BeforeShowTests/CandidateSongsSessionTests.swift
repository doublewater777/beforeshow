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
                CandidateSongInput(songName: "新歌1", artist: "艺人甲"),
                CandidateSongInput(songName: "新歌2", artist: "艺人甲")
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
        XCTAssertEqual(songs.map(\.order), [0, 1, 2])
        XCTAssertTrue(groups.contains(where: \.isUserCurated))
        XCTAssertFalse(groups.contains(where: { $0.id == oldGroup.id }))
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

        try session.remove(songs[0], previouslyOrdered: songs, in: context)
        songs = try context.fetch(FetchDescriptor<CandidateSong>()).sorted { $0.order < $1.order }
        XCTAssertEqual(songs.map(\.songName), ["一"])
        XCTAssertEqual(songs[0].order, 0)
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
        XCTAssertTrue(text.contains("猜歌单 · 全部（非官方）"))
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
