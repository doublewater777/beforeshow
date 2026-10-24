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

    func testInterruptionResumeNeedsBothUserIntentAndSystemRecommendation() {
        var intent = ListeningPlaybackIntent()
        intent.requestedPlay()
        intent.interruptionBegan()

        XCTAssertTrue(intent.shouldResume(systemRecommendsResume: true))
        XCTAssertFalse(intent.shouldResume(systemRecommendsResume: false))

        intent.requestedPause()
        XCTAssertFalse(
            intent.shouldResume(systemRecommendsResume: true),
            "A pause during the interruption outranks the system recommendation"
        )
    }

    func testInterruptedPauseIsNotTreatedAsUserPause() {
        var intent = ListeningPlaybackIntent()
        intent.requestedPlay()
        intent.interruptionBegan()
        intent.playerDidChange(to: .interrupted)

        XCTAssertTrue(intent.shouldResume(systemRecommendsResume: true))

        intent.playerDidChange(to: .paused)
        XCTAssertTrue(
            intent.shouldResume(systemRecommendsResume: true),
            "The system pauses the player for the interruption; intent survives"
        )
    }

    func testPauseOutsideInterruptionClearsUserIntentOnceItSettles() {
        var intent = ListeningPlaybackIntent()
        intent.requestedPlay()
        intent.confirmedPause()

        XCTAssertFalse(
            intent.shouldResume(systemRecommendsResume: true),
            "A Lock Screen pause is a user pause"
        )
    }

    func testPlaybackStartedOutsideTheAppCountsAsUserIntent() {
        var intent = ListeningPlaybackIntent()
        intent.playerDidChange(to: .playing)

        XCTAssertTrue(intent.shouldResume(systemRecommendsResume: true))
    }

    func testStoppingClearsIntentSoAnOldInterruptionCannotReviveIt() {
        var intent = ListeningPlaybackIntent()
        intent.requestedPlay()
        intent.interruptionBegan()
        intent.stopped()

        XCTAssertFalse(intent.shouldResume(systemRecommendsResume: true))
        XCTAssertFalse(intent.isInterrupted)
    }

    func testUnavailableQueueBlocksResumeEvenWithIntentAndRecommendation() {
        var intent = ListeningPlaybackIntent()
        intent.requestedPlay()
        intent.interruptionBegan()

        XCTAssertFalse(
            intent.shouldResume(systemRecommendsResume: true, canResume: false)
        )
    }

    func testConfirmedPauseDuringInterruptionDoesNotCancelTheResume() {
        var intent = ListeningPlaybackIntent()
        intent.requestedPlay()
        intent.interruptionBegan()
        intent.playerDidChange(to: .paused)

        intent.confirmedPause()

        XCTAssertTrue(
            intent.shouldResume(systemRecommendsResume: true),
            "The system's own pause must not be mistaken for the user's"
        )
    }
}
