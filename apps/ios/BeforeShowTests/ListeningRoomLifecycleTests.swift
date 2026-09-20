import Foundation
import XCTest
import SwiftData
@testable import BeforeShow

@MainActor final class ListeningRoomLifecycleTests: XCTestCase {
    func testFullBackgroundAndTabHideNeverOwnTransport() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first))
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying }
        room.setForeground(false)
        XCTAssertTrue(room.isPlaying)
        room.setActive(false)
        XCTAssertTrue(room.isPlaying)
        room.setForeground(true); room.setActive(true)
        XCTAssertTrue(room.isPlaying)
        room.playPause()
        try await ListenTestData.settle(room) { !room.isPlaying && !room.busy }
        room.setActive(false); room.setActive(true)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(room.isPlaying)
        room.stop(); room.mechanism.motion.stop()
    }

    func testForegroundBoundaryRepairsTransportChangeMissedWhileSuspended() async throws {
        let (container, show) = try ListenTestData.make()
        let playback = LifecyclePendingPlaybackService()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        room.restoreDisc(disc)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        room.playPause()
        XCTAssertFalse(room.isPlaying)

        room.setForeground(false)
        playback.setPlayingExternally(true)
        XCTAssertFalse(room.isPlaying)

        room.setForeground(true)

        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.display.player.phase, .playing)
    }

    func testOpeningLidDrainsAllPendingEvidenceBeforeControllerIsDestroyed() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer { room.mechanism.motion.stop() }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.count >= 2 })
        let firstSongID = disc.tracks[0].id
        let secondSongID = disc.tracks[1].id
        room.restoreDisc(disc, songID: firstSongID)
        try await ListenTestData.settle(room) { room.track?.id == firstSongID && !room.busy }

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )

        try await ListeningRemoteCommandBridge.shared.nextForTesting()
        XCTAssertEqual(room.track?.id, secondSongID)
        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true
        room.mechanism.setLid(open: true)

        XCTAssertTrue(playback.didStop)
        let records = try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
        XCTAssertEqual(
            Set(records.compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            [firstSongID, secondSongID]
        )
    }

    func testPartialEvidenceBatchCommitImmediatelyRefreshesRoomProjectionAndReportsFailure() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        var failSongID: String?
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable, failSongID != songID else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer {
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.count >= 2 })
        let firstSongID = disc.tracks[0].id
        let secondSongID = disc.tracks[1].id
        room.restoreDisc(disc, songID: firstSongID)
        try await ListenTestData.settle(room) { room.track?.id == firstSongID && !room.busy }

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )
        try await ListeningRemoteCommandBridge.shared.nextForTesting()
        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )

        persistenceAvailable = true
        failSongID = secondSongID
        room.errorText = nil
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(52)
        )

        XCTAssertTrue(room.actualSongIDs.contains(firstSongID))
        XCTAssertTrue(room.familiarSongIDs.contains(firstSongID))
        XCTAssertFalse(room.actualSongIDs.contains(secondSongID))
        XCTAssertFalse(room.familiarSongIDs.contains(secondSongID))
        XCTAssertNotNil(room.errorText)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            [firstSongID]
        )
    }

    func testOpeningLidWithPersistenceFailureRetainsPendingEvidenceForLaterRoomRetry() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer { room.mechanism.motion.stop() }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first { $0.tracks.count >= 2 })
        let firstSongID = disc.tracks[0].id
        let secondSongID = disc.tracks[1].id
        room.restoreDisc(disc, songID: firstSongID)
        try await ListenTestData.settle(room) { room.track?.id == firstSongID && !room.busy }

        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )
        try await ListeningRemoteCommandBridge.shared.nextForTesting()
        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )

        room.mechanism.setLid(open: true)

        XCTAssertTrue(playback.didStop)
        XCTAssertNil(
            try ListeningRemoteCommandBridge.shared.refreshForTesting(
                now: Date().addingTimeInterval(52)
            ),
            "lid-open teardown must detach the destroyed playback controller"
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<SongFamiliarityRecord>()).isEmpty)

        persistenceAvailable = true
        room.retryPendingPlaybackEvidence()

        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .compactMap { $0.actualListeningAt == nil ? nil : $0.songID }),
            [firstSongID, secondSongID]
        )
        XCTAssertTrue(room.actualSongIDs.contains(firstSongID))
        XCTAssertTrue(room.actualSongIDs.contains(secondSongID))
        XCTAssertTrue(room.familiarSongIDs.contains(firstSongID))
        XCTAssertTrue(room.familiarSongIDs.contains(secondSongID))
    }

    func testBackgroundEvidenceRetryDoesNotRepresentDismissedFailureAlert() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        var persistenceAttempts = 0
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        persistenceAttempts += 1
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer { room.mechanism.motion.stop() }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        room.restoreDisc(disc)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )

        XCTAssertEqual(
            room.errorText,
            BSLocalization.text("熟悉度保存失败，请重试")
        )
        room.errorText = nil
        let attemptsAfterDismiss = persistenceAttempts

        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertGreaterThan(
            persistenceAttempts,
            attemptsAfterDismiss,
            "background retry must have run while persistence remained unavailable"
        )
        XCTAssertNil(
            room.errorText,
            "background retry failures must not re-present a dismissed familiarity alert"
        )

        persistenceAvailable = true
        room.retryPendingPlaybackEvidence()
        room.stop()
    }

    func testBackgroundEvidenceRetryRecoveryClearsOwnedFailureAlert() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer { room.mechanism.motion.stop() }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.first?.id)
        room.restoreDisc(disc, songID: songID)
        try await ListenTestData.settle(room) { room.track?.id == songID && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )
        XCTAssertEqual(
            room.errorText,
            BSLocalization.text("熟悉度保存失败，请重试")
        )

        persistenceAvailable = true
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .contains { $0.songID == songID && $0.actualListeningAt != nil }
        )
        XCTAssertNil(
            room.errorText,
            "successful background persistence retry must clear its own stale alert"
        )
        room.stop()
    }

    func testBackgroundEvidenceRetryRecoveryDoesNotClearUnrelatedError() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer { room.mechanism.motion.stop() }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.first?.id)
        room.restoreDisc(disc, songID: songID)
        try await ListenTestData.settle(room) { room.track?.id == songID && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )
        XCTAssertNotNil(room.errorText)

        let unrelatedError = BSLocalization.text("保存失败，请重试")
        room.errorText = unrelatedError
        persistenceAvailable = true
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .contains { $0.songID == songID && $0.actualListeningAt != nil }
        )
        XCTAssertEqual(
            room.errorText,
            unrelatedError,
            "evidence recovery must not clear another coordinator error"
        )
        room.errorText = nil
        room.stop()
    }

    func testEvidenceFailureDoesNotOverrideExistingUnrelatedErrorOrClearItOnRecovery() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let playback = LifecyclePendingPlaybackService()
        var persistenceAvailable = false
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback },
            evidenceCoordinatorFactory: { modelContext in
                try ListeningPlaybackEvidenceCoordinator(
                    modelContext: modelContext,
                    persistActualFamiliarity: { songID, date in
                        _ = try ListeningRepository(modelContext: modelContext)
                            .confirmActualFamiliarity(songID: songID, at: date)
                        guard persistenceAvailable else {
                            throw LifecycleEvidencePersistenceTestError.expectedFailure
                        }
                        try modelContext.save()
                    }
                )
            }
        )
        defer { room.mechanism.motion.stop() }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.first?.id)
        room.restoreDisc(disc, songID: songID)
        try await ListenTestData.settle(room) { room.track?.id == songID && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        let unrelatedError = BSLocalization.text("保存失败，请重试")
        room.errorText = unrelatedError

        playback.currentTime = 51
        _ = try ListeningRemoteCommandBridge.shared.refreshForTesting(
            now: Date().addingTimeInterval(51)
        )

        XCTAssertEqual(
            room.errorText,
            unrelatedError,
            "evidence failure must not take alert ownership from an existing unrelated error"
        )

        persistenceAvailable = true
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SongFamiliarityRecord>())
                .contains { $0.songID == songID && $0.actualListeningAt != nil }
        )
        XCTAssertEqual(
            room.errorText,
            unrelatedError,
            "evidence recovery must preserve the unrelated error that existed before the outage"
        )
        room.errorText = nil
        room.stop()
    }

    func testLoadedDiscRestoresAcrossCoordinatorRecreationWithoutAutoplay() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.last?.id)
        room.restoreDisc(disc, songID: songID)

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertEqual(reopened.mechanism.disc?.id, disc.id)
        XCTAssertEqual(reopened.track?.id, songID)
        XCTAssertEqual(reopened.playbackState, .idle)
        XCTAssertFalse(reopened.isPlaying)

        await reopened.load(show: show)
        for _ in 0..<10 { await Task.yield() }
        try await ListenTestData.settle(reopened) { !reopened.busy }
        XCTAssertEqual(reopened.mechanism.position, .seated)
        XCTAssertTrue(reopened.mechanism.isClosed)
        XCTAssertEqual(reopened.mechanism.disc?.id, disc.id)
        XCTAssertEqual(reopened.track?.id, songID)
        XCTAssertEqual(reopened.playbackState, .idle)
        XCTAssertFalse(reopened.isPlaying)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ListeningLoadedDiscState>()), 1)
        reopened.mechanism.motion.stop()
    }

    func testManualEjectClearsColdLaunchStateBeforeCabinetReturn() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first))
        room.mechanism.setLid(open: true)
        try await ListenTestData.settle(room) { room.mechanism.isOpen }

        room.mechanism.removeDisc()
        XCTAssertEqual(room.mechanism.position, .removed)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ListeningLoadedDiscState>()), 0)

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertFalse(reopened.mechanism.hasDisc)
        XCTAssertNil(reopened.mechanism.disc)
        XCTAssertNil(reopened.track)
        reopened.mechanism.motion.stop()
    }

    func testAutomaticDiscSwapKeepsFinalLoadedDiscSnapshot() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let first = try XCTUnwrap(room.discs.first)
        let second = try XCTUnwrap(room.discs.first { $0.id != first.id })
        room.restoreDisc(first)

        room.loadDisc(second, autoplay: false)
        try await ListenTestData.settle(room) {
            !room.busy && room.mechanism.position == .seated && room.mechanism.disc?.id == second.id
        }

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertEqual(reopened.mechanism.disc?.id, second.id)
        XCTAssertEqual(reopened.playbackState, .idle)
        XCTAssertFalse(reopened.isPlaying)
        reopened.mechanism.motion.stop()
    }

    func testOpeningLidPreservesPersistedNonFirstTrackSelection() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let disc = try XCTUnwrap(room.browseArtists.first?.albums.first)
        let songID = try XCTUnwrap(disc.tracks.last?.id)
        XCTAssertNotEqual(songID, disc.tracks.first?.id)
        room.restoreDisc(disc, songID: songID)

        room.mechanism.setLid(open: true)
        try await ListenTestData.settle(room) { room.mechanism.isOpen }
        XCTAssertEqual(room.trackIndex, 0)

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertEqual(reopened.mechanism.disc?.id, disc.id)
        XCTAssertEqual(reopened.track?.id, songID)
        XCTAssertFalse(reopened.isPlaying)
        reopened.mechanism.motion.stop()
    }

    func testCurrentShowChangeKeepsLoadedDiscEvenWhenNewShowHasNoArtist() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let songID = try XCTUnwrap(disc.tracks.last?.id)
        room.restoreDisc(disc, songID: songID)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        let other = try Show(name: "Other", date: Date().addingTimeInterval(10000), startTime: Date().addingTimeInterval(10000))
        container.mainContext.insert(other); try container.mainContext.save()
        await room.load(show: other)
        XCTAssertEqual(room.mechanism.disc?.id, disc.id)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertNil(room.onlyArtistID)
        XCTAssertTrue(room.discs.isEmpty)
        XCTAssertEqual(room.show?.id, other.id)
        XCTAssertFalse(room.isPlaying)
        try await ListenTestData.settle(room) { !room.busy }
        room.mechanism.motion.stop()
    }

    func testReturningDiscToCabinetClearsColdLaunchState() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.restoreDisc(try XCTUnwrap(room.discs.first))
        try await room.mechanism.unload()

        let reopened = ListenTestData.room(container.mainContext)
        XCTAssertFalse(reopened.mechanism.hasDisc)
        XCTAssertNil(reopened.mechanism.disc)
        XCTAssertNil(reopened.track)
        reopened.mechanism.motion.stop()
    }

    func testSameShowArtistChangeRequiresCatalogReload() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
        XCTAssertFalse(room.browseArtists.contains { $0.id == "d" })

        show.artists.append(ArtistSlot(name: "D", avatarURL: nil, appleMusicArtistID: "d"))
        container.mainContext.insert(ArtistCatalogSnapshot(artistID: "d", artistName: "D", orderedSongIDs: ["a1"]))
        try container.mainContext.save()

        XCTAssertTrue(room.shouldReloadCatalog(for: show))
        await room.load(show: show)
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
        XCTAssertTrue(room.browseArtists.contains { $0.id == "d" })
        room.mechanism.motion.stop()
    }

    func testManualArtistRematchReturnsBeforeCatalogAndKeepsPlaybackTransport() async throws {
        let (container, show) = try ListenTestData.make()
        let catalog = GatedRematchCatalog()
        let playback = TrackingPlaybackService()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: catalog,
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in playback }
        )
        defer {
            catalog.release()
            room.stop()
            room.mechanism.motion.stop()
        }

        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        room.restoreDisc(disc)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }

        let discID = room.mechanism.disc?.id
        let songID = room.track?.id
        let trackIndex = room.trackIndex
        let prepareCount = playback.prepareCount
        let rematchFinished = expectation(description: "manual rematch saves locally")

        Task {
            await room.rematch(
                slotIndex: 1,
                artist: .init(id: "replacement", canonicalName: "Replacement", avatarURL: nil, appleMusicURL: nil)
            )
            rematchFinished.fulfill()
        }
        await fulfillment(of: [rematchFinished], timeout: 0.5)

        XCTAssertEqual(show.artists[1].appleMusicArtistID, "replacement")
        XCTAssertEqual(room.browseArtists.first { $0.slotIndex == 1 }?.id, "replacement")
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.mechanism.disc?.id, discID)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertEqual(room.trackIndex, trackIndex)
        XCTAssertEqual(playback.prepareCount, prepareCount)
        XCTAssertEqual(playback.pauseCount, 0)
        XCTAssertEqual(playback.stopCount, 0)

        try await waitUntil { catalog.didStartReplacementFetch }
        XCTAssertTrue(room.isPlaying)
        catalog.release()
        try await waitUntil { !room.isCatalogEnriching }
        XCTAssertTrue(room.isPlaying)
        XCTAssertEqual(room.mechanism.disc?.id, discID)
        XCTAssertEqual(room.track?.id, songID)
        XCTAssertEqual(playback.prepareCount, prepareCount)
        XCTAssertEqual(playback.pauseCount, 0)
        XCTAssertEqual(playback.stopCount, 0)
    }

    func testManualArtistRematchDuringInitialLoadJoinsExistingCatalogGeneration() async throws {
        let (container, show) = try ListenTestData.make()
        let catalog = GatedRematchCatalog()
        let search = GatedArtistSearch()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            search.release()
            catalog.release()
            room.stop()
            room.mechanism.motion.stop()
        }

        let loadTask = Task { await room.load(show: show) }
        try await waitUntil { search.didStartSearch }

        let rematchFinished = expectation(description: "manual rematch does not start a competing load")
        Task {
            await room.rematch(
                slotIndex: 1,
                artist: .init(id: "replacement", canonicalName: "Replacement", avatarURL: nil, appleMusicURL: nil)
            )
            rematchFinished.fulfill()
        }
        await fulfillment(of: [rematchFinished], timeout: 0.5)

        XCTAssertEqual(show.artists[1].appleMusicArtistID, "replacement")
        XCTAssertEqual(room.browseArtists.first { $0.slotIndex == 1 }?.id, "replacement")
        XCTAssertFalse(catalog.didStartReplacementFetch)

        catalog.release()
        search.release()
        await loadTask.value

        XCTAssertTrue(catalog.didStartReplacementFetch)
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
        XCTAssertEqual(room.browseArtists.first { $0.slotIndex == 1 }?.id, "replacement")
    }

    func testManualArtistRematchAfterInitialCatalogFetchStartsReloadsChangedIdentity() async throws {
        let (container, show) = try ListenTestData.make()
        let catalog = CatalogStageRaceCatalog()
        let search = CatalogRaceArtistSearch()
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { _ in ListeningFixturePlayer() }
        )
        defer {
            catalog.releaseInitialCatalog()
            room.stop()
            room.mechanism.motion.stop()
        }

        let loadTask = Task { await room.load(show: show, force: true) }
        try await waitUntil { catalog.didStartInitialCatalogFetch }
        let searchCountAfterCatalogStarted = search.searchCount

        let rematchFinished = expectation(description: "catalog-stage rematch still saves locally")
        Task {
            await room.rematch(
                slotIndex: 1,
                artist: .init(id: "replacement", canonicalName: "Replacement", avatarURL: nil, appleMusicURL: nil)
            )
            rematchFinished.fulfill()
        }
        await fulfillment(of: [rematchFinished], timeout: 0.5)

        XCTAssertEqual(show.artists[1].appleMusicArtistID, "replacement")
        XCTAssertEqual(room.browseArtists.first { $0.slotIndex == 1 }?.id, "replacement")
        XCTAssertFalse(catalog.didStartReplacementFetch)
        XCTAssertEqual(search.searchCount, searchCountAfterCatalogStarted)

        catalog.releaseInitialCatalog()
        await loadTask.value

        XCTAssertTrue(catalog.didStartReplacementFetch)
        XCTAssertGreaterThan(catalog.replacementFetchCount, 0)
        XCTAssertTrue(room.catalogSongs.contains { $0.appleMusicSongID == "replacement-song" })
        XCTAssertTrue(room.compilationDiscs.flatMap { $0.tracks }.contains { $0.id == "replacement-song" })
        XCTAssertEqual(room.browseArtists.first { $0.slotIndex == 1 }?.id, "replacement")
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
        XCTAssertEqual(search.searchCount, searchCountAfterCatalogStarted, "catalog catch-up must not rerun artist matching")
    }

    func testFailedPlaybackRetryRebuildsTransport() async throws {
        let (container, show) = try ListenTestData.make()
        var services: [RetryPlaybackService] = []
        let room = ListeningRoomCoordinator(
            context: container.mainContext,
            catalogService: ListeningFixtureCatalog(scenario: .singleFull),
            artistSearchService: ListeningFixtureArtistSearch(),
            playbackFactory: { _ in
                let service = RetryPlaybackService()
                services.append(service)
                return service
            }
        )
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        room.restoreDisc(disc)
        try await ListenTestData.settle(room) { room.track != nil && !room.busy }
        room.playPause()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(services.count, 1)
        services[0].failure = .songUnavailable(try XCTUnwrap(room.track?.id))
        room.tick()
        XCTAssertEqual(room.playbackState, .failed)
        XCTAssertNotNil(room.playbackError)
        services[0].failure = nil
        room.retryCurrentPlayback()
        try await ListenTestData.settle(room) { room.isPlaying && !room.busy }
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[1].prepareCount, 1)
        room.stop(); room.mechanism.motion.stop()
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true")
    }
}

private final class GatedRematchCatalog: @unchecked Sendable, ListeningMusicCatalogServicing {
    private let lock = NSLock()
    private var released = false
    private var replacementFetchStarted = false

    var didStartReplacementFetch: Bool { lock.withLock { replacementFetchStarted } }

    func release() {
        lock.withLock { released = true }
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        guard artistID == "replacement" else { return [] }
        try await waitForRelease()
        return [replacementSong]
    }

    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        guard artistID == "replacement" else { throw ListeningCatalogError.artistNotFound(artistID) }
        try await waitForRelease()
        return ListeningArtistCatalogPayload(
            artistID: artistID,
            artistName: "Replacement",
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: [replacementSong.songID],
            topSongIDs: [replacementSong.songID],
            albumIDs: [],
            songs: [replacementSong],
            albums: [],
            fetchedAt: fetchedAt
        )
    }

    private var replacementSong: ListeningCatalogSongPayload {
        .init(
            songID: "replacement-song",
            title: "Replacement Song",
            artistName: "Replacement",
            albumID: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: 180,
            performerArtistIDs: ["replacement"],
            performerArtistNames: ["Replacement"],
            previewURL: nil
        )
    }

    private func waitForRelease() async throws {
        lock.withLock { replacementFetchStarted = true }
        while !lock.withLock({ released }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class GatedArtistSearch: @unchecked Sendable, ArtistSearchServicing {
    private let lock = NSLock()
    private var released = false
    private var started = false

    var didStartSearch: Bool { lock.withLock { started } }

    func release() {
        lock.withLock { released = true }
    }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        lock.withLock { started = true }
        while !lock.withLock({ released }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        return []
    }
}

private final class CatalogStageRaceCatalog: @unchecked Sendable, ListeningMusicCatalogServicing {
    private let lock = NSLock()
    private var initialCatalogReleased = false
    private var initialCatalogFetchStarted = false
    private var replacementFetches = 0

    var didStartInitialCatalogFetch: Bool { lock.withLock { initialCatalogFetchStarted } }
    var replacementFetchCount: Int { lock.withLock { replacementFetches } }
    var didStartReplacementFetch: Bool { replacementFetchCount > 0 }

    func releaseInitialCatalog() {
        lock.withLock { initialCatalogReleased = true }
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess {
        .init(authorizationStatus: .authorized, canPlayCatalogContent: true)
    }

    func fetchRuntimeSongs(artistID: String) async throws -> [ListeningCatalogSongPayload] {
        guard artistID == "replacement" else { return [] }
        lock.withLock { replacementFetches += 1 }
        return [replacementSong]
    }

    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        if artistID == "replacement" {
            lock.withLock { replacementFetches += 1 }
            return replacementPayload(fetchedAt: fetchedAt)
        }

        lock.withLock { initialCatalogFetchStarted = true }
        while !lock.withLock({ initialCatalogReleased }) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ListeningCatalogError.artistNotFound(artistID)
    }

    private var replacementSong: ListeningCatalogSongPayload {
        .init(
            songID: "replacement-song",
            title: "Replacement Song",
            artistName: "Replacement",
            albumID: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: 180,
            performerArtistIDs: ["replacement"],
            performerArtistNames: ["Replacement"],
            previewURL: nil
        )
    }

    private func replacementPayload(fetchedAt: Date) -> ListeningArtistCatalogPayload {
        ListeningArtistCatalogPayload(
            artistID: "replacement",
            artistName: "Replacement",
            artworkURL: nil,
            editorialText: nil,
            genreNames: [],
            orderedSongIDs: [replacementSong.songID],
            topSongIDs: [replacementSong.songID],
            albumIDs: [],
            songs: [replacementSong],
            albums: [],
            fetchedAt: fetchedAt
        )
    }
}

private final class CatalogRaceArtistSearch: @unchecked Sendable, ArtistSearchServicing {
    private let lock = NSLock()
    private var searches = 0

    var searchCount: Int { lock.withLock { searches } }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        lock.withLock { searches += 1 }
        return []
    }
}

private enum LifecycleEvidencePersistenceTestError: Error {
    case expectedFailure
}

@MainActor
private final class LifecyclePendingPlaybackService: ListeningPlaybackServicing {
    private var items: [ListeningPlaybackItem] = []
    private var index = 0
    private var source: ListeningPlaybackSource = .fullCatalog
    private var playing = false
    var currentTime: TimeInterval = 0
    private(set) var didStop = false

    func prepare(
        items: [ListeningPlaybackItem],
        source: ListeningPlaybackSource,
        startingAtSongID: String?
    ) async throws {
        guard !items.isEmpty else { throw ListeningPlaybackError.emptyQueue }
        self.items = items
        self.source = source
        index = startingAtSongID.flatMap { id in
            items.firstIndex(where: { $0.songID == id })
        } ?? 0
        currentTime = 0
        playing = false
        didStop = false
    }

    func play() async throws {
        playing = true
    }

    func pause() {
        playing = false
    }

    func setPlayingExternally(_ value: Bool) {
        playing = value
    }

    func skipToNext() async throws {
        guard index + 1 < items.count else { throw ListeningPlaybackError.queueBoundary }
        index += 1
        currentTime = 0
    }

    func skipToPrevious() async throws {
        guard index > 0 else { throw ListeningPlaybackError.queueBoundary }
        index -= 1
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        currentTime = time
    }

    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        return ListeningPlaybackSample(
            songID: item.songID,
            source: source,
            currentTime: currentTime,
            duration: item.duration,
            isPlaying: playing,
            observedAt: observedAt
        )
    }

    func stop() {
        didStop = true
        playing = false
        items = []
        index = 0
        currentTime = 0
    }
}

@MainActor
private final class TrackingPlaybackService: ListeningPlaybackServicing {
    private let player = ListeningFixturePlayer()
    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0

    func prepare(items: [ListeningPlaybackItem], source: ListeningPlaybackSource, startingAtSongID: String?) async throws {
        prepareCount += 1
        try await player.prepare(items: items, source: source, startingAtSongID: startingAtSongID)
    }
    func play() async throws {
        playCount += 1
        try await player.play()
    }
    func pause() {
        pauseCount += 1
        player.pause()
    }
    func stop() {
        stopCount += 1
        player.stop()
    }
    func seek(to time: TimeInterval) { player.seek(to: time) }
    func skipToNext() async throws { try await player.skipToNext() }
    func skipToPrevious() async throws { try await player.skipToPrevious() }
    func snapshot(observedAt: Date) -> ListeningPlaybackSample? { player.snapshot(observedAt: observedAt) }
}

@MainActor
private final class RetryPlaybackService: ListeningPlaybackServicing {
    var failure: ListeningPlaybackError?
    private(set) var prepareCount = 0
    private let player = ListeningFixturePlayer()
    func prepare(items: [ListeningPlaybackItem], source: ListeningPlaybackSource, startingAtSongID: String?) async throws {
        prepareCount += 1
        try await player.prepare(items: items, source: source, startingAtSongID: startingAtSongID)
    }
    func play() async throws { try await player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
    func seek(to time: TimeInterval) { player.seek(to: time) }
    func skipToNext() async throws { try await player.skipToNext() }
    func skipToPrevious() async throws { try await player.skipToPrevious() }
    func snapshot(observedAt: Date) -> ListeningPlaybackSample? { player.snapshot(observedAt: observedAt) }
}
