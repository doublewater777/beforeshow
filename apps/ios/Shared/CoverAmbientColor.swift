import CoreImage
import SwiftUI
import UIKit

// MARK: - Cover Ambient Color
// 首页与主屏小组件共用：封面顶部条带均色 → 舞台灯色。
// 只取顶部 ~25%，再轻提饱和、压亮度，让环境光从海报顶边向外蔓延。

enum CoverAmbientColor {
    static func uiColor(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let topBand = CGRect(
            x: extent.minX,
            y: extent.maxY - extent.height * 0.25,
            width: extent.width,
            height: extent.height * 0.25
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: topBand)
        ]), let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let average = UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return average
        }
        return UIColor(
            hue: hue,
            saturation: min(1, saturation * 1.5 + 0.15),
            brightness: min(max(brightness, 0.38), 0.75),
            alpha: 1
        )
    }

    static func uiColor(fromCoverAt path: String?) -> UIColor? {
        guard let path, let image = UIImage(contentsOfFile: path) else { return nil }
        return uiColor(from: image)
    }
}

struct WidgetAmbientRGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    init?(uiColor: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
    }
}

/// 首页 / 主屏小组件共用的封面顶边漫光。
struct CoverAmbientBloom: View {
    let ambient: WidgetAmbientRGB?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.018, blue: 0.025),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let ambient {
                GeometryReader { geometry in
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [
                                ambient.color.opacity(0.85),
                                ambient.color.opacity(0.38),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.68
                        ))
                        .frame(
                            width: geometry.size.width * 1.35,
                            height: geometry.size.height * 0.72
                        )
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.10)
                        .blur(radius: min(28, geometry.size.width * 0.16))
                        .blendMode(.screen)
                }

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.18), location: 0.00),
                        .init(color: Color.black.opacity(0.12), location: 0.42),
                        .init(color: Color.black.opacity(0.28), location: 0.76),
                        .init(color: Color.black.opacity(0.48), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}
