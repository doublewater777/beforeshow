import SwiftData
import XCTest
@testable import BeforeShow

@MainActor final class ListeningMVPTests: XCTestCase {
    func testAlbumsAreMultiTrackContainersAndHonorTrackOrder() {
        let songs = [CatalogSong(appleMusicSongID: "a", title: "A", artistName: "Artist"),
                     CatalogSong(appleMusicSongID: "b", title: "B", artistName: "Artist")]
        let album = CatalogAlbum(appleMusicAlbumID: "album", title: "Album", orderedTrackIDs: ["b", "a"])
        let discs = ListeningDiscAssembler.discs(albums: [album], songs: songs)
        XCTAssertEqual(discs.count, 1)
        XCTAssertEqual(discs[0].tracks.map(\.id), ["b", "a"])
    }
    func testAlbumMetadataIsCarriedToItsDisc() {
        let song = CatalogSong(appleMusicSongID: "song", title: "Song", artistName: "Artist")
        let album = CatalogAlbum(
            appleMusicAlbumID: "album", title: "Album", artistNames: ["Artist"],
            editorialText: "Editorial", genreNames: ["Pop"], recordLabelName: "Label",
            contentRatingRawValue: "explicit", audioVariantRawValues: ["lossless"],
            isAppleDigitalMaster: true, appleMusicURL: "https://music.apple.com/example",
            orderedTrackIDs: ["song"]
        )

        let disc = ListeningDiscAssembler.discs(albums: [album], songs: [song])[0]

        XCTAssertEqual(disc.artistNames, ["Artist"])
        XCTAssertEqual(disc.editorialText, "Editorial")
        XCTAssertEqual(disc.genreNames, ["Pop"])
        XCTAssertEqual(disc.recordLabelName, "Label")
        XCTAssertEqual(disc.contentRatingRawValue, "explicit")
        XCTAssertEqual(disc.audioVariantRawValues, ["lossless"])
        XCTAssertTrue(disc.isAppleDigitalMaster == true)
        XCTAssertEqual(disc.appleMusicURL, URL(string: "https://music.apple.com/example"))
    }
    func testAutomaticSwapUsesEveryMechanicalStep() async throws {
        let mechanism = CDMechanism()
        var steps: [String] = []
        mechanism.onTransition = { steps.append($0) }
        let first = ListeningDisc(id: "a", title: "A", artworkURL: nil, tracks: [])
        let second = ListeningDisc(id: "b", title: "B", artworkURL: nil, tracks: [])
        // Drive analytic spring channels directly so the test has no screen or
        // CADisplayLink dependency and still waits for physical convergence.
        let clock = Task { @MainActor in
            while !Task.isCancelled {
                mechanism.motion.lid.step(1)
                mechanism.motion.discX.step(1); mechanism.motion.discY.step(1)
                mechanism.motion.lift.step(1); mechanism.motion.discScale.step(1)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { clock.cancel() }
        try await mechanism.load(first)
        steps = []
        try await mechanism.load(second)
        XCTAssertEqual(steps, ["open", "remove", "store", "insert", "seat", "close"])
        XCTAssertEqual(mechanism.position, .seated)
        XCTAssertTrue(mechanism.isClosed)
        XCTAssertEqual(mechanism.disc?.id, "b")
    }
    func testSpringGrabKeepsPresentationAngle() async throws {
        let mechanism = CDMechanism()
        mechanism.motion.lid.value = 0.42; mechanism.motion.lid.target = 1
        mechanism.dragLid(0)
        XCTAssertEqual(mechanism.motion.lid.value, 0.42, accuracy: 0.000001)
        XCTAssertNil(mechanism.motion.lid.target)
    }
    func testManualCabinetDragSeatsAndReturnsTheSameDisc() {
        let mechanism = CDMechanism()
        let disc = ListeningDisc(id: "manual", title: "Manual", artworkURL: nil, tracks: [])
        let slot = CGPoint(x: 90, y: 940)
        let center = mechanism.configuration.geometry.discCenter
        mechanism.cabinetSlots[disc.id] = slot
        mechanism.cabinetDropZone = CGRect(x: 0, y: 850, width: 460, height: 200)
        mechanism.motion.lid.value = 1
        mechanism.beginCabinetDrag(disc)
        mechanism.dragDisc(CGSize(width: center.x - slot.x, height: center.y - slot.y))
        mechanism.endDiscDrag()
        settle(mechanism)
        XCTAssertEqual(mechanism.position, .seated)
        XCTAssertFalse(mechanism.isCabinetDragging)
        mechanism.dragDisc(CGSize(width: slot.x - center.x, height: slot.y - center.y))
        mechanism.endDiscDrag()
        XCTAssertTrue(mechanism.isReturning)
        settle(mechanism)
        mechanism.refresh()
        XCTAssertEqual(mechanism.position, .stored)
        XCTAssertEqual(mechanism.disc?.id, disc.id)
        XCTAssertEqual(mechanism.motion.discX.value, slot.x, accuracy: 0.001)
        XCTAssertEqual(mechanism.motion.discY.value, slot.y, accuracy: 0.001)
    }
    func testCabinetTapUsesSameVisiblePathIntoOpenTray() {
        let mechanism = CDMechanism()
        let disc = ListeningDisc(id: "tap", title: "Tap", artworkURL: nil, tracks: [])
        mechanism.motion.lid.value = 1
        mechanism.cabinetSlots[disc.id] = CGPoint(x: 90, y: 940)
        mechanism.takeFromCabinet(disc)
        settle(mechanism)
        XCTAssertEqual(mechanism.position, .seated)
        XCTAssertEqual(mechanism.motion.discX.value, mechanism.configuration.geometry.discCenter.x, accuracy: 0.001)
        XCTAssertEqual(mechanism.motion.discY.value, mechanism.configuration.geometry.discCenter.y, accuracy: 0.001)
    }
    func testCabinetMissReturnsDiscAndOpenSeatedDiscCanBeDragged() {
        let mechanism = CDMechanism()
        let disc = ListeningDisc(id: "manual", title: "Manual", artworkURL: nil, tracks: [])
        mechanism.motion.lid.value = 1
        mechanism.beginCabinetDrag(disc)
        mechanism.dragDisc(CGSize(width: -900, height: -900))
        mechanism.endDiscDrag()
        XCTAssertTrue(mechanism.isReturning)
        settle(mechanism)
        mechanism.refresh()
        XCTAssertEqual(mechanism.position, .stored)
        mechanism.beginCabinetDrag(disc)
        mechanism.dragDisc(CGSize(width: mechanism.configuration.geometry.discCenter.x - mechanism.motion.discX.value,
                                  height: mechanism.configuration.geometry.discCenter.y - mechanism.motion.discY.value))
        mechanism.endDiscDrag()
        settle(mechanism)
        mechanism.setLid(open: true)
        settle(mechanism)
        mechanism.dragDisc(CGSize(width: 100, height: 100))
        mechanism.endDiscDrag()
        settle(mechanism)
        XCTAssertEqual(mechanism.position, .removed)
        XCTAssertEqual(mechanism.motion.discX.value, mechanism.configuration.geometry.parkedDisc.x, accuracy: 0.001)
        XCTAssertEqual(mechanism.motion.discY.value, mechanism.configuration.geometry.parkedDisc.y, accuracy: 0.001)
    }
    func testCabinetLongPressOpensLidAndAcceptsDropBeforeItFinishesOpening() {
        let mechanism = CDMechanism()
        let disc = ListeningDisc(id: "fast", title: "Fast", artworkURL: nil, tracks: [])
        let slot = CGPoint(x: 90, y: 120)
        let center = mechanism.configuration.geometry.discCenter
        mechanism.cabinetSlots[disc.id] = slot

        XCTAssertTrue(mechanism.beginCabinetDrag(disc))
        XCTAssertEqual(mechanism.motion.lid.target, 1)
        mechanism.dragDisc(CGSize(width: center.x - slot.x, height: center.y - slot.y))
        mechanism.endDiscDrag()
        settle(mechanism)

        XCTAssertEqual(mechanism.position, .seated)
        XCTAssertTrue(mechanism.isOpen)
    }
    func testFastDropCannotBeInterruptedByClosingLid() {
        let mechanism = CDMechanism()
        let disc = ListeningDisc(id: "fast", title: "Fast", artworkURL: nil, tracks: [])
        let slot = CGPoint(x: 90, y: 120)
        let center = mechanism.configuration.geometry.discCenter
        mechanism.cabinetSlots[disc.id] = slot

        mechanism.beginCabinetDrag(disc)
        mechanism.dragDisc(CGSize(width: center.x - slot.x, height: center.y - slot.y))
        mechanism.endDiscDrag()
        mechanism.setLid(open: false)
        mechanism.dragLid(100)

        XCTAssertEqual(mechanism.motion.lid.target, 1)
        settle(mechanism)
        XCTAssertEqual(mechanism.position, .seated)
        XCTAssertTrue(mechanism.isOpen)
    }
    func testOccupiedPlayerRejectsAnotherCabinetDisc() {
        let mechanism = CDMechanism()
        let current = ListeningDisc(id: "current", title: "Current", artworkURL: nil, tracks: [])
        let replacement = ListeningDisc(id: "replacement", title: "Replacement", artworkURL: nil, tracks: [])
        mechanism.restoreSeated(current)

        XCTAssertFalse(mechanism.beginCabinetDrag(replacement))
        XCTAssertEqual(mechanism.disc?.id, current.id)
        XCTAssertEqual(mechanism.occupiedAttemptCount, 1)
    }
    func testAutomaticSwapDoesNotCarryOldDiscRotationIntoReplacement() async throws {
        let mechanism = CDMechanism()
        let first = ListeningDisc(id: "a", title: "A", artworkURL: nil, tracks: [])
        let second = ListeningDisc(id: "b", title: "B", artworkURL: nil, tracks: [])
        mechanism.restoreSeated(first)
        mechanism.motion.discAngle = 137
        let clock = Task { @MainActor in
            while !Task.isCancelled {
                mechanism.motion.lid.step(1)
                mechanism.motion.discX.step(1); mechanism.motion.discY.step(1)
                mechanism.motion.lift.step(1); mechanism.motion.discScale.step(1)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { clock.cancel() }

        try await mechanism.load(second)

        XCTAssertEqual(mechanism.disc?.id, second.id)
        XCTAssertEqual(mechanism.motion.discAngle, 0, accuracy: 0.001)
    }
    private func settle(_ mechanism: CDMechanism) {
        for _ in 0..<20 {
            mechanism.motion.lid.step(1)
            mechanism.motion.discX.step(1); mechanism.motion.discY.step(1)
            mechanism.motion.lift.step(1); mechanism.motion.discScale.step(1)
            mechanism.refresh()
        }
    }
    func testListeningIsThirdTabAndOnboardingSecondStep() {
        XCTAssertEqual(BeforeShowTab.allCases, [.current, .listen, .footprints])
        XCTAssertEqual(OnboardingPage.allCases[1], .listening)
    }
}

@MainActor final class ListeningRoomPlaybackTests: XCTestCase {
    func testPreviewContinuesWithinDiscAndStopsAtLastTrackWithoutEvidence() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Fixture", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        context.insert(show)
        for id in ["a", "b"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist", duration: 1,
                                      previewURL: "https://example.invalid/\(id).m4a"))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist", orderedSongIDs: ["a", "b"], topSongIDs: ["a", "b"]))
        try context.save()
        let service = ListeningMVPPlaybackStub()
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningMVPCatalogStub(), playbackFactory: { _ in service })
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        let clock = Task { @MainActor in
            while !Task.isCancelled {
                let motion = room.mechanism.motion
                motion.lid.step(1); motion.discX.step(1); motion.discY.step(1); motion.lift.step(1); motion.discScale.step(1)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { clock.cancel(); room.setActive(false) }
        room.loadDisc(disc)
        try await wait { room.mechanism.isClosed && room.mechanism.hasDisc && !room.busy }
        try await wait { room.isPlaying }
        XCTAssertEqual(service.source, .preview)
        service.ended = true
        room.tick()
        try await wait { room.trackIndex == 1 && room.isPlaying && !room.busy }
        XCTAssertEqual(service.preparedIDs, ["a", "b"])
        service.ended = true
        room.tick()
        XCTAssertEqual(room.trackIndex, 1)
        XCTAssertFalse(room.isPlaying)
        XCTAssertEqual(room.mechanism.disc?.id, disc.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 0)
        room.skip(1)
        XCTAssertEqual(room.trackIndex, 1)
        show.artists[0].appleMusicArtistID = "replacement-artist"
        await room.load(show: show)
        try await wait { room.mechanism.position == .stored && !room.busy }
        XCTAssertFalse(room.mechanism.hasDisc)
        XCTAssertFalse(room.isPlaying)
    }
    func testSelectingAnotherTrackOnTheSeatedDiscDoesNotReloadMechanically() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Fixture", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        context.insert(show)
        for id in ["a", "b"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: "Artist", duration: 1,
                                      previewURL: "https://example.invalid/\(id).m4a"))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist", orderedSongIDs: ["a", "b"], topSongIDs: ["a", "b"]))
        try context.save()
        let service = ListeningMVPPlaybackStub()
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningMVPCatalogStub(), playbackFactory: { _ in service })
        await room.load(show: show)
        let disc = try XCTUnwrap(room.discs.first)
        var steps: [String] = []
        room.mechanism.onTransition = { steps.append($0) }
        let clock = Task { @MainActor in
            while !Task.isCancelled {
                let motion = room.mechanism.motion
                motion.lid.step(1); motion.discX.step(1); motion.discY.step(1); motion.lift.step(1); motion.discScale.step(1)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { clock.cancel(); room.setActive(false) }
        room.loadDisc(disc, songID: "a", autoplay: true)
        try await wait { room.mechanism.isClosed && room.mechanism.hasDisc && room.isPlaying && !room.busy }
        steps = []
        room.loadDisc(disc, songID: "b", autoplay: true)
        try await wait { room.trackIndex == 1 && room.isPlaying && !room.busy }
        XCTAssertEqual(steps, [])
        XCTAssertEqual(room.mechanism.position, .seated)
        XCTAssertTrue(room.mechanism.isClosed)
        XCTAssertEqual(room.mechanism.disc?.id, disc.id)
        XCTAssertEqual(service.preparedIDs, ["a", "b"])
    }
    func testSwitchingDiscsWhilePlayingStopsOldTrackAndStartsReplacementAfterAnimation() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let now = Date()
        let show = try Show(name: "Fixture", date: now, startTime: now)
        show.artists = [ArtistSlot(name: "Artist", avatarURL: nil, appleMusicArtistID: "artist")]
        context.insert(show)
        let songA = CatalogSong(appleMusicSongID: "a", title: "a", artistName: "Artist", duration: 1,
                                previewURL: "https://example.invalid/a.m4a")
        let songB = CatalogSong(appleMusicSongID: "b", title: "b", artistName: "Artist", duration: 1,
                                previewURL: "https://example.invalid/b.m4a")
        context.insert(songA)
        context.insert(songB)
        context.insert(ArtistCatalogSnapshot(artistID: "artist", artistName: "Artist", orderedSongIDs: ["a", "b"], topSongIDs: ["a", "b"]))
        try context.save()
        let service = ListeningMVPPlaybackStub()
        let room = ListeningRoomCoordinator(context: context, catalogService: ListeningMVPCatalogStub(), playbackFactory: { _ in service })
        await room.load(show: show)
        let first = ListeningDisc(id: "first", title: "First", artworkURL: nil,
                                  tracks: [ListeningDiscTrack(songA)])
        let second = ListeningDisc(id: "second", title: "Second", artworkURL: nil,
                                   tracks: [ListeningDiscTrack(songB)])
        var steps: [String] = []
        room.mechanism.onTransition = { steps.append($0) }
        let clock = Task { @MainActor in
            while !Task.isCancelled {
                let motion = room.mechanism.motion
                motion.lid.step(1); motion.discX.step(1); motion.discY.step(1); motion.lift.step(1); motion.discScale.step(1)
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        defer { clock.cancel(); room.setActive(false) }

        room.loadDisc(first)
        try await wait { room.mechanism.disc?.id == first.id && room.isPlaying && !room.busy }
        room.mechanism.motion.discAngle = 137
        steps = []

        room.loadDisc(second)
        try await wait { room.mechanism.disc?.id == second.id && room.isPlaying && !room.busy }

        XCTAssertEqual(steps, ["open", "remove", "store", "insert", "seat", "close"])
        XCTAssertEqual(service.preparedIDs, ["a", "b"])
        XCTAssertEqual(room.mechanism.motion.discAngle, 0, accuracy: 0.001)
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for the listening transition")
    }
}

private struct ListeningMVPCatalogStub: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { ListeningMusicAccess(authorizationStatus: .authorized, canPlayCatalogContent: false) }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}

@MainActor private final class ListeningMVPPlaybackStub: ListeningPlaybackServicing {
    var source = ListeningPlaybackSource.preview
    var item: ListeningPlaybackItem?
    var playing = false
    var ended = false
    var preparedIDs: [String] = []
    func prepare(items: [ListeningPlaybackItem], source: ListeningPlaybackSource, startingAtSongID: String?) async throws {
        self.source = source; item = items.first; ended = false
        preparedIDs += items.map(\.songID)
    }
    func play() async throws { playing = true }
    func pause() { playing = false }
    func skipToNext() async throws { throw ListeningPlaybackError.queueBoundary }
    func skipToPrevious() async throws { throw ListeningPlaybackError.queueBoundary }
    func seek(to time: TimeInterval) {}
    func snapshot(observedAt: Date) -> ListeningPlaybackSample? {
        guard let item else { return nil }
        return ListeningPlaybackSample(songID: item.songID, source: source, currentTime: ended ? 1 : 0, duration: 1,
                                       isPlaying: playing && !ended, observedAt: observedAt, hasEnded: ended)
    }
    func stop() { item = nil; playing = false; ended = false }
}
