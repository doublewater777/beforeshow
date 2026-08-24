import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// app(启动/更新)与 widget extension(渲染)共用。
// attributes 只放稳定身份字段;可编辑展示字段放 ContentState,
// 这样延期/改场馆/换封面时 update 能生效(attributes 本身不可变)。
//
// 无 push 时 ContentState 只在 app 运行时更新,跨开场零点可能拿不到 update。
// 所以渲染侧不依赖 hasStarted:阶段(颜色/文案)由 context.isStale 判定
// (staleDate = startDate,过 T 系统重渲染),计时用系统 Text(style: .timer)
// 跨零自动倒数/正计时。hasStarted 仅为兼容保留,UI 不得以它作为渲染依据。

struct ShowLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var showName: String
        var city: String?
        var venueName: String?
        /// 开场时刻(effective start)
        var startDate: Date
        /// 预计谢幕(endBoundary);只在 hasStarted 后展示
        var endDate: Date?
        var timeZoneSecondsFromGMT: Int? = nil
        var endTimeZoneSecondsFromGMT: Int? = nil
        var timeZoneIdentifier: String? = nil
        var endTimeZoneIdentifier: String? = nil
        /// App Group 容器内的封面缓存文件名(Live Activity 小图规格);nil 用占位
        var coverImageFilename: String?
        /// 开场是否已过,由 app 同步时写入。仅为兼容保留;UI 阶段以 context.isStale 为准。
        var hasStarted: Bool = false

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
