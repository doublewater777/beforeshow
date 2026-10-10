import Foundation

/// Signals worth a second look after OCR: two sets on one stage at the same
/// time, an end before its start, or a missing name.
enum TimetableReviewIssues {
    struct Stage {
        var overlapping: Set<UUID> = []
        var invalid: Set<UUID> = []
        var count = 0
        var hasInvalidName = false

        func flagged(_ id: UUID) -> Bool { overlapping.contains(id) || invalid.contains(id) }
    }

    static func evaluate(_ stage: TimetableDraftStage) -> Stage {
        var result = Stage()
        if stage.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.hasInvalidName = true
            result.count += 1
        }
        let ordered = stage.performances.sorted { $0.startsAt < $1.startsAt }
        for (i, a) in ordered.enumerated() {
            if a.endsAt <= a.startsAt || a.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.invalid.insert(a.id)
                result.count += 1
            }
            for b in ordered[(i + 1)...] where b.startsAt < a.endsAt && a.startsAt < b.endsAt {
                result.overlapping.formUnion([a.id, b.id])
                result.count += 1
            }
        }
        return result
    }

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
