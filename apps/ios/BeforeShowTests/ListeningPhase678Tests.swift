import Foundation
import XCTest
import SwiftData
@testable import BeforeShow

@MainActor enum ListenTestData {
    static func make(ended: Bool = false) throws -> (ModelContainer, Show) {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(ended ? -10000 : 10000)
        let show = try Show(name: "Test Show", date: start, startTime: start)
        if ended { show.endedAt = start.addingTimeInterval(100) }
        show.artists = [ArtistSlot(name: "A", avatarURL: nil, appleMusicArtistID: "a"),
                        ArtistSlot(name: "B", avatarURL: nil), ArtistSlot(name: "C", avatarURL: nil, appleMusicArtistID: "c")]
        context.insert(show)
        for id in ["a1", "a2", "c1"] {
            context.insert(CatalogSong(appleMusicSongID: id, title: id, artistName: String(id.prefix(1)), duration: 100))
        }
        context.insert(ArtistCatalogSnapshot(artistID: "a", artistName: "A", orderedSongIDs: ["a1", "a2"], topSongIDs: ["a2"], albumIDs: ["album"]))
        context.insert(ArtistCatalogSnapshot(artistID: "c", artistName: "C", orderedSongIDs: ["c1"]))
        context.insert(CatalogAlbum(appleMusicAlbumID: "album", title: "Album", artistIDs: ["a"], orderedTrackIDs: ["a2", "a1"]))
        try context.save()
        return (container, show)
    }
    static func room(_ context: ModelContext) -> ListeningRoomCoordinator {
        ListeningRoomCoordinator(context: context, catalogService: ListenTestCatalog(), artistSearchService: ListeningFixtureArtistSearch(), playbackFactory: { _ in ListeningFixturePlayer() })
    }
    static func settle(_ room: ListeningRoomCoordinator, until condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            let m = room.mechanism.motion
            m.lid.step(1); m.discX.step(1); m.discY.step(1); m.lift.step(1); m.discScale.step(1)
            room.mechanism.refresh()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Physical operation did not settle")
    }
}
private struct ListenTestCatalog: ListeningMusicCatalogServicing {
    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { .authorized }
    func requestAuthorization() async -> ListeningMusicAuthorizationStatus { .authorized }
    func currentAccess() async -> ListeningMusicAccess { .init(authorizationStatus: .authorized, canPlayCatalogContent: true) }
    func fetchArtistCatalog(artistID: String, fetchedAt: Date) async throws -> ListeningArtistCatalogPayload { throw ListeningCatalogError.artistNotFound(artistID) }
}

private final class AuthorizationTransitionCatalog: @unchecked Sendable, ListeningMusicCatalogServicing {
    private let lock = NSLock()
    private var status: ListeningMusicAuthorizationStatus = .notDetermined

    private func readStatus() -> ListeningMusicAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    private func setStatus(_ value: ListeningMusicAuthorizationStatus) {
        lock.lock()
        status = value
        lock.unlock()
    }

    func currentAuthorizationStatus() -> ListeningMusicAuthorizationStatus { readStatus() }

    func requestAuthorization() async -> ListeningMusicAuthorizationStatus {
        setStatus(.authorized)
        return .authorized
    }

    func currentAccess() async -> ListeningMusicAccess {
        let current = readStatus()
        return .init(
            authorizationStatus: current,
            canPlayCatalogContent: current == .authorized
        )
    }

    func fetchArtistCatalog(
        artistID: String,
        fetchedAt: Date
    ) async throws -> ListeningArtistCatalogPayload {
        throw ListeningCatalogError.artistNotFound(artistID)
    }
}

private final class CountingArtistSearchService: @unchecked Sendable, ArtistSearchServicing {
    private let lock = NSLock()
    private var searches = 0

    private func recordSearch() {
        lock.lock()
        searches += 1
        lock.unlock()
    }

    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return searches
    }

    func searchArtists(query: String) async throws -> [RecognizedArtist] {
        recordSearch()
        return []
    }

    func requestAuthorizationIfNeeded() async -> ArtistSearchAuthorizationStatus { .authorized }
}

final class NavigationTests: XCTestCase {
    func testThreeTabsOrder() { XCTAssertEqual(BeforeShowTab.allCases, [.current, .listen, .footprints]) }

}
final class ListeningPresentationTests: XCTestCase {
    func testCacheAlwaysRemainsBrowsable() {
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: false, connected: true, hasSongs: true, loading: false, failed: false), .ready)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: true, hasSongs: true, loading: false, failed: true), .cachedWithError)
    }
    func testUnavailableStates() {
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: false, connected: true, hasSongs: false, loading: true, failed: false, accessResolved: false), .loading)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: false, authorized: false, connected: false, hasSongs: false, loading: false, failed: false), .noCurrentShow)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: false, connected: true, hasSongs: false, loading: false, failed: false), .needsAuthorization)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: false, hasSongs: false, loading: false, failed: false), .noConnectedArtists)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: true, hasSongs: false, loading: true, failed: false), .loadingCatalog)
        XCTAssertEqual(ListeningPresentation.resolve(hasShow: true, authorized: true, connected: true, hasSongs: false, loading: false, failed: true), .fatalUnavailable)
    }
    @MainActor func testEveryFixtureIsIsolatedAndReproducible() throws {
        for scenario in ListeningFixtureScenario.allCases {
            let fixture = try ListeningDebugFixtures(scenario: scenario)
            let count = try fixture.container.mainContext.fetchCount(FetchDescriptor<Show>())
            XCTAssertEqual(count, scenario == .noCurrent ? 0 : 1)
        }
    }
}
final class ListeningAccessibilityTests: XCTestCase {
    func testUserPauseNeverResumesFromLifecycle() {
        var policy = ListeningVisibilityPolicy()
        policy.interrupt(wasPlaying: true)
        XCTAssertTrue(policy.resumeIfAllowed())
        policy.userPause(); policy.interrupt(wasPlaying: true)
        XCTAssertFalse(policy.resumeIfAllowed())
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: true, foreground: false, source: .fullCatalog))
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: true, foreground: false, source: .preview))
        XCTAssertFalse(ListeningVisibilityPolicy.mustPause(tabVisible: false, foreground: true, source: .fullCatalog))
    }
    func testDiscRotationRunsOnCoreAnimationInsteadOfMechanicalDisplayLink() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BeforeShow")
        let machine = try String(
            contentsOf: sourceRoot.appendingPathComponent("Features/Listening/Views/ListeningMachineView.swift"),
            encoding: .utf8
        )
        let motion = try String(
            contentsOf: sourceRoot.appendingPathComponent("Features/Listening/Player/CDMotionDriver.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: sourceRoot.appendingPathComponent("UI/DesignSystem/BSListeningTokens.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(machine.contains(#"CABasicAnimation(keyPath: "transform.rotation.z")"#))
        XCTAssertTrue(machine.contains("animation.repeatCount = .infinity"))
        XCTAssertTrue(machine.contains("isRotating: isPlaying && !motion.reducedMotion"))
        XCTAssertTrue(machine.contains("CACurrentMediaTime()"))
        XCTAssertFalse(motion.contains("discAngle"))
        XCTAssertFalse(motion.contains("discSpin"))
        XCTAssertFalse(motion.contains("var spinning"))
        XCTAssertTrue(tokens.contains("static let discRotationRPM = 20.0"))
    }

    func testDiscWellAndCenterGeometryAreIndependentAndTokenized() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BeforeShow")
        let machine = try String(
            contentsOf: sourceRoot.appendingPathComponent("Features/Listening/Views/ListeningMachineView.swift"),
            encoding: .utf8
        )
        let style = try String(
            contentsOf: sourceRoot.appendingPathComponent("Features/Listening/Views/ListeningStyle.swift"),
            encoding: .utf8
        )
        let config = try String(
            contentsOf: sourceRoot.appendingPathComponent("Features/Listening/Player/CDPlayerConfiguration.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: sourceRoot.appendingPathComponent("UI/DesignSystem/BSListeningTokens.swift"),
            encoding: .utf8
        )
        let discWell = sourceRoot
            .appendingPathComponent("Resources/ListeningPlayer.xcassets/listen_01b_disc_well.imageset")
        let discWellContents = try String(
            contentsOf: discWell.appendingPathComponent("Contents.json"),
            encoding: .utf8
        )

        XCTAssertTrue(config.contains(#"var discWell = "listen_01b_disc_well""#))
        XCTAssertTrue(machine.contains("CDPlayerDiscWellView"))
        XCTAssertTrue(machine.contains("CDPlayerBodyShellView"))
        XCTAssertTrue(machine.contains(".luminanceToAlpha()"))
        XCTAssertTrue(config.contains("var discWellDiameter: CGFloat = 364"))
        XCTAssertTrue(machine.contains("frame(width: geometry.discWellDiameter, height: geometry.discWellDiameter)"))
        XCTAssertTrue(machine.contains("geometry.projectedY(geometry.discCenter.y)"))
        XCTAssertTrue(machine.contains("geometry.discDiameter * BSListeningTokens.discSpindleRadiusFraction * 2"))
        XCTAssertTrue(style.contains("size * BSListeningTokens.discHubRadiusFraction"))
        XCTAssertTrue(tokens.contains("static let discHubRadiusFraction: CGFloat = 0.0625"))
        XCTAssertTrue(tokens.contains("static let discSpindleRadiusFraction: CGFloat = 0.025"))
        XCTAssertTrue(discWellContents.contains("01b_disc_well.svg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: discWell.appendingPathComponent("01b_disc_well.svg").path))
        let discWellSVG = try String(
            contentsOf: discWell.appendingPathComponent("01b_disc_well.svg"),
            encoding: .utf8
        )
        XCTAssertEqual(discWellSVG.components(separatedBy: "<circle ").count - 1, 1)
        XCTAssertFalse(discWellSVG.contains("r=\"18\""))
        XCTAssertFalse(discWellSVG.contains("r=\"8\""))
        XCTAssertFalse(machine.contains("ListeningTrayLight("))
        XCTAssertFalse(tokens.contains("trayRingWidth"))
    }

    func testAccessibleActionsAndReducedMotionRemainWired() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow/Features/Listening")
        let source = try String(contentsOf: root.appendingPathComponent("Views/ListeningRoomView.swift"), encoding: .utf8)
        let header = try String(contentsOf: root.appendingPathComponent("Views/ListeningRoomHeader.swift"), encoding: .utf8)
        let room = try XCTUnwrap(source.components(separatedBy: "struct ListeningRoomView: View").last)
        XCTAssertTrue(room.contains("accessibilityReduceMotion"))
        XCTAssertTrue(room.contains("motion.reducedMotion = value"))
        XCTAssertTrue(header.contains(".font(BSFont.pageTitle)"))
        XCTAssertTrue(header.contains(#"Text(BSLocalization.text("听"))"#))
        XCTAssertFalse(room.contains("Text(show.name)"))
        XCTAssertFalse(room.contains(#"accessibilityIdentifier("listening.discTracks")"#))
        XCTAssertFalse(room.contains("paintpalette"))
        XCTAssertTrue(header.contains(".accessibilityAddTraits(.isHeader)"))
        XCTAssertTrue(room.contains(".padding(.horizontal, BSSpacing.roomy)"))
        XCTAssertTrue(header.contains(".padding(.top, BSLayout.pageHeaderTopPadding)"))
        XCTAssertFalse(room.contains(".padding(BSSpacing.lg)"))
        XCTAssertFalse(room.contains(".select(showID:"))
        XCTAssertFalse(room.contains("AddShowCoordinatorSheet"))
        XCTAssertFalse(room.contains(#"Menu(BSLocalization.text("选择现场"))"#))
        let sheet = try String(contentsOf: root.appendingPathComponent("Views/ListeningCabinetSheet.swift"), encoding: .utf8)
        XCTAssertTrue(sheet.contains("LazyVGrid(columns: gridColumns"))
        XCTAssertTrue(sheet.contains("count: 2"), "The record cabinet uses two columns to keep covers and titles readable")
        XCTAssertFalse(sheet.contains("JewelCaseShelf"))
    }
}

@MainActor final class ListeningLoadingPipelineTests: XCTestCase {
    func testAuthorizationContinuesCatalogWithoutRepeatingArtistMatching() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(10_000)
        let show = try Show(name: "First Show", date: start, startTime: start)
        show.artists = [ArtistSlot(name: "Unmatched Artist", avatarURL: nil)]
        context.insert(show)
        try context.save()

        let catalog = AuthorizationTransitionCatalog()
        let search = CountingArtistSearchService()
        let room = ListeningRoomCoordinator(
            context: context,
            catalogService: catalog,
            artistSearchService: search,
            playbackFactory: { _ in ListeningFixturePlayer() }
        )

        await room.load(show: show)
        XCTAssertEqual(search.searchCount, 1)
        XCTAssertFalse(room.shouldReloadCatalog(for: show), "An empty but completed first load must not restart on every tab activation")

        await room.authorize()
        XCTAssertEqual(search.searchCount, 1, "Authorization should resume catalog loading instead of restarting show preparation")
        XCTAssertFalse(room.shouldReloadCatalog(for: show))
    }

    func testImportedArtistAutoMatchRequiresOneExactIdentity() {
        let exact = RecognizedArtist(id: "1", canonicalName: "Beyoncé", avatarURL: nil, appleMusicURL: nil)
        let fuzzy = RecognizedArtist(id: "2", canonicalName: "Beyoncé Live", avatarURL: nil, appleMusicURL: nil)
        XCTAssertEqual(
            ShowDraftArtistAutoMatchPolicy.uniqueExactMatch(for: "  Beyonce ", among: [fuzzy, exact])?.id,
            "1"
        )

        let collision = RecognizedArtist(id: "3", canonicalName: "Beyonce", avatarURL: nil, appleMusicURL: nil)
        XCTAssertNil(
            ShowDraftArtistAutoMatchPolicy.uniqueExactMatch(for: "Beyoncé", among: [exact, collision]),
            "Same-name collisions must remain unresolved for manual confirmation"
        )
    }
}

@MainActor final class ListeningWantsLivePresentationTests: XCTestCase {
    func testFrozenAndCanceledAreReadOnlyAndShowScoped() throws {
        let (container, show) = try ListenTestData.make()
        let repo = ListeningRepository(modelContext: container.mainContext)
        try repo.setWantsLive(showID: show.id, songID: "a1", isWanted: true)
        XCTAssertTrue(WantsLivePolicy.isMutable(show: show))
        XCTAssertFalse(WantsLivePolicy.isMutable(show: show, now: Date().addingTimeInterval(20000)))
        XCTAssertThrowsError(try repo.setWantsLive(showID: show.id, songID: "a1", isWanted: false, at: Date().addingTimeInterval(20000)))
        show.changeStatus = .canceled
        XCTAssertFalse(WantsLivePolicy.isMutable(show: show))
        XCTAssertThrowsError(try repo.setWantsLive(showID: show.id, songID: "a2", isWanted: true))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShowWantsLiveSong>()), 1)
        let frozen = ListeningWantsLivePresentation(selected: true, mutable: false)
        XCTAssertEqual(frozen.label, "开场前想现场听")
        XCTAssertEqual(frozen.symbol, "heart.fill")
    }
}
@MainActor final class ListeningArtistMatchingTests: XCTestCase {
    func testCandidateDoesNotWriteUntilConfirmation() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        let candidate = RecognizedArtist(id: "new", canonicalName: "New Artist", avatarURL: nil, appleMusicURL: URL(string: "https://music.apple.com/artist/123"))
        XCTAssertNil(show.artists[1].appleMusicArtistID)
        await room.rematch(slotIndex: 1, artist: candidate)
        XCTAssertEqual(show.artists[1].appleMusicArtistID, "new")
        XCTAssertEqual(show.artists[1].name, "New Artist")
        XCTAssertEqual(show.artists[1].appleMusicURL, candidate.appleMusicURL?.absoluteString)
    }
}
@MainActor final class ListeningArtistPreferenceTests: XCTestCase {
    func testScopeIsRuntimeAndExclusionReturnsToWholeShow() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        room.filterArtist("a")
        XCTAssertEqual(room.onlyArtistID, "a")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ShowArtistListeningPreference>()), 0)
        room.excludeArtist("a", excluded: true)
        XCTAssertNil(room.onlyArtistID)
        XCTAssertEqual(room.excludedArtistIDs, ["a"])
        let rows = try container.mainContext.fetch(FetchDescriptor<ShowArtistListeningPreference>())
        XCTAssertTrue(rows.allSatisfy { $0.showID == show.id })
        room.excludeArtist("a", excluded: false)
        XCTAssertTrue(room.excludedArtistIDs.isEmpty)
    }
}
@MainActor final class ListeningArtistLibraryTests: XCTestCase {
    func testTopAndAlbumOrderUseCatalogAndUnconnectedDoesNotBlock() async throws {
        let (container, show) = try ListenTestData.make()
        let room = ListenTestData.room(container.mainContext)
        await room.load(show: show)
        XCTAssertEqual(room.discs.first?.tracks.map(\.id), ["a2"])
        let artist = try XCTUnwrap(room.artistPresentation("a"))
        XCTAssertEqual(artist.top.map(\.id), ["a2"])
        XCTAssertEqual(artist.albums.first?.tracks.map(\.id), ["a2", "a1"])
        XCTAssertTrue(try XCTUnwrap(room.artistPresentation("c")).top.isEmpty)
        room.playLibrarySong(artist.all[1], artistID: "a")
        try await ListenTestData.settle(room) { room.isPlaying && room.track?.id == "a2" }
        XCTAssertEqual(room.mechanism.disc?.id, "album")
        room.setActive(false)
    }
}
@MainActor final class ListeningArtistRematchTests: XCTestCase {
    func testRematchKeepsBaselineAndGlobalEvidence() async throws {
        let (container, show) = try ListenTestData.make(ended: true)
        let context = container.mainContext
        let repo = ListeningRepository(modelContext: context)
        try repo.confirmManualFamiliarity(songID: "a1", at: Date().addingTimeInterval(-20000))
        try OpeningFamiliarityCoordinator.captureDueBaselines(in: context)
        try OpeningFamiliarityCoordinator.resolveAvailableTiers(in: context)
        try repo.setArtistExcluded(showID: show.id, artistID: "a", isExcluded: true)
        try context.save()
        let baseline = try XCTUnwrap(context.fetch(FetchDescriptor<ShowOpeningFamiliarityBaseline>()).first)
        let captured = baseline.capturedAt
        let room = ListenTestData.room(context)
        await room.load(show: show)
        await room.rematch(slotIndex: 0, artist: .init(id: "replacement", canonicalName: "Replacement", avatarURL: nil, appleMusicURL: nil))
        XCTAssertEqual(baseline.capturedAt, captured)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongFamiliarityRecord>()), 1)
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShowArtistListeningPreference>()).contains { $0.artistID == "a" })
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShowOpeningArtistTier>()).contains { $0.artistID == "a" })
    }
}
