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
            [.beforeShow, .listening, .showDay, .afterShow, .start]
        )
    }

    func testOnboardingPageCopyCustomizedForInvitedSnapshot() {
        let futureSnapshot = CompanionInviteSnapshot(
            token: "test-token-future",
            shareURL: URL(string: "https://www.icloud.com/share/test")!,
            showName: "草东没有派对",
            showStartTime: Date(timeIntervalSince1970: 1_792_324_800),
            timeZoneIdentifier: "Asia/Shanghai",
            timeZoneSecondsFromGMT: 28800,
            location: "MAO Livehouse · 上海",
            ownerName: "Alex",
            coverImageURL: URL(string: "https://images.example.com/poster.jpg")
        )

        XCTAssertEqual(OnboardingPage.start.phaseText(for: futureSnapshot), "同行约定")
        XCTAssertEqual(OnboardingPage.start.title(for: futureSnapshot), "一起去现场")
        XCTAssertTrue(OnboardingPage.start.bodyText(for: futureSnapshot).contains("Alex"))
        XCTAssertTrue(OnboardingPage.start.bodyText(for: futureSnapshot).contains("倒数"))

        let pastSnapshot = CompanionInviteSnapshot(
            token: "test-token-past",
            shareURL: URL(string: "https://www.icloud.com/share/test")!,
            showName: "SUMMER DRIVER",
            showStartTime: Date(timeIntervalSince1970: 1_656_156_600), // 2022
            timeZoneIdentifier: "Asia/Shanghai",
            timeZoneSecondsFromGMT: 28800,
            location: "Loopy · 杭州",
            ownerName: "yy",
            coverImageURL: nil
        )

        XCTAssertEqual(OnboardingPage.start.phaseText(for: pastSnapshot), "共同记忆")
        XCTAssertEqual(OnboardingPage.start.title(for: pastSnapshot), "记录这场共同回忆")
        XCTAssertTrue(OnboardingPage.start.bodyText(for: pastSnapshot).contains("yy"))
        XCTAssertFalse(OnboardingPage.start.bodyText(for: pastSnapshot).contains("倒数"))

        // Standard copy when snapshot is nil
        XCTAssertEqual(OnboardingPage.start.phaseText(for: nil), "现在开始")
        XCTAssertEqual(OnboardingPage.start.title(for: nil), "从下一场开始，慢慢靠近")
    }
}
