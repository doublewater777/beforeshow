import XCTest
import UIKit

@MainActor final class ListeningDragTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReplacementCarryKeepsSleeveFixedAndUsesPlayerSize() throws {
        let app = launchRoom()
        let window = app.windows.firstMatch
        XCTAssertTrue(app.otherElements["夜航 · Album CD"].waitForExistence(timeout: 10))
        coordinate(in: window, x: 260, y: 205).press(forDuration: 0, thenDragTo: coordinate(in: window, x: 120, y: 205))
        XCTAssertTrue(app.buttons["Aimer"].waitForExistence(timeout: 5))
        coordinate(in: window, x: 120, y: 205).press(forDuration: 0, thenDragTo: coordinate(in: window, x: 260, y: 205))
        XCTAssertTrue(app.buttons["Live Prep"].waitForExistence(timeout: 5))
        let before = XCUIScreen.main.screenshot().image
        let sleeve = sleevePatch
        let exposedCD = coordinate(in: window, x: 282, y: 205)
        let destination = exposedCD.withOffset(CGVector(dx: -40, dy: 220))
        attach(before, name: "Before CD carry")
        let held = try captureDuringDrag(from: exposedCD, to: destination)
        attach(held, name: "CD carry before release")
        XCTAssertLessThan(try difference(before, held, in: sleeve), 0.03,
                          "The sleeve must stay in its original position while the CD moves")
        let fullSizeRim = CGRect(x: 85, y: 400, width: 25, height: 40)
        XCTAssertGreaterThan(try brightFraction(held, in: fullSizeRim), 0.9,
                             "The carried CD must grow to player size, not remain a small sleeve preview")
        XCTAssertGreaterThan(try difference(before, held, in: fullSizeRim), 0.08,
                             "The full-size rim must belong to the carried CD, not the disc already seated")
    }

    private func launchRoom() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--listen-fixture", "single-full", "--listen-seed-disc", "file:///missing-listening-cover.png",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Rehearsal"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private final class Capture {
        var image: UIImage?
        var capturedAt: TimeInterval?
    }

    private func captureDuringDrag(from start: XCUICoordinate, to end: XCUICoordinate) throws -> UIImage {
        let capture = Capture()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            MainActor.assumeIsolated {
                capture.image = XCUIScreen.main.screenshot().image
                capture.capturedAt = ProcessInfo.processInfo.systemUptime
            }
        }
        defer { timer.invalidate() }
        start.press(forDuration: 0.5, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 10)
        let releasedAt = ProcessInfo.processInfo.systemUptime
        XCTAssertLessThan(try XCTUnwrap(capture.capturedAt), releasedAt,
                          "The visual assertion must sample the held gesture, not its final state")
        return try XCTUnwrap(capture.image)
    }

    private var sleevePatch: CGRect {
        CGRect(x: 136, y: 164, width: 88, height: 89)
    }

    private func coordinate(in window: XCUIElement, x: CGFloat, y: CGFloat) -> XCUICoordinate {
        XCTAssertEqual(window.frame.size, CGSize(width: 402, height: 874), "Run this visual fixture on beforeshow iphone 18 pro")
        return window.coordinate(withNormalizedOffset: CGVector(dx: x / 402, dy: y / 874))
    }

    private func difference(_ before: UIImage, _ after: UIImage, in rect: CGRect) throws -> Double {
        let a = try pixels(before, in: rect)
        let b = try pixels(after, in: rect)
        XCTAssertEqual(a.count, b.count)
        return zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count * 255)
    }

    private func brightFraction(_ image: UIImage, in rect: CGRect) throws -> Double {
        let values = try pixels(image, in: rect)
        var bright = 0
        for index in stride(from: 0, to: values.count, by: 4) {
            let channels = values[index...index + 2]
            if channels.allSatisfy({ $0 > 110 }) { bright += 1 }
        }
        return Double(bright) / Double(values.count / 4)
    }

    private func pixels(_ image: UIImage, in rect: CGRect) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cgImage.width) / 402
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
