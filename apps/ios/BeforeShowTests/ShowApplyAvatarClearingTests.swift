import XCTest
@testable import BeforeShow

final class ShowApplyAvatarClearingTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func makeShow(
        artists: [ArtistSlot] = []
    ) throws -> Show {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 19, minute: 30))!
        return try Show(
            name: "测试现场",
            date: date,
            startTime: start,
            city: "上海",
            venueName: "场馆",
            artists: artists
        )
    }

    private func makeDraft(artists: [ArtistSlot] = []) -> ShowDraft {
        ShowDraft(
            name: "测试现场",
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!,
            startTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 19, minute: 30))!,
            city: "上海",
            venueName: "场馆",
            artists: artists,
            source: .manual
        )
    }

    func testApplyKeepsAvatarsWhenArtistNameUnchanged() throws {
        let show = try makeShow(artists: [ArtistSlot(name: "陈绮贞", avatarURL: "https://example.test/avatar.png")])
        let draft = makeDraft(artists: [ArtistSlot(name: "陈绮贞", avatarURL: "https://example.test/avatar.png")])

        try show.apply(draft)

        XCTAssertEqual(show.artists, [ArtistSlot(name: "陈绮贞", avatarURL: "https://example.test/avatar.png")])
    }

    func testApplyClearsAvatarAtChangedIndexOnly() throws {
        let show = try makeShow(artists: [ArtistSlot(name: "陈绮贞", avatarURL: "https://example.test/avatar.png")])
        let draft = makeDraft(artists: [ArtistSlot(name: "Aimer", avatarURL: nil)])

        try show.apply(draft)

        XCTAssertEqual(show.artists, [ArtistSlot(name: "Aimer", avatarURL: nil)])
    }

    func testApplyShrinksAvatarsWhenRowsRemoved() throws {
        let show = try makeShow(artists: [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png"),
            ArtistSlot(name: "B", avatarURL: "https://example.test/b.png")
        ])
        let draft = makeDraft(artists: [ArtistSlot(name: "A", avatarURL: "https://example.test/a.png")])

        try show.apply(draft)

        XCTAssertEqual(show.artists, [ArtistSlot(name: "A", avatarURL: "https://example.test/a.png")])
    }

    func testApplyExtendsEmptyAvatarsWhenRowsAdded() throws {
        let show = try makeShow(artists: [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png")
        ])
        let draft = makeDraft(artists: [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png"),
            ArtistSlot(name: "B", avatarURL: nil)
        ])

        try show.apply(draft)

        XCTAssertEqual(show.artists, [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png"),
            ArtistSlot(name: "B", avatarURL: nil)
        ])
    }

    func testApplyKeepsOtherSlotsAvatarsWhenOneNameChanges() throws {
        let show = try makeShow(artists: [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png"),
            ArtistSlot(name: "B", avatarURL: "https://example.test/b.png")
        ])
        let draft = makeDraft(artists: [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png"),
            ArtistSlot(name: "B 改名", avatarURL: "https://example.test/b.png")
        ])

        try show.apply(draft)

        // B 改名 → 那一 slot 头像被清; A 头像保留
        XCTAssertEqual(show.artists, [
            ArtistSlot(name: "A", avatarURL: "https://example.test/a.png"),
            ArtistSlot(name: "B 改名", avatarURL: nil)
        ])
    }
}
