import Foundation

// MARK: - Live Activity Alert Copy
// 预约启动的实时活动到点必弹 alert。开场段替本地「开场前」提醒说话,用同一套文案;
// 分段交接是技术边界,不是换场:有人在演时说正在演出的那一场,否则说下一场。

struct LiveActivityAlertCopy: Equatable {
    let title: String
    let body: String

    static func opening(snapshot: WidgetShowSnapshot, opening: Date, start: Date) -> LiveActivityAlertCopy {
        let calendar = snapshot.timing.eventCalendar(fallback: .current)
        let copy = NotificationCopy(context: NotificationCopyContext(snapshot: snapshot, opening: opening, calendar: calendar))
        let remaining = Int(opening.timeIntervalSince(start))
        // 满 3 小时用「还有 3 小时，准备出门」;被 8 小时上限截短时说实际剩余。
        let message = copy.showDay(remainingSeconds: remaining >= 3 * 3_600 - 60 ? nil : remaining)
        return LiveActivityAlertCopy(
            title: copy.displayTitle(for: .showDay),
            body: copy.displayBody(message, for: .showDay)
        )
    }

    static func handover(state: ShowLiveActivityAttributes.ContentState) -> LiveActivityAlertCopy {
        if let artist = state.currentArtistName {
            return LiveActivityAlertCopy(
                title: BSLocalization.text("正在演出"),
                body: state.currentStageName.map { BSLocalization.format("%1$@ · %2$@", artist, $0) } ?? artist
            )
        }
        if let artist = state.nextArtistName {
            let opening = state.nextStartsAt.map { LiveActivityCopy.reminderOpening($0, calendar: state.startCalendar) }
            return LiveActivityAlertCopy(
                title: BSLocalization.text("下一场"),
                body: [artist, opening, state.nextStageName].compactMap { $0 }
                    .reduce(into: "") { $0 = $0.isEmpty ? $1 : BSLocalization.format("%1$@ · %2$@", $0, $1) }
            )
        }
        return LiveActivityAlertCopy(title: state.showName, body: BSLocalization.text("已开场"))
    }
}

extension NotificationCopyContext {
    init(snapshot: WidgetShowSnapshot, opening: Date, calendar: Calendar) {
        let name = snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines)
        showName = name.isEmpty ? BSLocalization.text("这场现场") : name
        artistName = nil
        isFestival = !(snapshot.timetable?.days.isEmpty ?? true)
        let venue = snapshot.venueName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = snapshot.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        place = !venue.isEmpty ? venue : !city.isEmpty ? city : nil
        isMultiDay = false
        startClock = String(
            format: "%02d:%02d",
            calendar.component(.hour, from: opening),
            calendar.component(.minute, from: opening)
        )
    }
}
