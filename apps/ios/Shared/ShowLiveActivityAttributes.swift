import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// app(启动/更新)与 widget extension(渲染)共用。
// attributes 只放稳定身份字段;可编辑展示字段放 ContentState,
// 这样延期/改场馆/换封面时 update 能生效(attributes 本身不可变)。
//
// 刻意不放 phase:无 push 时 ContentState 只在 app 运行时更新,
// 跨开场零点可能拿不到 update——UI 一律用跨零恒成立的中性文案,
// 正确性不依赖任何条件切换。

struct ShowLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var showName: String
        var city: String?
        var venueName: String?
        /// 开场时刻(effective start)
        var startDate: Date
        /// 预计谢幕(endBoundary);nil 时不画进度条
        var endDate: Date?
        var timeZoneSecondsFromGMT: Int? = nil
        var endTimeZoneSecondsFromGMT: Int? = nil
        var timeZoneIdentifier: String? = nil
        var endTimeZoneIdentifier: String? = nil
        /// App Group 容器内的封面缓存文件名(Live Activity 小图规格);nil 用占位
        var coverImageFilename: String?
        /// 开场时刻是否已过(app 运行时由 desiredState 写入)。LA 无自驱重渲染,
        /// 跨开场零点需靠状态翻转「已开场」标签,不能依赖渲染期的 Date()。
        /// optional:旧构建存留的活动解码时无此键,回退到渲染期 Date() 判断。
        var hasStarted: Bool? = nil

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
