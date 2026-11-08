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

    func testCompletedOnboardingWithoutShowsRoutesToMainApp() {
        let suiteName = "onboarding-skip-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        OnboardingCompletionStore.markCompleted(in: defaults)

        XCTAssertTrue(OnboardingCompletionStore.hasCompleted(in: defaults))
        XCTAssertFalse(
            OnboardingRoutingPolicy.shouldPresent(
                hasCompleted: OnboardingCompletionStore.hasCompleted(in: defaults),
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

    func testPhaseLabelsDoNotRepeatTheBrandMark() {
        for page in OnboardingPage.allCases {
            XCTAssertNotEqual(page.phaseText, "开场前")
        }
    }

    func testFeatureCopyMatchesShippedFeatures() {
        XCTAssertTrue(OnboardingPage.beforeShow.bodyText.contains("听熟"))
        XCTAssertTrue(OnboardingPage.showDay.bodyText.contains("路线"))
        XCTAssertTrue(OnboardingPage.showDay.bodyText.contains("舞台"))
        XCTAssertTrue(OnboardingPage.afterShow.bodyText.contains("足迹"))
    }

    func testStartPageInvitesLinkImport() {
        XCTAssertTrue(OnboardingPage.start.bodyText.contains("链接"))
        XCTAssertFalse(OnboardingPage.start.bodyText.contains("截图"))
    }

    func testEveryPageHasItsOwnArtwork() {
        let names = OnboardingPage.allCases.map(\.artworkName)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertNotNil(UIImage(named: name), name)
        }
    }
}
