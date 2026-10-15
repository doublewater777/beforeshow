import Foundation

/// User-facing copy for timetable validation failures.
enum TimetableReviewIssues {
    static func message(for error: TimetableValidationError) -> String {
        switch error {
        case .emptyArtistName: "请输入艺人名称"
        case .invalidPerformanceInterval: "结束时间需要晚于开始时间"
        case .emptyStageName: "请输入舞台名称"
        case .invalidDayDate: "演出开始日期与当天不一致"
        case .overlappingDays: "结束时间与下一天的演出重叠"
        case .emptyTimetable, .emptyDay, .emptyStage: "请至少保留一场演出"
        case .invalidTimeZone, .duplicateIdentity, .alreadyOwned: "时刻表数据无效，请重新导入"
        }
    }
}
