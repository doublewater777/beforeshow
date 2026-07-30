import Foundation
import XCTest
@testable import BeforeShow

final class WidgetSnapshotTests: XCTestCase {
    private func makeShow(
        name: String = "夜航西飞",
        changeStatus: ShowChangeStatus = .scheduled,
        postponedDate: Date? = nil
    ) throws -> Show {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!
        let startTime = calendar.date(from: DateComponents(hour: 19, minute: 30))!
        let show = try Show(
            name: name,
            date: date,
            startTime: startTime,
            city: "上海",
            venueName: "梅赛德斯-奔驰文化中心"
        )
        if let postponedDate {
            show.markPostponed(newDate: postponedDate)
        } else if changeStatus == .canceled {
            show.markCanceled()
        }
        return show
    }

    func testSnapshotCodableRoundTrip() throws {
        let show = try makeShow()
        let snapshot = WidgetShowSnapshot(show: show, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetShowSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.timing.effectiveDate, show.effectiveDate)
        XCTAssertEqual(decoded.name, "夜航西飞")
        XCTAssertEqual(decoded.city, "上海")
    }

    func testTimingInitMatchesShowInit() throws {
        let now = Date()
        let calendar = Calendar.current

        let scheduled = try makeShow()
        let postponed = try makeShow(
            postponedDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )
        let canceled = try makeShow(changeStatus: .canceled)

        for show in [scheduled, postponed, canceled] {
            let viaShow = CurrentShowTimeState(show: show, calendar: calendar, now: now)
            let viaTiming = CurrentShowTimeState(timing: show.timingFields, calendar: calendar, now: now)
            XCTAssertEqual(viaShow, viaTiming)
        }
    }

    func testAppGroupStoreWriteReadClear() throws {
        let snapshot = WidgetShowSnapshot(
            showID: UUID(),
            name: "测试现场",
            city: "北京",
            venueName: nil,
            coverImageURL: nil,
            timing: ShowTimingFields(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                startTime: Date(timeIntervalSince1970: 1_800_000_000),
                endDate: nil,
                endTime: nil,
                postponedDate: nil,
                changeStatus: .scheduled
            ),
            generatedAt: Date()
        )

        WidgetSnapshotStore.write(snapshot)
        XCTAssertEqual(WidgetSnapshotStore.read(), snapshot)

        WidgetSnapshotStore.write(nil)
        XCTAssertNil(WidgetSnapshotStore.read())
    }
}
