import XCTest
import UIKit

@MainActor final class ListeningDragTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnlyCDMovesWhileDraggingIntoEmptyPlayer() throws {
        try assertDiscCarry(hasLoadedDisc: false)
    }

    func testOnlyCDMovesWhileDraggingReplacementOverPlayer() throws {
        try assertDiscCarry(hasLoadedDisc: true)
    }

    func testCoverCannotStartCarryAndRackStillSwipes() throws {
        let app = launchRoom()
        let rack = app.otherElements["listening.rack"]
        let plate = app.buttons["listening.rack.plate"]
        let before = XCUIScreen.main.screenshot().image
        let cover = rack.coordinate(withNormalizedOffset: CGVector(dx: 0.43, dy: 0.35))
        let held = try captureDuringDrag(from: cover, to: cover.withOffset(CGVector(dx: 0, dy: 220)))
        let sleeve = sleevePatch(in: rack.frame)
        XCTAssertLessThan(try difference(before, held, in: sleeve), 0.03,
                          "Holding the cover must leave the sleeve on the rack")
        XCTAssertFalse(app.otherElements["listening.discDetail"].exists)
        let initialTitle = plate.label
        rack.swipeLeft()
        let changed = NSPredicate { _, _ in plate.label != initialTitle }
        expectation(for: changed, evaluatedWith: plate)
        waitForExpectations(timeout: 5)
    }

    private func assertDiscCarry(hasLoadedDisc: Bool) throws {
        let app = launchRoom(hasLoadedDisc: hasLoadedDisc)
        let rack = app.otherElements["listening.rack"]
        let before = XCUIScreen.main.screenshot().image
        let sleeve = sleevePatch(in: rack.frame)
        let exposedCD = rack.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.35))
        let destination = exposedCD.withOffset(CGVector(dx: -40, dy: 220))
        let held = try captureDuringDrag(from: exposedCD, to: destination)
        XCTAssertLessThan(try difference(before, held, in: sleeve), 0.03,
                          "The sleeve must stay in its original position while the CD moves")
        let discPatch = CGRect(x: destination.screenPoint.x - 25, y: destination.screenPoint.y - 20,
                               width: 20, height: 40)
        XCTAssertGreaterThan(try colorfulFraction(held, in: discPatch), 0.25,
                             "The carried CD must remain visible outside the rack over the player")
        attach(before, name: "Before CD carry")
        attach(held, name: "CD carry before release")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'NO DISC'")).firstMatch.exists,
                       "A real long-press and drop must load the CD")
    }

    private func launchRoom(hasLoadedDisc: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "single-full", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if hasLoadedDisc {
            app.launchArguments += ["--listen-seed-disc", "file:///missing-listening-cover.png"]
        }
        app.launch()
        XCTAssertTrue(app.otherElements["listening.rack"].waitForExistence(timeout: 15))
        // The rack reveals its disc after the initial focus animation.
        let ready = NSPredicate { _, _ in
            !app.activityIndicators.firstMatch.exists
        }
        expectation(for: ready, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        Thread.sleep(forTimeInterval: 1)
        return app
    }

    private final class Capture {
        var image: UIImage?
        var capturedAt: TimeInterval?
    }

    private func captureDuringDrag(from start: XCUICoordinate, to end: XCUICoordinate) throws -> UIImage {
        let capture = Capture()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            MainActor.assumeIsolated {
                capture.image = XCUIScreen.main.screenshot().image
                capture.capturedAt = ProcessInfo.processInfo.systemUptime
            }
        }
        defer { timer.invalidate() }
        start.press(forDuration: 0.5, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 3)
        let releasedAt = ProcessInfo.processInfo.systemUptime
        XCTAssertLessThan(try XCTUnwrap(capture.capturedAt), releasedAt,
                          "The visual assertion must sample the held gesture, not its final state")
        return try XCTUnwrap(capture.image)
    }

    private func sleevePatch(in rack: CGRect) -> CGRect {
        CGRect(x: rack.minX + rack.width * 0.34, y: rack.minY + rack.height * 0.18,
               width: rack.width * 0.22, height: rack.height * 0.40)
    }

    private func difference(_ before: UIImage, _ after: UIImage, in rect: CGRect) throws -> Double {
        let a = try pixels(before, in: rect)
        let b = try pixels(after, in: rect)
        XCTAssertEqual(a.count, b.count)
        return zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count * 255)
    }

    private func colorfulFraction(_ image: UIImage, in rect: CGRect) throws -> Double {
        let values = try pixels(image, in: rect)
        var colorful = 0
        for index in stride(from: 0, to: values.count, by: 4) {
            let channels = values[index...index + 2]
            if Int(channels.max()!) - Int(channels.min()!) > 45 { colorful += 1 }
        }
        return Double(colorful) / Double(values.count / 4)
    }

    private func pixels(_ image: UIImage, in rect: CGRect) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cgImage.width) / image.size.width
        let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                           width: rect.width * scale, height: rect.height * scale)))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: crop.width, height: crop.height,
                                             bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return bytes
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
