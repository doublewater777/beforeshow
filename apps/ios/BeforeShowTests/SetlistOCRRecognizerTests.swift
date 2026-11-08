import CoreGraphics
import XCTest
@testable import BeforeShow

final class SetlistOCRRecognizerTests: XCTestCase {
    func testRecognizesNumberedSetlist() {
        let lines = [
            "SETLIST",
            "1. 爱人错过",
            "2. 披星戴月的想你",
            "3. 给你一瓶魔法药水",
            "4. 唯一",
            "5. 带我去找夜生活",
            "6. 好不容易"
        ]
        let observations = lines.enumerated().map { index, text in
            TimetableOCRObservation(text: text, boundingBox: CGRect(x: 0.1, y: 0.9 - Double(index) * 0.1, width: 0.8, height: 0.05))
        }

        let result = SetlistOCRRecognizer.detect(observations: observations, showArtist: "告五人")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.songTitles.count, 6)
        XCTAssertEqual(result?.songTitles.first, "爱人错过")
        XCTAssertEqual(result?.songTitles.last, "好不容易")
        XCTAssertEqual(result?.artistName, "告五人")
    }

    func testDoesNotDetectTimetableAsSetlist() {
        let lines = [
            "草莓音乐节 演出时间表",
            "14:00 - 14:40 痛仰",
            "15:00 - 15:40 新裤子",
            "16:00 - 16:40 重塑雕像的权利",
            "17:00 - 17:40 万能青年旅店"
        ]
        let observations = lines.enumerated().map { index, text in
            TimetableOCRObservation(text: text, boundingBox: CGRect(x: 0.1, y: 0.9 - Double(index) * 0.1, width: 0.8, height: 0.05))
        }

        let result = SetlistOCRRecognizer.detect(observations: observations, showArtist: nil)
        XCTAssertNil(result, "Timetable with time intervals must not be detected as a setlist")
    }

    func testStripsTrackNumbering() {
        XCTAssertEqual(SetlistOCRRecognizer.cleanSongTitle("01. 晴天"), "晴天")
        XCTAssertEqual(SetlistOCRRecognizer.cleanSongTitle("2、简单爱"), "简单爱")
        XCTAssertEqual(SetlistOCRRecognizer.cleanSongTitle("3 七里香"), "七里香")
        XCTAssertEqual(SetlistOCRRecognizer.cleanSongTitle("IV. 夜曲"), "夜曲")
        XCTAssertEqual(SetlistOCRRecognizer.cleanSongTitle("- 稻香"), "稻香")
    }
}
