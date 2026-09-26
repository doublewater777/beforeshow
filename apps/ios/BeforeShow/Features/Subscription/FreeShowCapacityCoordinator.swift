import Foundation

struct FreeShowCapacityCoordinator {
    private let gate: ProFeatureGate
    private let stateStore: FreeShowCapacityStateStore

    init(
        gate: ProFeatureGate = ProFeatureGate(),
        stateStore: FreeShowCapacityStateStore = FreeShowCapacityStateStore()
    ) {
        self.gate = gate
        self.stateStore = stateStore
    }

    func canAddShow(
        from shows: [Show],
        entitlement: ProEntitlementState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let state = synchronizeFreeCapacity(
            from: shows,
            entitlement: entitlement,
            now: now,
            calendar: calendar
        )
        return gate.canAddShow(
            from: shows,
            entitlement: entitlement,
            state: state
        )
    }

    @discardableResult
    func synchronizeFreeCapacity(
        from shows: [Show],
        entitlement: ProEntitlementState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FreeShowCapacityState {
        let next = gate.synchronizedState(
            from: shows,
            entitlement: entitlement,
            now: now,
            calendar: calendar,
            storedState: stateStore.load()
        )
        stateStore.save(next)
        return next
    }

    func reset() {
        stateStore.reset()
    }
}
