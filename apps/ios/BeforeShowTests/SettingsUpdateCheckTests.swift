import XCTest
@testable import BeforeShow

@MainActor
final class SettingsUpdateCheckTests: XCTestCase {
    func testVersionComparisonNewerCases() {
        XCTAssertTrue(AppUpdateChecker.isVersion("1.1.4", newerThan: "1.1.3"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.2.0", newerThan: "1.1.3"))
        XCTAssertTrue(AppUpdateChecker.isVersion("2.0.0", newerThan: "1.1.3"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.1.10", newerThan: "1.1.3"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.2", newerThan: "1.1.3"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.1.3.1", newerThan: "1.1.3"))
    }

    func testVersionComparisonNotNewerCases() {
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1.3", newerThan: "1.1.3"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1.2", newerThan: "1.1.3"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.0.9", newerThan: "1.1.3"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1.3", newerThan: "1.1.10"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1.0", newerThan: "1.1"))
        XCTAssertFalse(AppUpdateChecker.isVersion("", newerThan: "1.1.3"))
        XCTAssertFalse(AppUpdateChecker.isVersion("abc", newerThan: "1.1.3"))
    }

    func testUpdateAvailableWhenRemoteIsNewer() async {
        let checker = AppUpdateChecker(
            currentVersion: "1.1.3",
            appStoreID: "6780078298",
            fetchRemoteVersion: { "1.2.0" }
        )
        XCTAssertEqual(checker.status, .idle)
        XCTAssertFalse(checker.hasUpdate)
        XCTAssertNil(checker.remoteVersion)

        await checker.check()

        XCTAssertEqual(checker.status, .updateAvailable(remoteVersion: "1.2.0"))
        XCTAssertTrue(checker.hasUpdate)
        XCTAssertEqual(checker.remoteVersion, "1.2.0")
    }

    func testUpToDateWhenRemoteMatchesCurrent() async {
        let checker = AppUpdateChecker(
            currentVersion: "1.1.3",
            appStoreID: "6780078298",
            fetchRemoteVersion: { "1.1.3" }
        )

        await checker.check()

        XCTAssertEqual(checker.status, .upToDate(remoteVersion: "1.1.3"))
        XCTAssertFalse(checker.hasUpdate)
        XCTAssertEqual(checker.remoteVersion, "1.1.3")
    }

    func testUpToDateWhenRemoteIsOlder() async {
        let checker = AppUpdateChecker(
            currentVersion: "1.1.3",
            appStoreID: "6780078298",
            fetchRemoteVersion: { "1.1.0" }
        )

        await checker.check()

        XCTAssertEqual(checker.status, .upToDate(remoteVersion: "1.1.0"))
        XCTAssertFalse(checker.hasUpdate)
        XCTAssertEqual(checker.remoteVersion, "1.1.0")
    }

    func testStatusFailedWhenRemoteFetchThrows() async {
        struct MockError: Error {}
        let checker = AppUpdateChecker(
            currentVersion: "1.1.3",
            appStoreID: "6780078298",
            fetchRemoteVersion: { throw MockError() }
        )

        await checker.check()

        XCTAssertEqual(checker.status, .failed)
        XCTAssertFalse(checker.hasUpdate)
        XCTAssertNil(checker.remoteVersion)
    }

    func testStatusFailedWhenRemoteVersionIsEmpty() async {
        let checker = AppUpdateChecker(
            currentVersion: "1.1.3",
            appStoreID: "6780078298",
            fetchRemoteVersion: { "" }
        )

        await checker.check()

        XCTAssertEqual(checker.status, .failed)
        XCTAssertFalse(checker.hasUpdate)
        XCTAssertNil(checker.remoteVersion)
    }

    func testAppStoreLookupResponseDecoding() throws {
        let json = """
        {
            "resultCount": 1,
            "results": [
                {
                    "version": "1.2.0",
                    "trackViewUrl": "https://apps.apple.com/app/id6780078298"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AppStoreLookupResponse.self, from: json)
        XCTAssertEqual(response.resultCount, 1)
        XCTAssertEqual(response.results.first?.version, "1.2.0")
        XCTAssertEqual(response.results.first?.trackViewUrl, "https://apps.apple.com/app/id6780078298")
    }

    func testAppStoreInformationURL() {
        XCTAssertEqual(AppStoreInformation.appStoreURL?.absoluteString, "https://apps.apple.com/app/id6780078298")
    }
}
