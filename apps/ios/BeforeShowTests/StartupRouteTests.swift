import XCTest
@testable import BeforeShow

final class StartupRouteTests: XCTestCase {
    func testRoutesDirectlyToHomeWhileOnboardingAndAddShowAreDeferred() {
        let state = StartupState(hasCompletedOnboarding: false, hasShows: false)

        XCTAssertEqual(StartupRouter.route(for: state), .currentHome)
    }
}
