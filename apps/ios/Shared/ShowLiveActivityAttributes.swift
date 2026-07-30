import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// app(启动/更新)与 widget extension(渲染)共用。
// attributes 只放稳定身份字段;可编辑展示字段放 ContentState,
// 这样延期/改场馆/换封面时 update 能生效(attributes 本身不可变)。

enum ShowLiveActivityPhase: String, Codable, Hashable {
    /// 开场前倒计时
    case countdown
    /// 开场中(越过开场时间,未到预计谢幕)
    case live
}

struct ShowLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: ShowLiveActivityPhase
        var showName: String
        var city: String?
        var venueName: String?
        /// 开场时刻(effective start)
        var startDate: Date
        /// 预计谢幕(endBoundary);nil 时不画进度条
        var endDate: Date?
        /// App Group 容器内的封面缓存文件名;nil 用占位
        var coverImageFilename: String?
    }

    /// 现场身份(app 侧判断是否同一场,决定更新还是重启)
    var showID: String
}
