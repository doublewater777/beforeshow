import XCTest
@testable import BeforeShow

final class AppReviewPromptTests: XCTestCase {
    func testAddedShowReviewWaitsForHomeArrival() {
        XCTAssertEqual(
            AppReviewPromptPolicy.presentationDelayNanoseconds(for: .addedShow),
            2_000_000_000
        )
    }

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "app-review-prompt-tests")
        defaults.removePersistentDomain(forName: "app-review-prompt-tests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "app-review-prompt-tests")
        defaults = nil
        super.tearDown()
    }

    func testAllowsFirstSuccessMoment() {
        XCTAssertTrue(
            AppReviewPromptPolicy.shouldPrompt(
                now: Date(timeIntervalSince1970: 1_800_000_000),
                version: "1.0",
                defaults: defaults,
                arguments: []
            )
        )
    }

    func testBlocksSameVersionUntilIntervalPasses() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        AppReviewPromptPolicy.recordPrompt(
            now: now,
            version: "1.0",
            defaults: defaults
        )

        XCTAssertFalse(
            AppReviewPromptPolicy.shouldPrompt(
                now: now.addingTimeInterval(30 * 24 * 60 * 60),
                version: "1.0",
                defaults: defaults,
                arguments: []
            )
        )
        XCTAssertTrue(
            AppReviewPromptPolicy.shouldPrompt(
                now: now.addingTimeInterval(AppReviewPromptPolicy.minimumInterval),
                version: "1.1",
                defaults: defaults,
                arguments: []
            )
        )
    }

    func testBlocksAutomatedLaunches() {
        XCTAssertFalse(
            AppReviewPromptPolicy.shouldPrompt(
                now: Date(),
                version: "1.0",
                defaults: defaults,
                arguments: ["--open-settings"]
            )
        )
        XCTAssertTrue(AppReviewPromptPolicy.isAutomatedLaunch(["--seed-app-store-screenshots"]))
        XCTAssertTrue(AppReviewPromptPolicy.isAutomatedLaunch(["--auto-fire-dispersal"]))
    }

    func testWriteReviewURLUsesAppStoreID() {
        XCTAssertEqual(
            AppReviewPrompt.writeReviewURL?.absoluteString,
            "https://apps.apple.com/app/id6780078298?action=write-review"
        )
    }

    func testRateAppCopyResolvesInEnglishAndTraditionalChinese() {
        let keys = ["评价此应用", "打开 App Store 写下评价"]
        for code in ["en", "zh-Hant"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let tablePath = Bundle(path: path)?.path(forResource: "Localizable", ofType: "strings"),
                  let table = NSDictionary(contentsOfFile: tablePath) as? [String: String] else {
                XCTFail("Missing \(code) Localizable.strings in app bundle")
                continue
            }
            for key in keys {
                XCTAssertNotNil(table[key], "\(key) missing from \(code) Localizable.strings")
            }
        }
    }
}
