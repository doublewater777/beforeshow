import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The light rig behind the screen: moving heads on the truss, uplights on the deck
/// and a laser, drawn as light in haze — a defined column, a soft halo and a hot core.
struct BSStageRig: View {
    let height: CGFloat
    let energy: Double
    private let palette: [SIMD3<Double>]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let fixtureCount = BSStageChoreography.trussCount
    /// Where the truss lamps hang, as a fraction of the width.
    static func fixtureX(_ index: Int) -> CGFloat {
        0.1 + CGFloat(index) * 0.8 / CGFloat(fixtureCount - 1)
    }
    /// Deck uplights stand either side of the screen.
    private static let deckX: [CGFloat] = [0.05, 0.19, 0.81, 0.95]

    init(colors: [Color], energy: Double, height: CGFloat) {
        self.height = height
        self.energy = energy
        palette = colors.map { color in
            var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD3(Double(red), Double(green), Double(blue))
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 2 : context.date.timeIntervalSinceReferenceDate
            let frame = BSStageChoreography.frame(at: t, palette: palette, energy: energy)
            Canvas { canvas, size in
                canvas.blendMode = .plusLighter
                Self.drawLaser(frame.laser, in: &canvas, size: size)
                for (index, beam) in frame.deck.enumerated() {
                    let origin = CGPoint(x: size.width * Self.deckX[index], y: size.height - 78)
                    Self.draw(beam, from: origin, upward: true, in: &canvas, size: size)
                }
                for (index, beam) in frame.truss.enumerated() {
                    let origin = CGPoint(x: size.width * Self.fixtureX(index), y: 20)
                    Self.draw(beam, from: origin, upward: false, in: &canvas, size: size)
                }
            }
            // Haze: light only shows where there is smoke, and smoke drifts.
            .mask(BSStageHaze(time: t))
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ beam: BSStageBeamState, from origin: CGPoint, upward: Bool, in canvas: inout GraphicsContext, size: CGSize) {
        guard beam.intensity > 0.01 else { return }
        let radians = beam.pan * .pi / 180
        // A beam lifted toward the crowd reads shorter and wider from the front.
        let length = (upward ? size.height * 0.95 : size.height * 1.25 * (0.35 + 0.65 * beam.tilt))
        let widen = (1 + (1 - beam.tilt) * 1.2) * beam.spread
        let direction = CGPoint(x: sin(radians), y: upward ? -cos(radians) : cos(radians))
        let end = CGPoint(x: origin.x + direction.x * length, y: origin.y + direction.y * length)
        let normal = CGPoint(x: direction.y, y: -direction.x)
        let tint = Color(red: beam.rgb.x, green: beam.rgb.y, blue: beam.rgb.z)
        let level = beam.intensity

        func column(lens: CGFloat, angle: Double) -> Path {
            let half = lens + tan(angle * widen * .pi / 180) * length
            var path = Path()
            path.move(to: CGPoint(x: origin.x + normal.x * lens, y: origin.y + normal.y * lens))
            path.addLine(to: CGPoint(x: end.x + normal.x * half, y: end.y + normal.y * half))
            path.addLine(to: CGPoint(x: end.x - normal.x * half, y: end.y - normal.y * half))
            path.addLine(to: CGPoint(x: origin.x - normal.x * lens, y: origin.y - normal.y * lens))
            path.closeSubpath()
            return path
        }
        func along(_ stops: [(Color, Double)]) -> GraphicsContext.Shading {
            .linearGradient(Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }), startPoint: origin, endPoint: end)
        }

        // Halo: the haze lit around the beam.
        canvas.fill(column(lens: 6, angle: 4.5), with: along([(tint.opacity(0.12 * level), 0), (tint.opacity(0.06 * level), 0.5), (tint.opacity(0), 1)]))
        // Body: a column with a clear edge that carries far before it fades.
        canvas.fill(column(lens: 3, angle: 1.3), with: along([(tint.opacity(0.5 * level), 0), (tint.opacity(0.38 * level), 0.55), (tint.opacity(0), 1)]))
        // Core: the hot white centre.
        canvas.fill(column(lens: 1, angle: 0.3), with: along([(Color.white.opacity(0.6 * level), 0), (tint.opacity(0.25 * level), 0.4), (tint.opacity(0), 0.9)]))

        // Glare at the lens, bigger when the head turns toward the crowd.
        let glare = (upward ? 12 : 14 + 14 * (1 - beam.tilt)) + 8 * level
        canvas.fill(
            Path(ellipseIn: CGRect(x: origin.x - glare, y: origin.y - glare, width: glare * 2, height: glare * 2)),
            with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * level), tint.opacity(0.45 * level), .clear]), center: origin, startRadius: 0, endRadius: glare)
        )

        // Where a truss beam meets the floor.
        let floorY = size.height - 62
        guard !upward, direction.y > 0.2, end.y >= floorY else { return }
        let hit = CGPoint(x: origin.x + direction.x * (floorY - origin.y) / direction.y, y: floorY)
        let pool = 46 * beam.spread
        canvas.fill(
            Path(ellipseIn: CGRect(x: hit.x - pool, y: hit.y - pool / 5, width: pool * 2, height: pool * 0.4)),
            with: .radialGradient(Gradient(colors: [tint.opacity(0.35 * level), .clear]), center: hit, startRadius: 0, endRadius: pool)
        )
    }

    /// Thin, straight, saturated lines — sharper than any beam.
    private static func drawLaser(_ laser: BSStageLaserState, in canvas: inout GraphicsContext, size: CGSize) {
        guard laser.intensity > 0.01 else { return }
        let origin = CGPoint(x: size.width / 2, y: 44)
        let tint = Color(red: laser.rgb.x, green: laser.rgb.y, blue: laser.rgb.z)
        let lines = 9
        let length = size.height * 1.4
        for line in 0..<lines {
            let angle = (laser.center + laser.opening * (Double(line) / Double(lines - 1) - 0.5)) * .pi / 180
            var path = Path()
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + sin(angle) * length, y: origin.y + cos(angle) * length))
            canvas.stroke(path, with: .color(tint.opacity(0.22 * laser.intensity)), lineWidth: 3.5)
            canvas.stroke(path, with: .color(tint.opacity(0.95 * laser.intensity)), lineWidth: 0.8)
        }
    }
}

/// Slow-drifting smoke, as an alpha mask between 0.5 and 1.
private struct BSStageHaze: View {
    let time: Double

    private static let texture: UIImage? = {
        let context = CIContext()
        let noise = CIFilter.randomGenerator().outputImage?
            .transformed(by: CGAffineTransform(scaleX: 6, y: 3))
            .applyingGaussianBlur(sigma: 10)
            .cropped(to: CGRect(x: 0, y: 0, width: 640, height: 400))
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = noise
        // White with alpha squeezed into 0.5...1, so beams are textured but never lost.
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 0.17, y: 0.17, z: 0.17, w: 0)
        matrix.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0.5)
        guard let output = matrix.outputImage,
              let cg = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: 640, height: 400)) else { return nil }
        return UIImage(cgImage: cg)
    }()

    var body: some View {
        GeometryReader { proxy in
            if let texture = Self.texture {
                let drift = CGFloat(time * 6).truncatingRemainder(dividingBy: proxy.size.width)
                HStack(spacing: 0) {
                    Image(uiImage: texture).resizable().frame(width: proxy.size.width, height: proxy.size.height)
                    Image(uiImage: texture).resizable().frame(width: proxy.size.width, height: proxy.size.height)
                }
                .offset(x: -drift)
            } else {
                Color.white
            }
        }
        .clipped()
    }
}
