import Foundation
import UIKit

/// Stage-light colours sampled from a show's poster, so every night is lit differently.
struct FootprintStageLight: Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

enum FootprintStageLights {
    /// Warm amber and gold for posters with no usable colour.
    static let fallback = [
        FootprintStageLight(red: 1.0, green: 0.62, blue: 0.24),
        FootprintStageLight(red: 1.0, green: 0.82, blue: 0.42)
    ]

    /// The two most present vivid hues, lifted to full brightness like a gelled lamp.
    static func pick(from pixels: [FootprintStageLight]) -> [FootprintStageLight] {
        var buckets: [Int: (weight: Double, hue: Double, saturation: Double)] = [:]
        for pixel in pixels {
            let (hue, saturation, brightness) = hsb(pixel)
            guard saturation > 0.3, brightness > 0.3 else { continue }
            let bucket = Int(hue * 12) % 12
            let weight = saturation * brightness
            let current = buckets[bucket] ?? (0, 0, 0)
            buckets[bucket] = (current.weight + weight, current.hue + hue * weight, current.saturation + saturation * weight)
        }
        let ranked = buckets.values.sorted { $0.weight > $1.weight }
        guard let first = ranked.first, first.weight > Double(pixels.count) * 0.02 else { return fallback }
        let lights = ranked.prefix(2).map { bucket in
            light(hue: bucket.hue / bucket.weight, saturation: min(0.9, bucket.saturation / bucket.weight))
        }
        return lights.count == 2 ? lights : [lights[0], light(hue: hsb(lights[0]).0 + 0.08, saturation: 0.7)]
    }

    /// Downsamples the poster and reads its pixels; runs off the main thread.
    static func sample(_ image: UIImage) -> [FootprintStageLight] {
        let side = 16
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = small.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let stride = cg.bytesPerRow, step = cg.bitsPerPixel / 8
        guard step >= 3 else { return [] }
        var pixels: [FootprintStageLight] = []
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let offset = y * stride + x * step
                pixels.append(FootprintStageLight(
                    red: Double(bytes[offset]) / 255,
                    green: Double(bytes[offset + 1]) / 255,
                    blue: Double(bytes[offset + 2]) / 255
                ))
            }
        }
        return pixels
    }

    private static func light(hue: Double, saturation: Double) -> FootprintStageLight {
        let color = UIColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: 1, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return FootprintStageLight(red: Double(r), green: Double(g), blue: Double(b))
    }

    private static func hsb(_ pixel: FootprintStageLight) -> (Double, Double, Double) {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(red: pixel.red, green: pixel.green, blue: pixel.blue, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (Double(h), Double(s), Double(v))
    }
}
