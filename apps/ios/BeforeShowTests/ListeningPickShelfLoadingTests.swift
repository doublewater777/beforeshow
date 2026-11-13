import XCTest
import SwiftUI
import simd
@testable import BeforeShow

@MainActor
final class ListeningPickShelfLoadingTests: XCTestCase {
    private static let phone = CGSize(width: 402, height: 874)
    private static let discs = (0..<1000).map {
        ListeningDisc(id: "case-\($0)", title: "Album \($0)", artworkURL: nil, tracks: [])
    }
    private var previousKeyWindow: UIWindow?

    func testOpeningBuildsEveryCaseBeforeTheSwing() async {
        let (discs, phone) = (Self.discs, Self.phone)
        let scene = ShelfScene3D()
        scene.update(discs: discs, position: 500, landing: nil, entrance: 0, size: phone)
        let shown = ShelfGeometry.entranceIndices(count: discs.count, position: 500, size: phone)
        let built = scene.view.layer.sublayers ?? []
        XCTAssertEqual(built.count, shown.count, "Every case the swing shows is built before it starts")
        XCTAssertTrue(built.allSatisfy(\.isHidden), "The cases wait out of sight for their prints")

        await scene.waitForOpening()
        XCTAssertTrue((scene.view.layer.sublayers ?? []).allSatisfy(\.isHidden), "The swing starts from an empty stage")
        let cases = Set(built.map(ObjectIdentifier.init))
        for step in 0...60 {
            scene.update(discs: discs, position: 500, landing: nil, entrance: Double(step) / 60, size: phone)
            XCTAssertTrue(Set((scene.view.layer.sublayers ?? []).map(ObjectIdentifier.init)).isSubset(of: cases),
                          "The swing must not build cases; step \(step)")
        }
        XCTAssertTrue((scene.view.layer.sublayers ?? []).contains { !$0.isHidden }, "The row comes to rest in view")
    }

    func testCasesBeyondReachLeaveTheScene() async {
        let (discs, phone) = (Self.discs, Self.phone)
        let scene = ShelfScene3D()
        scene.update(discs: discs, position: 500, landing: nil, entrance: 1, size: phone)
        await scene.waitForOpening()
        for (position, landing) in [(500.0, nil), (501.5, nil), (50.0, 900)] as [(Double, Int?)] {
            scene.update(discs: discs, position: position, landing: landing, entrance: 1, size: phone)
            let built = scene.view.layer.sublayers ?? []
            XCTAssertTrue(built.contains { !$0.isHidden }, "The row at rest must render; position \(position)")
            XCTAssertLessThanOrEqual(built.count, 47, "Only the reach round the current album stays built; position \(position)")
        }
        for size in [CGSize(width: 1024, height: 1366), CGSize(width: 1366, height: 1024)] {
            scene.update(discs: discs, position: 500, landing: nil, entrance: 1, size: size)
            XCTAssertTrue((scene.view.layer.sublayers ?? []).contains { !$0.isHidden }, "The row renders on \(size)")
        }
    }

    func testShelfOpensWithoutArtwork() async throws {
        let ready = expectation(description: "3D shelf ready")
        let window = try host(ListeningPickShelf3D(discs: Array(Self.discs.prefix(20)), position: 10, entrance: 0) {
            ready.fulfill()
        })
        defer { dismiss(window) }
        await fulfillment(of: [ready], timeout: 5)
    }

    func testOpeningWaitsForItsPrintsWithinABudget() {
        let cases = ["near", "far"]
        let nearOnly = { (id: String) in id == "near" }
        XCTAssertTrue(ShelfScene3D.isOpeningPrinted(cases: cases, waited: .zero) { _ in true })
        XCTAssertFalse(ShelfScene3D.isOpeningPrinted(cases: cases, waited: .milliseconds(200), isSettled: nearOnly))
        XCTAssertTrue(ShelfScene3D.isOpeningPrinted(cases: cases, waited: ShelfScene3D.openingBudget, isSettled: nearOnly),
                      "A slow cover must not hold the swing")
    }

    func testFaceLandsOnItsProjectedCorners() {
        let size = CGSize(width: 114, height: 100)
        let corners = [CGPoint(x: 10, y: 20), CGPoint(x: 200, y: 40), CGPoint(x: 180, y: 300), CGPoint(x: 30, y: 250)]
        let mapping = ShelfGeometry.mapping(size, onto: corners)
        let square = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
        for (point, expected) in zip(square, corners) {
            let x = point.x * mapping.m11 + point.y * mapping.m21 + mapping.m41
            let y = point.x * mapping.m12 + point.y * mapping.m22 + mapping.m42
            let w = point.x * mapping.m14 + point.y * mapping.m24 + mapping.m44
            XCTAssertEqual(x / w, expected.x, accuracy: 0.001)
            XCTAssertEqual(y / w, expected.y, accuracy: 0.001)
        }
    }

    func testOnlyFacesTowardTheCameraAreDrawn() throws {
        let camera = ShelfCamera(size: Self.phone)
        let shelfCase = ShelfCaseLayer()
        // Front, open edge, top, hinge.
        shelfCase.place(ShelfCaseLayer.placement(.init(place: .zero, turn: simd_quatf(angle: 0, axis: [0, 1, 0]), opacity: 1), camera: camera))
        let faces = try XCTUnwrap(shelfCase.root.sublayers)
        XCTAssertEqual(faces.map(\.isHidden), [false, false, false, true], "At rest the hinge is turned away")
        let swinging = ShelfGeometry.Pose(place: .zero, turn: simd_quatf(angle: ShelfGeometry.swingAngle, axis: [0, 1, 0]), opacity: 1)
        shelfCase.place(ShelfCaseLayer.placement(swinging, camera: camera))
        XCTAssertEqual(faces.map(\.isHidden), [false, true, false, false], "Swinging in, the hinge shows and the open edge turns away")
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
