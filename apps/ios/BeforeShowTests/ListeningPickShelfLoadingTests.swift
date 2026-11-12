import XCTest
import SwiftUI
import RealityKit
@testable import BeforeShow

@available(iOS 18.0, *)
@MainActor
final class ListeningPickShelfLoadingTests: XCTestCase {
    private static let phone = CGSize(width: 402, height: 874)
    private static let discs = (0..<1000).map {
        ListeningDisc(id: "case-\($0)", title: "Album \($0)", artworkURL: nil, tracks: [])
    }
    private var previousKeyWindow: UIWindow?

    @MainActor
    private final class Built {
        var anchor: Entity?
        var fixtures = 0
    }

    func testOpeningBuildsEveryCaseBeforeTheSwing() async throws {
        let (discs, phone) = (Self.discs, Self.phone)
        let scene = ShelfScene3D()
        let built = Built()
        let begun = expectation(description: "Opening begun")
        let window = try host(RealityView { content in
            content.camera = .virtual
            scene.install(in: &content)
            built.anchor = content.entities.first
            built.fixtures = built.anchor?.children.count ?? 0
            scene.beginOpening(discs: discs, position: 500, landing: nil, entrance: 0, size: phone)
            begun.fulfill()
        })
        defer { dismiss(window) }
        await fulfillment(of: [begun], timeout: 15)
        let root = try XCTUnwrap(built.anchor)
        let fixtures = built.fixtures
        let shown = ShelfScene3D.entranceIndices(count: discs.count, position: 500, size: phone)
        XCTAssertEqual(root.children.count - fixtures, shown.count, "Every case the swing shows is built while hidden")

        await scene.waitForOpening()
        XCTAssertEqual(root.children.filter(\.isEnabled).count, fixtures,
                       "The view is revealed on the swing's empty start, not the row at rest")
        let cases = Set(root.children.map(ObjectIdentifier.init))
        for step in 0...60 {
            scene.update(discs: discs, position: 500, landing: nil, entrance: Double(step) / 60, size: phone)
            XCTAssertTrue(Set(root.children.map(ObjectIdentifier.init)).isSubset(of: cases),
                          "The swing must not build cases; step \(step)")
        }
        XCTAssertGreaterThan(root.children.filter(\.isEnabled).count, fixtures, "The row comes to rest in view")
    }

    func testCasesBeyondReachLeaveTheScene() async throws {
        let (discs, phone) = (Self.discs, Self.phone)
        let scene = ShelfScene3D()
        let checked = expectation(description: "Reach checked")
        let window = try host(RealityView { content in
            content.camera = .virtual
            scene.install(in: &content)
            guard let root = content.entities.first else {
                XCTFail("The shelf must install its scene")
                checked.fulfill()
                return
            }
            let fixtures = root.children.count
            for (position, landing) in [(500.0, nil), (501.5, nil), (50.0, 900)] as [(Double, Int?)] {
                scene.update(discs: discs, position: position, landing: landing, entrance: 1, size: phone)
                let count = root.children.count - fixtures
                XCTAssertGreaterThan(count, 0, "The row at rest must render; position \(position)")
                XCTAssertLessThanOrEqual(count, 47, "Only the reach round the current album stays built; position \(position)")
            }
            for size in [CGSize(width: 1024, height: 1366), CGSize(width: 1366, height: 1024)] {
                scene.update(discs: discs, position: 500, landing: nil, entrance: 1, size: size)
                XCTAssertGreaterThan(root.children.filter(\.isEnabled).count, fixtures, "The row renders on \(size)")
            }
            checked.fulfill()
        })
        defer { dismiss(window) }
        await fulfillment(of: [checked], timeout: 15)
    }

    func testShelfBuildsItsSceneWithoutArtwork() async throws {
        let ready = expectation(description: "3D shelf ready")
        let clock = ContinuousClock()
        let start = clock.now
        var elapsed: Duration?
        let window = try host(ListeningPickShelf3D(discs: Array(Self.discs.prefix(20)), position: 10) {
            elapsed = start.duration(to: clock.now)
            ready.fulfill()
        })
        defer { dismiss(window) }
        await fulfillment(of: [ready], timeout: 15)
        let duration = try XCTUnwrap(elapsed)
        let timing = XCTAttachment(string: "First shelf scene ready: \(duration)")
        timing.lifetime = .keepAlways
        add(timing)
    }

    func testOpeningWaitsForItsPrintsWithinABudgetFromTheFirstFrame() {
        let cases = ["near", "far"]
        let nearOnly = { (id: String) in id == "near" }
        XCTAssertTrue(ShelfScene3D.isOpeningPrinted(cases: cases, sinceFirstFrame: nil) { _ in true })
        XCTAssertFalse(ShelfScene3D.isOpeningPrinted(cases: cases, sinceFirstFrame: nil, isSettled: nearOnly),
                       "Compiling shaders before the first frame must not use up the wait")
        XCTAssertFalse(ShelfScene3D.isOpeningPrinted(cases: cases, sinceFirstFrame: .milliseconds(200), isSettled: nearOnly))
        XCTAssertTrue(ShelfScene3D.isOpeningPrinted(cases: cases, sinceFirstFrame: ShelfScene3D.openingBudget, isSettled: nearOnly),
                      "A slow cover must not hold the swing")
    }

    private func host(_ view: some View) throws -> UIWindow {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = windowScene.keyWindow
        let window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.screen.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }

    private func dismiss(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}
