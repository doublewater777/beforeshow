import Foundation

enum ShowChangeStatus: String, CaseIterable, Codable, Equatable {
    case scheduled
    case postponed
    case canceled
}

/// 现场的时间字段，纯值类型——SwiftData `Show` 与 widget 快照共用同一组输入，
/// 让 `CurrentShowTimeState` 可以脱离 @Model 在 extension 进程里重算倒计时。
struct ShowTimingFields: Equatable, Codable {
    var date: Date
    var startTime: Date
    var endDate: Date?
    var endTime: Date?
    var endedAt: Date? = nil
    var postponedDate: Date?
    var changeStatus: ShowChangeStatus

    var effectiveDate: Date {
        postponedDate ?? date
    }
}
