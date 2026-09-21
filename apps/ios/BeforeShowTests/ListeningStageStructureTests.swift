import XCTest
@testable import BeforeShow

final class ListeningStageStructureTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("BeforeShow")

    private func source(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Features/Listening/\(name).swift"), encoding: .utf8)
    }

    func testProductionStageUsesFullDiscAndNoLegacyMachineLayers() throws {
        let stage = try source("Views/ListeningStageView")
        let room = try source("Views/ListeningRoomView")
        XCTAssertTrue(room.contains("ListeningStageView(room: room, width: proxy.size.width)"))
        for component in ["ListeningDiscStage", "ListeningTrackInformation", "ListeningTransportControls", "ListeningStageSurface", "ListeningPlayerAmbientHalo"] {
            XCTAssertTrue(stage.contains(component))
        }
        for legacy in ["CDPlayerLidView", "CDPlayerLidSurface", "HingedPlane", "CDPlayerLCDView", "CDPlayerDisplayView", "CDPlayerBodySurface", "ListeningCabinetView(", "ListeningArtistSelector("] {
            XCTAssertFalse(stage.contains(legacy))
            XCTAssertFalse(room.contains(legacy))
        }
        let disc = try source("Views/ListeningDiscStage")
        XCTAssertTrue(disc.contains("rotationEffect(.degrees(angle))"))
        XCTAssertFalse(disc.contains("scaleEffect(y:"))
        XCTAssertTrue((0.92...0.95).contains(ListeningStageTokens.discWidthFraction))
        let artwork = try source("Views/ListeningStyle").components(separatedBy: "struct ListeningArtwork")[0]
        XCTAssertFalse(artwork.contains("AngularGradient"))
        XCTAssertFalse(artwork.contains("listen_04_disc"))
    }

    func testFourControlsInOrderAndChangeDiscPresentsExistingSheet() throws {
        let controls = try source("Views/ListeningTransportControls")
        let previous = try XCTUnwrap(controls.range(of: "transport(.previous"))
        let play = try XCTUnwrap(controls.range(of: "transport(.playPause"))
        let next = try XCTUnwrap(controls.range(of: "transport(.next"))
        let change = try XCTUnwrap(controls.range(of: "Button(action: room.openCabinet)"))
        XCTAssertLessThan(previous.lowerBound, play.lowerBound)
        XCTAssertLessThan(play.lowerBound, next.lowerBound)
        XCTAssertLessThan(next.lowerBound, change.lowerBound)
        XCTAssertFalse(controls.contains("perform(.open)"))
        XCTAssertFalse(controls.contains(".stop"))
        XCTAssertTrue(controls.contains("accessibilityIdentifier(\"changeDisc\")"))
        XCTAssertTrue(try source("Views/ListeningRoomView").contains("ListeningCabinetSheet(room: room)"))
        XCTAssertGreaterThan(ListeningStageTokens.primaryButton, ListeningStageTokens.secondaryButton)
    }

    func testFiveApprovedAssetsExistAndAreReferenced() throws {
        let sources = try ["ListeningStageSurface", "ListeningStyle", "ListeningDiscStage", "ListeningTransportButtonFace"]
            .map { try source("Views/\($0)") }.joined()
        for name in ["player_stage_surface", "disc_gloss_overlay", "spindle_center", "button_primary_base", "button_secondary_base"] {
            XCTAssertTrue(sources.contains(name))
            let path = root.appendingPathComponent("Resources/BeforeShowListeningProductionAssets.xcassets/\(name).imageset/\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }

    func testPlaybackBindingsAndExistingBottomChromeRemain() throws {
        let info = try source("Views/ListeningTrackInformation")
        for binding in ["room.track?.title", "room.track?.artistName", "room.trackIndex + 1", "room.mechanism.disc?.tracks.count", "room.playbackState", "room.elapsed / duration", "room.timeText"] {
            XCTAssertTrue(info.contains(binding))
        }
        XCTAssertTrue(try source("ListeningFeatureRootView").contains("ListeningPolishedBottomChrome(selectedTab: $selectedTab)"))
        XCTAssertTrue(try source("ListeningRoomCoordinator").contains("func playPause()"))
        XCTAssertTrue(try source("Player/CDMechanism").contains("func load("))
        XCTAssertTrue(try source("Views/ListeningRoomView").contains("motion.reducedMotion = value"))
    }
}
