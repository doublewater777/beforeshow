import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// app(启动/更新)与 widget extension(渲染)共用。静态内容放 attributes,
// 随时间变化的最小状态放 ContentState;计时文本用 Text(timerInterval:) 原生跳动,
// 不依赖 content state 高频更新。

enum ShowLiveActivityPhase: String, Codable, Hashable {
    /// 开场前倒计时
    case countdown
    /// 开场中(越过开场时间,未到预计谢幕)
    case live
}

struct ShowLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: ShowLiveActivityPhase
    }

    /// 现场身份(app 侧判断是否同一场,决定更新还是重启)
    var showID: String
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
