import Foundation

struct ProFeatureGate {
    static let freeBaseShowCapacity = 5
    static let minimumMonthlyFreeCapacity = 6

    func canAddShow(
        from shows: [Show],
        entitlement: ProEntitlementState,
        state: FreeShowCapacityState?
    ) -> Bool {
        guard !entitlement.isProActive else { return true }

        let currentCount = selfAddedShowCount(from: shows)
        guard let baseline = state?.baselineSelfAddedShowCount else {
            return currentCount < Self.minimumMonthlyFreeCapacity
        }

        return currentCount < max(Self.minimumMonthlyFreeCapacity, baseline + 1)
    }

    /// Pure policy for establishing or advancing the durable free-capacity baseline.
    ///
    /// While Pro is active we keep observing the retained self-added count without
    /// creating a free baseline. If Pro later expires in the same month, that moment's
    /// count becomes the baseline unless the month already had a free baseline.
    func synchronizedState(
        from shows: [Show],
        entitlement: ProEntitlementState,
        now: Date = Date(),
        calendar: Calendar = .current,
        storedState: FreeShowCapacityState?
    ) -> FreeShowCapacityState {
        let currentCount = selfAddedShowCount(from: shows)
        let month = FreeShowCapacityMonth(now: now, calendar: calendar)

        if let storedState, storedState.month == month {
            return FreeShowCapacityState(
                month: month,
                baselineSelfAddedShowCount: entitlement.isProActive
                    ? storedState.baselineSelfAddedShowCount
                    : (storedState.baselineSelfAddedShowCount ?? currentCount),
                lastObservedSelfAddedShowCount: currentCount
            )
        }

        let baseline: Int?
        if entitlement.isProActive {
            baseline = nil
        } else if let storedState {
            // If the first observed mutation after midnight is a deletion, the
            // previous observation is the true month-boundary count.
            baseline = storedState.lastObservedSelfAddedShowCount
        } else {
            // Migration / first launch of this policy.
            baseline = currentCount
        }

        return FreeShowCapacityState(
            month: month,
            baselineSelfAddedShowCount: baseline,
            lastObservedSelfAddedShowCount: currentCount
        )
    }

    func selfAddedShowCount(from shows: [Show]) -> Int {
        shows.filter(\.countsTowardFreeShowCapacity).count
    }

    func canAccessExistingLocalData(entitlement: ProEntitlementState) -> Bool {
        true
    }

    func canEditManualContent(entitlement: ProEntitlementState) -> Bool {
        true
    }
}

struct FreeShowCapacityState: Codable, Equatable {
    let month: FreeShowCapacityMonth
    let baselineSelfAddedShowCount: Int?
    let lastObservedSelfAddedShowCount: Int
}

struct FreeShowCapacityMonth: Codable, Equatable {
    let year: Int
    let month: Int

    init(now: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: now)
        year = components.year ?? 0
        month = components.month ?? 0
    }
}
