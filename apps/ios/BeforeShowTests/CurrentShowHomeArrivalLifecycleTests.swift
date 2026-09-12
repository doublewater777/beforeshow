import Foundation
import XCTest
@testable import BeforeShow

final class CurrentShowHomeArrivalLifecycleTests: XCTestCase {
    func testVisibleIdentitySwitchWaitsForChildPreparationBeforeAnimating() {
        let showA = UUID()
        let showB = UUID()
        var lifecycle = CurrentShowHomeArrivalLifecycle()

        lifecycle.observeCurrentShow(showA)
        XCTAssertNil(lifecycle.arrival)

        lifecycle.observeCurrentShow(showB)
        XCTAssertEqual(
            lifecycle.arrival,
            CurrentShowHomeArrival(showID: showB, phase: .prepared)
        )

        // A visible A → B switch must not collapse prepared and animating into
        // one parent update. The child first consumes `.prepared` by hiding all
        // three arrival surfaces, then explicitly reports readiness.
        XCTAssertEqual(CurrentShowHomeArrivalFlags.prepared.hasArrivedHero, false)
        XCTAssertEqual(CurrentShowHomeArrivalFlags.prepared.hasArrivedCountdown, false)
        XCTAssertEqual(CurrentShowHomeArrivalFlags.prepared.hasArrivedActions, false)
        XCTAssertTrue(CurrentShowHomeArrivalFlags.prepared.isPreparedForAnimation)
        XCTAssertFalse(
            lifecycle.beginAnimationIfPossible(
                currentShowID: showB,
                isVisible: true
            )
        )
        XCTAssertEqual(
            lifecycle.arrival,
            CurrentShowHomeArrival(showID: showB, phase: .prepared)
        )

        lifecycle.childDidPrepare(showID: showB)
        XCTAssertTrue(
            lifecycle.beginAnimationIfPossible(
                currentShowID: showB,
                isVisible: true
            )
        )
        XCTAssertEqual(
            lifecycle.arrival,
            CurrentShowHomeArrival(showID: showB, phase: .animating)
        )

        lifecycle.finish(showID: showB)
        XCTAssertNil(lifecycle.arrival)
    }

    func testPreparedArrivalStaysPendingUntilCurrentHomeIsActuallyVisible() {
        let showA = UUID()
        let showB = UUID()
        var lifecycle = CurrentShowHomeArrivalLifecycle()

        lifecycle.observeCurrentShow(showA)
        lifecycle.observeCurrentShow(showB)
        lifecycle.childDidPrepare(showID: showB)

        XCTAssertFalse(
            lifecycle.beginAnimationIfPossible(
                currentShowID: showB,
                isVisible: false
            )
        )
        XCTAssertEqual(
            lifecycle.arrival,
            CurrentShowHomeArrival(showID: showB, phase: .prepared)
        )

        XCTAssertTrue(
            lifecycle.beginAnimationIfPossible(
                currentShowID: showB,
                isVisible: true
            )
        )
    }

    func testVisibilityRequiresRootHomeAndManagementLayersToBeClear() {
        XCTAssertTrue(
            CurrentShowHomeVisibilityPolicy.isVisible(
                tabIsActive: true,
                sceneIsActive: true,
                featurePresentationActive: false,
                homePresentationActive: false,
                managementPresentationActive: false
            )
        )

        XCTAssertFalse(
            CurrentShowHomeVisibilityPolicy.isVisible(
                tabIsActive: true,
                sceneIsActive: true,
                featurePresentationActive: true,
                homePresentationActive: false,
                managementPresentationActive: false
            )
        )
        XCTAssertFalse(
            CurrentShowHomeVisibilityPolicy.isVisible(
                tabIsActive: true,
                sceneIsActive: true,
                featurePresentationActive: false,
                homePresentationActive: true,
                managementPresentationActive: false
            )
        )
        XCTAssertFalse(
            CurrentShowHomeVisibilityPolicy.isVisible(
                tabIsActive: true,
                sceneIsActive: true,
                featurePresentationActive: false,
                homePresentationActive: false,
                managementPresentationActive: true
            )
        )
    }

    func testIdentityChangesWhilePendingReplaceThePendingArrival() {
        let showA = UUID()
        let showB = UUID()
        let showC = UUID()
        var lifecycle = CurrentShowHomeArrivalLifecycle()

        lifecycle.observeCurrentShow(showA)
        lifecycle.observeCurrentShow(showB)
        lifecycle.childDidPrepare(showID: showB)

        lifecycle.observeCurrentShow(showC)
        XCTAssertEqual(
            lifecycle.arrival,
            CurrentShowHomeArrival(showID: showC, phase: .prepared)
        )
        XCTAssertNil(lifecycle.preparedShowID)

        lifecycle.childDidPrepare(showID: showB)
        XCTAssertNil(lifecycle.preparedShowID)
        lifecycle.childDidPrepare(showID: showC)
        XCTAssertEqual(lifecycle.preparedShowID, showC)
    }
}
