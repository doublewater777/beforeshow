import XCTest
@testable import BeforeShow

/// 倒计时分享卡上的二维码：链接本身带着这场现场，扫到的人原样加进自己的 App。
@MainActor
final class ShowShareLinkTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    func testShowArrivesAsItWasShared() throws {
        let cover = "https://img.alicdn.com/imgextra/i3/2251059038/O1CN01AbCdEfGh1TmM6Hk0i_!!2251059038.jpg"
        let show = try Show(
            name: "五月天 回到那一天 25周年巡回演唱会 上海站",
            date: start,
            startTime: start,
            timeZoneSecondsFromGMT: 28_800,
            timeZoneIdentifier: "Asia/Shanghai",
            city: "上海",
            venueName: "上海体育场",
            venueAddress: "天钥桥路666号",
            artists: [ArtistSlot(name: "五月天", avatarURL: "https://example.com/a.jpg")],
            coverImageURL: cover
        )
        let url = ShowShareLink.url(for: show)
        XCTAssertEqual(url.host, "beforeshow.doublewaterapps.com")
        XCTAssertTrue(url.path.hasPrefix("/s/"))

        let draft = try XCTUnwrap(ShowShareLink.draft(from: url))
        XCTAssertEqual(draft.name, show.name)
        XCTAssertEqual(draft.date, start)
        XCTAssertEqual(draft.startTime, start)
        XCTAssertEqual(draft.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(draft.timeZoneSecondsFromGMT, 28_800)
        XCTAssertEqual(draft.city, "上海")
        XCTAssertEqual(draft.venueName, "上海体育场")
        XCTAssertTrue(draft.artists.isEmpty, "The lineup stays out so the code stays sparse")
        XCTAssertEqual(draft.coverImageURL, cover)
        XCTAssertEqual(draft.source, .link)
        XCTAssertEqual(draft.recognizedFields, [.name, .date, .startTime, .city, .venueName], "Everything brought in is marked")
        XCTAssertNoThrow(try draft.makeShow())
    }

    func testFestivalKeepsItsLastDay() throws {
        let lastDay = start.addingTimeInterval(86_400)
        let end = lastDay.addingTimeInterval(6 * 3_600)
        let show = try Show(name: "草莓音乐节", date: start, startTime: start, endDate: lastDay, endTime: end)
        let draft = try XCTUnwrap(ShowShareLink.draft(from: ShowShareLink.url(for: show)))
        XCTAssertEqual(draft.endDate, lastDay)
        XCTAssertEqual(draft.endTime, end)
    }

    func testPostponedShowTravelsOnItsNewDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let show = try Show(name: "草东没有派对", date: start, startTime: start)
        let newDate = start.addingTimeInterval(14 * 86_400)
        show.markPostponed(newDate: newDate)
        let draft = try XCTUnwrap(ShowShareLink.draft(from: ShowShareLink.url(for: show)))
        XCTAssertEqual(draft.date, newDate)
        let startTime = try XCTUnwrap(draft.startTime)
        XCTAssertTrue(calendar.isDate(startTime, inSameDayAs: newDate))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: startTime),
                       calendar.dateComponents([.hour, .minute], from: start))
    }

    func testOnlyWebCoversTravel() throws {
        let local = try Show(name: "A", date: start, startTime: start, coverImageURL: ShowCoverReference.stored(fileName: "x.jpg"))
        XCTAssertEqual(ShowShareLink.draft(from: ShowShareLink.url(for: local))?.coverImageURL, "")

        let long = "https://example.com/" + String(repeating: "a", count: ShowShareLink.coverLimit)
        let longCover = try Show(name: "A", date: start, startTime: start, coverImageURL: long)
        XCTAssertEqual(ShowShareLink.draft(from: ShowShareLink.url(for: longCover))?.coverImageURL, "",
                       "A long cover address would make the code too dense to scan")
    }

    func testAppSchemeCarriesTheSameShow() throws {
        let show = try Show(name: "A", date: start, startTime: start)
        let token = try XCTUnwrap(ShowShareLink.token(in: ShowShareLink.url(for: show)))
        let draft = try XCTUnwrap(ShowShareLink.draft(from: XCTUnwrap(URL(string: "beforeshow://s/\(token)"))))
        XCTAssertEqual(draft.name, "A")
    }

    func testOtherLinksAreNotShowLinks() throws {
        for link in [
            "https://beforeshow.doublewaterapps.com/join/abc",
            "https://example.com/s/abc",
            "beforeshow://listen",
            "beforeshow://join/abc",
        ] {
            XCTAssertNil(ShowShareLink.token(in: try XCTUnwrap(URL(string: link))), link)
        }
    }

    func testBrokenTokensDoNotDecode() throws {
        let unsupported = Data(#"{"v":2,"n":"A","d":0,"t":0}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        for token in ["", "a.b", "bm90IGpzb24", unsupported] {
            let url = try XCTUnwrap(URL(string: "https://beforeshow.doublewaterapps.com/s/\(token)"))
            XCTAssertNil(ShowShareLink.draft(from: url), token)
        }
    }
}
