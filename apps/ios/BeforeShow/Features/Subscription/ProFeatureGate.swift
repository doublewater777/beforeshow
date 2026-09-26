import Foundation

struct ProFeatureGate {
    static let freeBaseShowCapacity = 5
    static let minimumMonthlyFreeCapacity = 6

    private static let freeCapacityStateKey = "freeShowCapacityState.v1"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static func resetFreeCapacityState(in userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: freeCapacityStateKey)
    }

    func canAddShow(
        from shows: [Show],
        entitlement: ProEntitlementState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        synchronizeFreeCapacity(
            from: shows,
            entitlement: entitlement,
            now: now,
            calendar: calendar
        )

        guard !entitlement.isProActive else { return true }

        let currentCount = selfAddedShowCount(from: shows)
        guard let state = currentState(now: now, calendar: calendar),
              let baseline = state.baselineSelfAddedShowCount else {
            return currentCount < Self.minimumMonthlyFreeCapacity
        }

        return currentCount < max(Self.minimumMonthlyFreeCapacity, baseline + 1)
    }

    /// Keeps one durable free-capacity baseline per local calendar month.
    ///
    /// While Pro is active we keep observing the retained self-added count without
    /// creating a free baseline. If Pro later expires in the same month, that moment's
    /// count becomes the baseline unless the month already had a free baseline.
    func synchronizeFreeCapacity(
        from shows: [Show],
        entitlement: ProEntitlementState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let currentCount = selfAddedShowCount(from: shows)
        let month = FreeCapacityMonth(now: now, calendar: calendar)
        let stored = loadState()

        let next: FreeCapacityState
        if let stored, stored.month == month {
            next = FreeCapacityState(
                month: month,
                baselineSelfAddedShowCount: entitlement.isProActive
                    ? stored.baselineSelfAddedShowCount
                    : (stored.baselineSelfAddedShowCount ?? currentCount),
                lastObservedSelfAddedShowCount: currentCount
            )
        } else {
            let baseline: Int?
            if entitlement.isProActive {
                baseline = nil
            } else if let stored {
                // If the first observed mutation after midnight is a deletion, the
                // previous observation is the true month-boundary count.
                baseline = stored.lastObservedSelfAddedShowCount
            } else {
                // Migration / first launch of this policy.
                baseline = currentCount
            }

            next = FreeCapacityState(
                month: month,
                baselineSelfAddedShowCount: baseline,
                lastObservedSelfAddedShowCount: currentCount
            )
        }

        saveState(next)
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

    private func currentState(now: Date, calendar: Calendar) -> FreeCapacityState? {
        guard let state = loadState(),
              state.month == FreeCapacityMonth(now: now, calendar: calendar) else {
            return nil
        }
        return state
    }

    private func loadState() -> FreeCapacityState? {
        guard let data = userDefaults.data(forKey: Self.freeCapacityStateKey) else { return nil }
        return try? JSONDecoder().decode(FreeCapacityState.self, from: data)
    }

    private func saveState(_ state: FreeCapacityState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.freeCapacityStateKey)
    }
}

private struct FreeCapacityState: Codable, Equatable {
    let month: FreeCapacityMonth
    let baselineSelfAddedShowCount: Int?
    let lastObservedSelfAddedShowCount: Int
}

private struct FreeCapacityMonth: Codable, Equatable {
    let year: Int
    let month: Int

    init(now: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: now)
        year = components.year ?? 0
        month = components.month ?? 0
    }
}
