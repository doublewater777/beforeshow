import Foundation
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintArtistIdentityTests: XCTestCase {
    func testArtistCardUsesOneIdentityWhenNamesCollide() throws {
        let older = try makeShow("旧场", year: 2023, artistID: "111", avatar: "https://img.example/111.jpg")
        let unlinked = try makeShow("无关联", year: 2024, artistID: nil, avatar: "https://img.example/unknown.jpg")
        let newer = try makeShow("新场", year: 2025, artistID: "222", avatar: "https://img.example/222.jpg")

        let item = try XCTUnwrap(FootprintArchiveRankingBuilder.artists(in: [older, unlinked, newer]).first)

        XCTAssertEqual(item.artistID, "222")
        XCTAssertEqual(item.artworkURL, URL(string: "https://img.example/222.jpg"),
                       "Another identity's or an unlinked show's stored image must not stand in")
    }

    private func makeShow(_ name: String, year: Int, artistID: String?, avatar: String) throws -> Show {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
        var slot = ArtistSlot(name: "Nova", avatarURL: avatar)
        slot.appleMusicArtistID = artistID
        return try Show(name: name, date: date, startTime: date.addingTimeInterval(19 * 3_600),
                        city: "上海", venueName: "MAO", artists: [slot])
    }
}
