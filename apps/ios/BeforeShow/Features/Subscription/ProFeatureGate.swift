import Foundation

struct ProFeatureGate {
    static let freeShowCapacity = 20
    static let maxFreeShowCapacity = 20

    func canAddShow(
        from shows: [Show],
        entitlement: ProEntitlementState,
        state: FreeShowCapacityState? = nil
    ) -> Bool {
        guard !entitlement.isProActive else { return true }
        let currentCount = selfAddedShowCount(from: shows)
        return currentCount < Self.freeShowCapacity
    }

    /// Free show capacity is 20 shows.
    /// Retained for coordinator and maintenance synchronization without monthly growth calculations.
    func synchronizedState(
        from shows: [Show],
        entitlement: ProEntitlementState,
        now: Date = Date(),
        calendar: Calendar = .current,
        storedState: FreeShowCapacityState? = nil
    ) -> FreeShowCapacityState {
        let currentCount = selfAddedShowCount(from: shows)
        let month = FreeShowCapacityMonth(now: now, calendar: calendar)

        return FreeShowCapacityState(
            month: month,
            baselineSelfAddedShowCount: entitlement.isProActive ? nil : currentCount,
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
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month], from: now)
        year = components.year ?? 0
        month = components.month ?? 0
    }

    func isBefore(_ other: FreeShowCapacityMonth) -> Bool {
        if year != other.year {
            return year < other.year
        }
        return month < other.month
    }
}
