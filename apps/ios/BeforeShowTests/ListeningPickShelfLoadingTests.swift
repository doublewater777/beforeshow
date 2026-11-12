import XCTest
import SwiftUI
import RealityKit
@testable import BeforeShow

@available(iOS 18.0, *)
@MainActor
final class ListeningPickShelfLoadingTests: XCTestCase {
    func testSceneOnlyCreatesCasesThatCanBeDrawn() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = windowScene.keyWindow
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.screen.bounds
        let checked = expectation(description: "Visible scene entities checked")
        let scene = ShelfScene3D()
        let discs = (0..<1000).map {
            ListeningDisc(id: "visible-\($0)", title: "Album \($0)", artworkURL: nil, tracks: [])
        }
        window.rootViewController = UIHostingController(rootView: RealityView { content in
            content.camera = .virtual
            scene.install(in: &content)
            guard let root = content.entities.first else {
                XCTFail("The shelf must install its scene")
                checked.fulfill()
                return
            }
            let lightingAndCameraCount = root.children.count
            let size = CGSize(width: 402, height: 874)
            scene.update(discs: discs, position: 500, landing: nil, entrance: 0, size: size)
            XCTAssertEqual(root.children.count, lightingAndCameraCount,
                           "A fully transparent opening must not build any cases")

            for (position, landing, entrance) in [(500.0, nil, 0.2), (500.0, nil, 1.0), (501.5, nil, 1.0), (50.0, 900, 1.0)] as [(Double, Int?, Double)] {
                scene.update(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
                XCTAssertTrue(root.children.allSatisfy(\.isEnabled),
                              "Offscreen cases must be removed rather than kept disabled; position \(position)")
                if entrance == 1 {
                    XCTAssertGreaterThan(root.children.count, lightingAndCameraCount, "The visible shelf must still render")
                }
                let count = root.children.count - lightingAndCameraCount
                if entrance == 0.2 {
                    XCTAssertLessThanOrEqual(count, 8,
                                             "The first visible stretch must not allocate the offscreen row")
                }
                let note = XCTAttachment(string: "position=\(position), entrance=\(entrance), case entities=\(count)")
                note.lifetime = .keepAlways
                self.add(note)
            }
            for size in [CGSize(width: 1024, height: 1366), CGSize(width: 1366, height: 1024)] {
                scene.update(discs: discs, position: 500, landing: nil, entrance: 1, size: size)
                XCTAssertTrue(root.children.allSatisfy(\.isEnabled), "Viewport resizing must retire invisible cases")
                XCTAssertGreaterThan(root.children.count, lightingAndCameraCount)
            }
            scene.update(discs: discs, position: 50, landing: nil, entrance: 0, size: size)
            XCTAssertEqual(root.children.count, lightingAndCameraCount, "Cases that stop drawing must leave the scene")
            checked.fulfill()
        })
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        await fulfillment(of: [checked], timeout: 15)
    }

    func testShelfBuildsItsSceneWithoutArtwork() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = windowScene.keyWindow
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.screen.bounds
        let ready = expectation(description: "3D shelf ready")
        let clock = ContinuousClock()
        let start = clock.now
        var elapsed: Duration?
        let discs = (0..<20).map {
            ListeningDisc(id: "cold-\($0)", title: "Album \($0)", artworkURL: nil, tracks: [])
        }
        window.rootViewController = UIHostingController(rootView: ListeningPickShelf3D(discs: discs, position: 10) {
            elapsed = start.duration(to: clock.now)
            ready.fulfill()
        })
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        await fulfillment(of: [ready], timeout: 15)
        let duration = try XCTUnwrap(elapsed)
        let timing = XCTAttachment(string: "First shelf scene ready: \(duration)")
        timing.lifetime = .keepAlways
        add(timing)
    }

    func testUnloadedNeighboursDoNotDelayAnOpeningDiscWithoutArtwork() async {
        let scene = ShelfScene3D()
        let discs = (0..<50).map { index in
            ListeningDisc(
                id: "\(index)", title: "Album \(index)",
                artworkURL: index == 30 ? nil : URL(string: "https://shelf-loading.test/\(index)"),
                tracks: []
            )
        }
        await scene.preload([discs[30]])

        let clock = ContinuousClock()
        let start = clock.now
        await scene.waitForOpening(discs: discs, position: 30)

        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(100),
                          "The row must enter without waiting for neighbouring artwork")
    }

    func testPendingOpeningArtworkHasAShortWaitBudget() async {
        let scene = ShelfScene3D()
        let disc = ListeningDisc(
            id: "pending", title: "Pending artwork",
            artworkURL: URL(string: "https://shelf-loading.test/pending"), tracks: []
        )

        let clock = ContinuousClock()
        let start = clock.now
        await scene.waitForOpening(discs: [disc], position: 0)
        let elapsed = start.duration(to: clock.now)

        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100), "Allow nearby cached artwork to arrive")
        XCTAssertLessThan(elapsed, .milliseconds(400), "A slow cover must not hold the entrance for a second")
    }
}
