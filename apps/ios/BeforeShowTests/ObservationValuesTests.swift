import Observation
import XCTest
@testable import BeforeShow

@MainActor
final class ObservationValuesTests: XCTestCase {
    @Observable final class State {
        var value = 0
    }

    func testDeliversInitialAndLatestValuesAndStopsAfterCancellation() async throws {
        let state = State()
        var values: [Int] = []
        let task = Task { @MainActor in
            for await value in BSObservationValues({ state.value }) {
                values.append(value)
            }
        }
        try await waitUntil { values == [0] }
        state.value = 1
        try await waitUntil { values.last == 1 }
        state.value = 2
        try await waitUntil { values.last == 2 }
        task.cancel()
        await task.value
        state.value = 3
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(values, [0, 1, 2])
    }
}
