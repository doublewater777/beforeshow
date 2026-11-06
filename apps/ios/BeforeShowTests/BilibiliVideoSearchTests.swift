import XCTest
@testable import BeforeShow

final class BilibiliVideoSearchTests: XCTestCase {
    private func payload(_ items: String, code: Int = 0) -> Data {
        Data(#"{"code":\#(code),"data":{"result":[\#(items)]}}"#.utf8)
    }

    func testParsesVideosAndStripsHighlightMarkup() throws {
        let data = payload(#"""
        {"bvid":"BV1","title":"【4K】<em class=\"keyword\">告五人</em>《唯一》 &amp; 安可","author":"佐罗桑","play":2555059,"duration":"4:54","pic":"//i1.hdslb.com/a.jpg"}
        """#)

        let videos = try BilibiliSearchParser.videos(from: data, artist: "告五人")

        XCTAssertEqual(videos, [ArtistVideo(
            bvid: "BV1", title: "【4K】告五人《唯一》 & 安可", author: "佐罗桑",
            playCount: 2_555_059, duration: "4:54", coverURL: URL(string: "https://i1.hdslb.com/a.jpg")
        )])
    }

    func testDropsHitsThatDoNotNameTheArtist() throws {
        let data = payload(#"""
        {"bvid":"BV1","title":"Soft Pine live","author":"x","play":1,"duration":"1:00","pic":""},
        {"bvid":"BV2","title":"unrelated","author":"y","play":1,"duration":"1:00","pic":""},
        {"bvid":"BV3","title":"concert","author":"SOFTPINE官方","play":"12","duration":"1:00","pic":""},
        {"bvid":"BV1","title":"Soft Pine again","author":"x","play":1,"duration":"1:00","pic":""}
        """#)

        let videos = try BilibiliSearchParser.videos(from: data, artist: "Soft Pine")

        XCTAssertEqual(videos.map(\.bvid), ["BV1", "BV3"])
        XCTAssertEqual(videos.last?.playCount, 12)
    }

    func testServiceErrorCodeThrows() {
        XCTAssertThrowsError(try BilibiliSearchParser.videos(from: payload("", code: -412), artist: "a")) {
            XCTAssertEqual($0 as? BilibiliSearchParser.ServiceError, .init(code: -412))
        }
    }

    func testStreamResolvesCidThenHttpsMp4() throws {
        let view = Data(#"{"code":0,"data":{"bvid":"BV1","cid":792044692}}"#.utf8)
        XCTAssertEqual(try BilibiliSearchParser.cid(from: view), 792044692)

        let play = Data(#"{"code":0,"data":{"quality":80,"durl":[{"url":"http://upos.example/v.mp4?e=1"}]}}"#.utf8)
        XCTAssertEqual(try BilibiliSearchParser.streamURL(from: play).absoluteString, "https://upos.example/v.mp4?e=1")
    }

    func testStreamWithoutPartsThrows() {
        let play = Data(#"{"code":-404,"data":null}"#.utf8)
        XCTAssertThrowsError(try BilibiliSearchParser.streamURL(from: play))
    }
}
