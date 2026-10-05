import XCTest
import UIKit
@testable import BeforeShow

@MainActor
final class TimetableOCRRecognitionTests: XCTestCase {
    private let recognizer = TimetableImageRecognizer(timeZoneIdentifier: "Asia/Shanghai")

    func testTaihuBayMultiImageRecognitionAndMerge() async throws {
        let files = [
            "/Users/water/Downloads/时刻表/太湖湾音乐节/IMG_4226.JPG",
            "/Users/water/Downloads/时刻表/太湖湾音乐节/IMG_4227.JPG",
            "/Users/water/Downloads/时刻表/太湖湾音乐节/IMG_4228.JPG",
            "/Users/water/Downloads/时刻表/太湖湾音乐节/IMG_4229.JPG"
        ]
        var images: [UIImage] = []
        for path in files {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let img = UIImage(data: data) else {
                continue
            }
            images.append(img)
        }
        guard images.count == 4 else {
            throw XCTSkip("Local sample files not found at expected path")
        }

        let draft = try await recognizer.recognize(images: images)
        XCTAssertEqual(draft.days.count, 4)
        XCTAssertEqual(draft.summary.dayCount, 4)
        XCTAssertGreaterThanOrEqual(draft.summary.performanceCount, 40)
        XCTAssertEqual(draft.summary.dateRangeDescription, "10.01 - 10.04")

        // Invariant check: builds valid Timetable domain entity
        let timetable = try draft.buildTimetable()
        XCTAssertEqual(timetable.orderedDays.count, 4)
        XCTAssertEqual(timetable.orderedDays.map(\.orderedStages.count), [1, 1, 1, 1])
    }

    func testTianmushanRecognition() async throws {
        let path = "/Users/water/Downloads/时刻表/天目山音乐节.JPG"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = UIImage(data: data) else {
            throw XCTSkip("Local sample files not found at expected path")
        }

        let draft = try await recognizer.recognize(images: [image])
        XCTAssertEqual(draft.days.count, 2)
        XCTAssertEqual(draft.summary.dayCount, 2)
        XCTAssertEqual(draft.summary.dateRangeDescription, "10.02 - 10.03")
        XCTAssertGreaterThanOrEqual(draft.summary.stageCount, 2)
        XCTAssertGreaterThanOrEqual(draft.summary.performanceCount, 20)

        let timetable = try draft.buildTimetable()
        XCTAssertEqual(timetable.orderedDays.count, 2)
    }

    func testBubblingIslandRecognition() async throws {
        let path = "/Users/water/Downloads/时刻表/泡泡岛时刻表.PNG"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = UIImage(data: data) else {
            throw XCTSkip("Local sample files not found at expected path")
        }

        let draft = try await recognizer.recognize(images: [image])
        XCTAssertEqual(draft.days.count, 2)
        XCTAssertEqual(draft.summary.dateRangeDescription, "10.03 - 10.04")
        XCTAssertGreaterThanOrEqual(draft.summary.performanceCount, 20)

        let timetable = try draft.buildTimetable()
        XCTAssertEqual(timetable.orderedDays.count, 2)
    }

    func testNanjingRoamingRecognition() async throws {
        let path = "/Users/water/Downloads/时刻表/南京漫游.JPG"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = UIImage(data: data) else {
            throw XCTSkip("Local sample files not found at expected path")
        }

        let draft = try await recognizer.recognize(images: [image])
        XCTAssertEqual(draft.days.count, 3)
        XCTAssertEqual(draft.summary.dateRangeDescription, "10.02 - 10.04")
        XCTAssertGreaterThanOrEqual(draft.summary.performanceCount, 20)

        let timetable = try draft.buildTimetable()
        XCTAssertEqual(timetable.orderedDays.count, 3)
    }

    func testManualCorrectionsOnDraft() throws {
        let cal = Calendar(identifier: .gregorian)
        var comp = DateComponents()
        comp.year = 2026; comp.month = 10; comp.day = 2; comp.hour = 0; comp.minute = 0
        let dayDate = cal.startOfDay(for: cal.date(from: comp)!)

        let perf1 = TimetableDraftPerformance(
            artistName: "Wrong Artist",
            startsAt: cal.date(bySettingHour: 14, minute: 0, second: 0, of: dayDate)!,
            endsAt: cal.date(bySettingHour: 15, minute: 0, second: 0, of: dayDate)!
        )
        let perf2 = TimetableDraftPerformance(
            artistName: "Delete Me",
            startsAt: cal.date(bySettingHour: 16, minute: 0, second: 0, of: dayDate)!,
            endsAt: cal.date(bySettingHour: 17, minute: 0, second: 0, of: dayDate)!
        )
        let stage = TimetableDraftStage(name: "Old Stage", sortOrder: 0, performances: [perf1, perf2])
        let day = TimetableDraftDay(date: dayDate, stages: [stage])
        var draft = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [day])

        // 1. Correct artist name and time
        let newStart = cal.date(bySettingHour: 14, minute: 30, second: 0, of: dayDate)!
        let newEnd = cal.date(bySettingHour: 15, minute: 30, second: 0, of: dayDate)!
        draft.updatePerformance(id: perf1.id, artistName: "Correct Artist", startsAt: newStart, endsAt: newEnd)
        XCTAssertEqual(draft.days[0].stages[0].performances[0].artistName, "Correct Artist")
        XCTAssertEqual(draft.days[0].stages[0].performances[0].startsAt, newStart)
        XCTAssertEqual(draft.days[0].stages[0].performances[0].endsAt, newEnd)

        // 2. Correct stage name
        draft.updateStageName(stageID: stage.id, newName: "Main Stage")
        XCTAssertEqual(draft.days[0].stages[0].name, "Main Stage")

        // 3. Delete performance
        draft.removePerformance(id: perf2.id)
        XCTAssertEqual(draft.days[0].stages[0].performances.count, 1)

        // 4. Invariant check: builds valid Timetable
        let timetable = try draft.buildTimetable()
        XCTAssertEqual(timetable.orderedDays[0].orderedStages[0].name, "Main Stage")
        XCTAssertEqual(timetable.orderedDays[0].orderedStages[0].orderedPerformances.first?.artistName, "Correct Artist")
    }

    func testEmptyAndNonImageErrors() async {
        do {
            _ = try await recognizer.recognize(images: [])
            XCTFail("Should throw missingImageData")
        } catch {
            XCTAssertEqual(error as? TimetableRecognitionError, .missingImageData)
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let blankImage = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        do {
            _ = try await recognizer.recognize(images: [blankImage])
            XCTFail("Should throw noTimetableFound")
        } catch {
            XCTAssertEqual(error as? TimetableRecognitionError, .noTimetableFound)
        }
    }
}
