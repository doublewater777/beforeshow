import XCTest
@testable import BeforeShow

final class ListeningMusicContractsTests: XCTestCase {
    func testFullPlaybackRequiresAuthorizedCatalogPlaybackCapability() {
        let access = ListeningMusicAccess(
            authorizationStatus: .authorized,
            canPlayCatalogContent: true
        )

        XCTAssertEqual(
            ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: false,
                hasCatalogMetadata: false
            ),
            .fullPlayback
        )
    }

    func testAuthorizedNonSubscriberFallsBackToPreviewWhenAvailable() {
        let access = ListeningMusicAccess(
            authorizationStatus: .authorized,
            canPlayCatalogContent: false
        )

        XCTAssertEqual(
            ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: true,
                hasCatalogMetadata: true
            ),
            .previewOnly
        )
    }

    func testDeniedAuthorizationCanUsePreviouslyCachedPreviewAsset() {
        let access = ListeningMusicAccess(
            authorizationStatus: .denied,
            canPlayCatalogContent: false
        )

        XCTAssertEqual(
            ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: true,
                hasCatalogMetadata: true
            ),
            .previewOnly
        )
    }

    func testDeniedAuthorizationFallsBackToMetadataWithoutPreview() {
        let access = ListeningMusicAccess(
            authorizationStatus: .denied,
            canPlayCatalogContent: false
        )

        XCTAssertEqual(
            ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: false,
                hasCatalogMetadata: true
            ),
            .metadataOnly
        )
    }

    func testUnavailableWhenNoAuthorizedMediaPathOrCachedMetadataExists() {
        let access = ListeningMusicAccess(
            authorizationStatus: .notDetermined,
            canPlayCatalogContent: false
        )

        XCTAssertEqual(
            ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: false,
                hasCatalogMetadata: false
            ),
            .unavailable
        )
    }

    func testAccessCheckFailureRemainsDistinctWhilePreviewStillWorks() {
        let access = ListeningMusicAccess(
            authorizationStatus: .authorized,
            catalogPlaybackAccess: .accessCheckFailed
        )

        XCTAssertFalse(access.canPlayCatalogContent)
        XCTAssertEqual(access.catalogPlaybackAccess, .accessCheckFailed)
        XCTAssertEqual(
            ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: true,
                hasCatalogMetadata: true
            ),
            .previewOnly
        )
    }

    func testCatalogRefreshPolicyUsesTwentyFourHourBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertFalse(ListeningCatalogRefreshPolicy.shouldRefresh(
            fetchedAt: now.addingTimeInterval(-(24 * 60 * 60) + 1),
            now: now
        ))
        XCTAssertTrue(ListeningCatalogRefreshPolicy.shouldRefresh(
            fetchedAt: now.addingTimeInterval(-(24 * 60 * 60)),
            now: now
        ))
    }
}
