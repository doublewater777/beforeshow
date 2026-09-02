import Foundation

struct ProFeatureGate {
    /// 免费用户每个自然月可添加的现场数量。
    let freeMonthlyShowLimit: Int

    init(freeMonthlyShowLimit: Int = 1) {
        self.freeMonthlyShowLimit = freeMonthlyShowLimit
    }

    func canAddShow(showsAddedThisMonth: Int, entitlement: ProEntitlementState) -> Bool {
        entitlement.isProActive || showsAddedThisMonth < freeMonthlyShowLimit
    }

    /// 统计当自然月（本地时区）新增的现场数。
    func showsAddedThisMonth(
        from createdDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        createdDates.filter { calendar.isDate($0, equalTo: now, toGranularity: .month) }.count
    }

    /// 免费额度只统计用户自己添加的现场（`creationOrigin == .user`）。
    /// 仅因接受 CloudKit 同行邀请而新建的 participant 侧现场不占额度；
    /// 把邀请合并进用户已有现场不会退还已经占用的额度。
    func showsAddedThisMonth(
        from shows: [Show],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        showsAddedThisMonth(
            from: shows.filter { $0.countsTowardFreeMonthlyQuota }.map(\.createdAt),
            now: now,
            calendar: calendar
        )
    }

    func canAccessExistingLocalData(entitlement: ProEntitlementState) -> Bool {
        true
    }

    func canEditManualContent(entitlement: ProEntitlementState) -> Bool {
        true
    }
}
