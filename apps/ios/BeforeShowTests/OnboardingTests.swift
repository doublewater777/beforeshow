import XCTest
@testable import BeforeShow

final class OnboardingTests: XCTestCase {
    func testNewEmptyInstallPresentsOnboarding() {
        XCTAssertTrue(
            OnboardingRoutingPolicy.shouldPresent(
                hasCompleted: false,
                hasShows: false
            )
        )
    }

    func testExistingShowBypassesAndMigratesOnboarding() {
        XCTAssertFalse(
            OnboardingRoutingPolicy.shouldPresent(
                hasCompleted: false,
                hasShows: true
            )
        )
        XCTAssertTrue(
            OnboardingRoutingPolicy.shouldMigrateExistingUser(
                hasCompleted: false,
                hasShows: true
            )
        )
    }

    func testCompletedOnboardingDoesNotReturnAfterShowsAreDeleted() {
        XCTAssertFalse(
            OnboardingRoutingPolicy.shouldPresent(
                hasCompleted: true,
                hasShows: false
            )
        )
        XCTAssertFalse(
            OnboardingRoutingPolicy.shouldMigrateExistingUser(
                hasCompleted: true,
                hasShows: false
            )
        )
    }

    func testCompletionStorePersistsOnlyAfterExplicitCompletion() {
        let suiteName = "onboarding-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(OnboardingCompletionStore.hasCompleted(in: defaults))
        OnboardingCompletionStore.markCompleted(in: defaults)
        XCTAssertTrue(OnboardingCompletionStore.hasCompleted(in: defaults))
    }

    func testOnboardingPageOrderFollowsShowLifecycle() {
        XCTAssertEqual(
            OnboardingPage.allCases,
            [.beforeShow, .showDay, .afterShow, .start]
        )
    }
}
