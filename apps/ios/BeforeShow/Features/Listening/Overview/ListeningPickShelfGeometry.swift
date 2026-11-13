import CoreGraphics
import QuartzCore
import simd

/// The 3D shelf's row and camera: where each case stands and where it lands on screen. The cases are flat layers mapped
/// onto their projected corners, so this is all the 3D there is.
enum ShelfGeometry {
    /// A real jewel case is 142 × 125 mm: a little wider than tall.
    static let caseWidth: Float = 1.14
    static let caseHeight: Float = 1
    static let thickness: Float = 0.085
    /// The clear lid is the front of the case's depth; the tray behind it is darker.
    static let lidDepth: Float = thickness * 0.38
    static let hingeWidth: Float = 0.04
    /// The printed insert under the lid, set off the hinge.
    static let insertSize: SIMD2<Float> = [1.06, 0.96]
    static let insertShift: Float = 0.03
    static let spacing: Float = 0.24
    /// Each case further back also sits a little to the right, so the row runs diagonally.
    static let stagger: Float = 0
    /// The picked case slides out sideways beside the row and stands facing you.
    static let pullOut: SIMD3<Float> = [1.25, 0.1, 0.15]
    static let pullTurn: Float = 0.2
    /// Cases in front of the picked one ease forward a little, leaving the slot it came from.
    static let frontGap: Float = 0.1
    /// The opening swing: the row turns in round the case this far back, from this angle off to the right.
    static let swingPivot: Float = 26
    static let swingAngle: Float = 1.25
    /// Camera 33° round to the right of the covers and 34° above, framed close like the drawn shelf: the row runs from off the
    /// bottom-left edge to off the right edge just under the title, with the picked case right of centre.
    static let cameraOffset: SIMD3<Float> = [4.289, 5.312, 6.605]
    /// Wider screens (iPad landscape) swing the camera further round and lower, so the row lies flatter and still runs
    /// from the bottom-left edge to the top-right one.
    static func cameraOffset(for size: CGSize) -> SIMD3<Float> {
        guard size.height > 0 else { return cameraOffset }
        let wide = Float(min(1, max(0, (size.width / size.height - 0.75) / 0.6)))
        let distance = simd_length(cameraOffset)
        let azimuth = (33 + 14 * wide) * .pi / 180
        let elevation = (34 - 12 * wide) * .pi / 180
        return [distance * cos(elevation) * sin(azimuth), distance * sin(elevation), distance * cos(elevation) * cos(azimuth)]
    }
    static let aim: SIMD3<Float> = [1.5, 0.9, 1.3]

    /// A blur faded in over the top-right corner: none up to `from`, all of it past `to`, as fractions of the view.
    struct SoftBand {
        let radius: CGFloat
        let from: CGPoint
        let to: CGPoint

        /// The corner the band covers, from where it starts to the top-right.
        func region(in size: CGSize) -> CGRect {
            CGRect(x: size.width * from.x, y: 0, width: size.width * (1 - from.x), height: size.height * from.y)
        }
    }

    /// The far end of the row goes soft towards the top-right corner: a light blur first, then a heavier one over it,
    /// so no stretch fades straight from sharp to the heaviest blur.
    static let softBands = [
        SoftBand(radius: 2, from: CGPoint(x: 0.4, y: 0.36), to: CGPoint(x: 0.6, y: 0.23)),
        SoftBand(radius: 4.5, from: CGPoint(x: 0.6, y: 0.23), to: CGPoint(x: 0.8, y: 0.1)),
    ]
    static let fieldOfView: CGFloat = 30
    /// Lens scale in points. A phone gets `fieldOfView` across its height; taller screens (iPad) stop growing the cases
    /// a little past phone size and show more of the row instead.
    static func focal(forHeight height: CGFloat) -> CGFloat {
        let phoneFocal = 874 / 2 / tan(fieldOfView / 2 * .pi / 180)
        return min(height / 2 / tan(fieldOfView / 2 * .pi / 180), phoneFocal * 1.15)
    }
    /// How much more of the row fits than on a phone.
    private static func reach(forHeight height: CGFloat) -> Double {
        Double(height / 2 / focal(forHeight: height) / tan(fieldOfView / 2 * .pi / 180))
    }

    /// Where the next case back in the row lands on screen, so a drag can keep the cases under the finger.
    static func screenStep(in size: CGSize) -> CGVector {
        let camera = ShelfCamera(size: size)
        let near = camera.project([0, 0, 0])
        let far = camera.project([0, 0, -spacing])
        return CGVector(dx: far.x - near.x, dy: far.y - near.y)
    }

    /// Where a point in the scene lands in the view.
    static func project(_ point: SIMD3<Float>, in size: CGSize) -> CGPoint {
        ShelfCamera(size: size).project(point)
    }

    /// The row ends below the title at the back and above the scrubber at the front, fading out at both.
    private static func visibility(of center: SIMD3<Float>, camera: ShelfCamera) -> Float {
        guard camera.size.height > 0 else { return 1 }
        let top = Float(camera.project(center + [0, caseHeight / 2, 0]).y)
        let bottom = Float(camera.project(center - [0, caseHeight / 2, 0]).y)
        let height = Float(camera.size.height)
        // The margins clear the title and controls; a view smaller than a phone, such as a style preview, shrinks them.
        let scale = min(1, height / 700)
        let back = min(1, max(0, (top - 55 * scale) / (35 * scale)))
        let front = min(1, max(0, (height - 190 * scale - bottom) / (70 * scale)))
        return min(back, front)
    }

    private static func intersectsViewport(center: SIMD3<Float>, turn: simd_quatf, camera: ShelfCamera) -> Bool {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        let depth = thickness / 2
        for x in [-caseWidth / 2, caseWidth / 2] {
            for y in [-caseHeight / 2, caseHeight / 2] {
                for z in [-depth, depth] {
                    let point = camera.project(center + turn.act([x, y, z]))
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }
        return maxX > 0 && minX < camera.size.width && maxY > 0 && minY < camera.size.height
    }

    /// The albums kept as cases round `position`: as far back as the row is seen, and the few in front.
    static func window(count: Int, position: Double, size: CGSize) -> ClosedRange<Int>? {
        let base = Int(position.rounded(.down))
        let reach = reach(forHeight: size.height)
        let lower = max(0, base - Int(14 * reach))
        let upper = min(count - 1, base + Int(32 * reach))
        return lower <= upper ? lower...upper : nil
    }

    struct Pose {
        let place: SIMD3<Float>
        let turn: simd_quatf
        let opacity: Float
    }

    /// Where the case `d` albums along from the current one stands, `arrival` of the way into the opening;
    /// nil when it is not drawn.
    static func pose(offset d: Float, settled: Float, arrival: Float, camera: ShelfCamera) -> Pose? {
        // Opening: the row swings in from the right around its far end, curled, and straightens; after a beat the case in
        // front slides out.
        let pullOut = smoothstep(min(1, max(0, (arrival - 0.72) / 0.28)))
        let swingProgress = min(1, arrival / 0.6)
        let fadeIn = smoothstep(min(1, arrival / 0.12))
        let pop = smoothstep(max(0, 1 - abs(d))) * settled * pullOut
        let aside = smoothstep(min(1, max(0, -d))) * frontGap
        var place: SIMD3<Float> = [d * stagger + pop * Self.pullOut.x, pop * Self.pullOut.y, -d * spacing + aside + pop * Self.pullOut.z]
        var turn = simd_quatf(angle: pop * pullTurn, axis: [0, 1, 0])
        if swingProgress < 1 {
            // Nearer cases trail further behind, which bends the row into an arc.
            let lag = 0.4 * min(1, max(0, (swingPivot - d) / swingPivot))
            let settle = min(1, max(0, (swingProgress - lag) / 0.6))
            // Eases out gently, so the curled row stays on screen while it straightens instead of snapping into line.
            let swing = simd_quatf(angle: swingAngle * pow(1 - settle, 2), axis: [0, 1, 0])
            let pivot: SIMD3<Float> = [0, 0, -swingPivot * spacing]
            place = pivot + swing.act(place - pivot)
            turn = swing * turn
        }
        let opacity = max(pop, visibility(of: place, camera: camera)) * fadeIn
        guard opacity > 0.01, intersectsViewport(center: place, turn: turn, camera: camera) else { return nil }
        return Pose(place: place, turn: turn, opacity: opacity)
    }

    static func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    /// Every album the opening shows at some point, as the row swings in and comes to rest.
    static func entranceIndices(count: Int, position: Double, size: CGSize) -> [Int] {
        guard let window = window(count: count, position: position, size: size) else { return [] }
        let camera = ShelfCamera(size: size)
        return window.filter { index in
            (1...30).contains { pose(offset: Float(Double(index) - position), settled: 1, arrival: Float($0) / 30, camera: camera) != nil }
        }
    }

    /// The stretch round `position`, nearest first: where a pick lands, so its inserts load before the row gets there.
    static func openingOrder(count: Int, around position: Double) -> [Int] {
        guard count > 0 else { return [] }
        let base = min(max(Int(position.rounded()), 0), count - 1)
        return Array(max(0, base - 14)...min(count - 1, base + 32)).sorted { abs($0 - base) < abs($1 - base) }
    }

    /// Maps a layer of `size` onto four points on screen: top-left, top-right, bottom-right, bottom-left.
    static func mapping(_ size: CGSize, onto q: [CGPoint]) -> CATransform3D {
        let sx = q[0].x - q[1].x + q[2].x - q[3].x, sy = q[0].y - q[1].y + q[2].y - q[3].y
        let dx1 = q[1].x - q[2].x, dx2 = q[3].x - q[2].x, dy1 = q[1].y - q[2].y, dy2 = q[3].y - q[2].y
        let den = dx1 * dy2 - dx2 * dy1
        let g = den == 0 ? 0 : (sx * dy2 - dx2 * sy) / den
        let h = den == 0 ? 0 : (dx1 * sy - sx * dy1) / den
        var square = CATransform3DIdentity
        square.m11 = q[1].x - q[0].x + g * q[1].x
        square.m12 = q[1].y - q[0].y + g * q[1].y
        square.m14 = g
        square.m21 = q[3].x - q[0].x + h * q[3].x
        square.m22 = q[3].y - q[0].y + h * q[3].y
        square.m24 = h
        square.m41 = q[0].x
        square.m42 = q[0].y
        return CATransform3DConcat(CATransform3DMakeScale(1 / size.width, 1 / size.height, 1), square)
    }
}

/// The shelf's camera for one view size.
struct ShelfCamera {
    let size: CGSize
    let eye: SIMD3<Float>
    private let forward: SIMD3<Float>
    private let right: SIMD3<Float>
    private let up: SIMD3<Float>
    private let focal: Float
    private let elevation: Float

    init(size: CGSize) {
        let offset = ShelfGeometry.cameraOffset(for: size)
        self.size = size
        eye = ShelfGeometry.aim + offset
        forward = simd_normalize(-offset)
        right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        up = simd_cross(right, forward)
        focal = Float(ShelfGeometry.focal(forHeight: size.height))
        elevation = asin(offset.y / simd_length(offset))
    }

    /// Where a point in the scene lands in the view. Looking down tilts upright edges inward; this straightens them, like
    /// a shift lens, as if the camera looked level with the aim point kept where it was.
    func project(_ point: SIMD3<Float>) -> CGPoint {
        let v = point - eye
        let depth = simd_dot(v, forward)
        let x = focal * simd_dot(v, right) / depth
        let y = -focal * simd_dot(v, up) / depth
        let w = 1 - tan(elevation) * y / focal
        return CGPoint(x: size.width / 2 + CGFloat(x / w), y: size.height / 2 + CGFloat(y / cos(elevation) / w))
    }

    /// How far ahead of the camera a point is; nearer cases draw over further ones.
    func depth(of point: SIMD3<Float>) -> Float { simd_dot(point - eye, forward) }

    /// Whether a face turned this way, through this point, faces the camera.
    func sees(_ normal: SIMD3<Float>, at point: SIMD3<Float>) -> Bool { simd_dot(normal, eye - point) > 0 }
}
