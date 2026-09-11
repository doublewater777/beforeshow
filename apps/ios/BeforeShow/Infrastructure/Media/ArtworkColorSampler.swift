import CoreImage
import UIKit

enum ArtworkColorSampler {
    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    nonisolated(unsafe) private static let cache = NSCache<UIImage, UIColor>()

    /// Work on the cached, decoded image off the main actor; never on playback ticks.
    static func color(in image: UIImage) async -> UIColor? {
        if let cached = cache.object(forKey: image) {
            return cached
        }
        return await Task.detached(priority: .utility) {
            guard let input = CIImage(image: image),
                  let filter = CIFilter(name: "CIAreaAverage", parameters: [
                    kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)
                  ]), let output = filter.outputImage else { return nil }
            var pixel = [UInt8](repeating: 0, count: 4)
            ciContext.render(
                output, toBitmap: &pixel, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            guard pixel[3] > 0 else { return nil }
            let sampled = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                                  blue: CGFloat(pixel[2]) / 255, alpha: 1)
            cache.setObject(sampled, forKey: image)
            return sampled
        }.value
    }
}

