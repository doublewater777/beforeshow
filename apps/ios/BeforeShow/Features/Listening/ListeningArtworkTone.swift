import UIKit

/// Average artwork colour, used to tint CD spines and the rack glow.
@MainActor enum ListeningArtworkTone {
    private static var cache: [URL: UIColor] = [:]

    static func cached(_ url: URL?) -> UIColor? {
        url.flatMap { cache[$0] }
    }

    static func tone(for url: URL) async -> UIColor? {
        if let color = cache[url] { return color }
        guard let image = await ShowCoverImageCache.shared.image(from: url),
              let color = average(image) else { return nil }
        cache[url] = color
        return color
    }

    nonisolated static func average(_ image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    /// Pale covers keep a pale spine with dark ink; everything else gets a deepened spine.
    static func spine(for tone: UIColor) -> (fill: UIColor, isLight: Bool) {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        tone.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if brightness > 0.78, saturation < 0.18 {
            return (UIColor(hue: hue, saturation: saturation, brightness: 0.9, alpha: 1), true)
        }
        return (UIColor(hue: hue, saturation: min(saturation * 1.1, 0.8), brightness: min(brightness, 0.42), alpha: 1), false)
    }
}
