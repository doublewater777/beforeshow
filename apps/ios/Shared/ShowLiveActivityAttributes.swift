import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// app(启动/更新)与 widget extension(渲染)共用。
// attributes 只放稳定身份字段;可编辑展示字段放 ContentState,
// 这样延期/改场馆/换封面时 update 能生效(attributes 本身不可变)。
//
// 无 push 时仅由 App 更新 ContentState。staleDate 始终指向散场边界，
// 渲染侧以 context.isStale 显示散场；计时使用有边界的系统 timerInterval。
// hasStarted 仅为兼容保留，不驱动渲染。

struct ShowLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var showName: String
        var city: String?
        var venueName: String?
        /// 开场时刻(effective start)
        var startDate: Date
        /// 用户填写的散场时间；缺省时由 endBoundary 提供默认边界。
        var endDate: Date?
        /// 实际生命周期结束边界(包含散场或当日落幕)
        var lifecycleEnd: Date? = nil
        var timeZoneSecondsFromGMT: Int? = nil
        var endTimeZoneSecondsFromGMT: Int? = nil
        var timeZoneIdentifier: String? = nil
        var endTimeZoneIdentifier: String? = nil
        /// App Group 容器内的封面缓存文件名(Live Activity 小图规格);nil 用占位
        var coverImageFilename: String?
        /// 开场是否已过，由 App 同步时写入，仅为兼容保留。
        var hasStarted: Bool = false
        var currentArtistName: String? = nil
        var currentStageName: String? = nil
        /// 主现场这一场的起止；计时在单场结束时停止。
        var currentStartsAt: Date? = nil
        var currentEndsAt: Date? = nil
        var nextArtistName: String? = nil
        var nextStageName: String? = nil
        var nextStartsAt: Date? = nil
        var isNextStartingSoon: Bool = false
        var isInterestedNext: Bool = false
        var isFestivalDayActive: Bool = false
        /// 与主现场同时在演的另一场(现场模式)。
        var alsoArtistName: String? = nil
        var alsoStageName: String? = nil
        /// App Group 内艺人头像小图文件名;nil 用首字母。
        var currentArtistImageFilename: String? = nil
        var alsoArtistImageFilename: String? = nil
        var nextArtistImageFilename: String? = nil

        /// Shared by ActivityKit staleness and the widget's bounded system timer.
        var endBoundary: Date {
            lifecycleEnd ?? endDate ?? currentEndsAt ?? startDate.addingTimeInterval(
                TimeInterval(CurrentShowTimeState.defaultDurationHours) * 3_600
            )
        }

        var timerInterval: ClosedRange<Date> {
            let start = currentStartsAt ?? startDate
            let end = min(currentEndsAt ?? endBoundary, endBoundary)
            return start...max(start, end)
        }

        func hasEnded(isStale: Bool, now: Date) -> Bool {
            isStale || now >= endBoundary
        }

        var startCalendar: Calendar {
            calendar(identifier: timeZoneIdentifier, offsetSeconds: timeZoneSecondsFromGMT)
        }

        var endCalendar: Calendar {
            calendar(
                identifier: endTimeZoneIdentifier ?? timeZoneIdentifier,
                offsetSeconds: endTimeZoneSecondsFromGMT ?? timeZoneSecondsFromGMT
            )
        }

        private func calendar(identifier: String?, offsetSeconds: Int?) -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            if let identifier,
               let timeZone = TimeZone(identifier: identifier) {
                calendar.timeZone = timeZone
            } else if let offsetSeconds,
                      let timeZone = TimeZone(secondsFromGMT: offsetSeconds) {
                calendar.timeZone = timeZone
            }
            return calendar
        }
    }

    /// 现场身份(app 侧判断是否同一场,决定更新还是重启)
    var showID: String
}
