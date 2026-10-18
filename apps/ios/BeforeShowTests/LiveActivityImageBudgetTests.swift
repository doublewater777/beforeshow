import UIKit
import XCTest
@testable import BeforeShow

final class LiveActivityImageBudgetTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 灵动岛 / 锁屏在图片超出展示区域时显示灰色占位：输出的点尺寸必须等于展示区域。
    func testImageMatchesPresentationPointsAtThreeTimesPixels() throws {
        let url = try writeJPEG(width: 1_024, height: 1_024)

        for size in [CGSize(width: 22, height: 22), CGSize(width: 64, height: 64), CGSize(width: 72, height: 96)] {
            let image = try XCTUnwrap(WidgetCoverCache.liveActivityImage(contentsOf: url, filling: size))
            XCTAssertEqual(image.size, size)
            XCTAssertEqual(image.scale, 3)
            XCTAssertEqual(image.cgImage?.width, Int(size.width * 3))
            XCTAssertEqual(image.cgImage?.height, Int(size.height * 3))
        }
    }

    /// 宽图填充竖向区域时裁切而不是拉伸：中心列保持源图中心的颜色。
    func testNonSquareSourceIsCroppedNotStretched() throws {
        let url = try writeJPEG(width: 300, height: 100) { context, size in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: size.width / 3, height: size.height))
            UIColor.green.setFill(); context.fill(CGRect(x: size.width / 3, y: 0, width: size.width / 3, height: size.height))
            UIColor.blue.setFill(); context.fill(CGRect(x: size.width * 2 / 3, y: 0, width: size.width / 3, height: size.height))
        }

        let image = try XCTUnwrap(WidgetCoverCache.liveActivityImage(contentsOf: url, filling: CGSize(width: 20, height: 20)))
        let left = try pixel(of: image, x: 2, y: 30)
        XCTAssertGreaterThan(left.green, 0.6, "A 3:1 source filling a square shows only its middle third")
        XCTAssertLessThan(left.red, 0.4)
    }

    func testMissingOrEmptyInputsReturnNil() throws {
        XCTAssertNil(WidgetCoverCache.liveActivityImage(contentsOf: directory.appendingPathComponent("missing.jpg"),
                                                        filling: CGSize(width: 22, height: 22)))
        let url = try writeJPEG(width: 10, height: 10)
        XCTAssertNil(WidgetCoverCache.liveActivityImage(contentsOf: url, filling: .zero))
    }

    func testCachedLiveActivityFileCoversTheLargestPresentation() {
        // 锁屏封面 72×96pt @3x
        XCTAssertGreaterThanOrEqual(WidgetCoverCache.liveActivityMaxPixelDimension, 288)
    }

    // MARK: - Helpers

    private func writeJPEG(
        width: CGFloat, height: CGFloat,
        draw: ((UIGraphicsImageRendererContext, CGSize) -> Void)? = nil
    ) throws -> URL {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let draw { draw(context, size) } else {
                UIColor.orange.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: url)
        return url
    }

    private func pixel(of image: UIImage, x: Int, y: Int) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let cgImage = try XCTUnwrap(image.cgImage)
        var data = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: -x, y: -(cgImage.height - 1 - y), width: cgImage.width, height: cgImage.height))
        return (CGFloat(data[0]) / 255, CGFloat(data[1]) / 255, CGFloat(data[2]) / 255)
    }
}
