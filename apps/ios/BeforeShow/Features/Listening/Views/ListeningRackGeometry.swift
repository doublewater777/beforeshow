import SwiftUI
import simd

/// Where one standing case sits: translation, turn about its own centre, and its finish.
struct ListeningRackPose: VectorArithmetic {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var rotation: Double = 0
    var opacity: Double = 1
    var peek: Double = ListeningRackLayout.peekIn
    var lit: Double = 0

    private var values: [Double] { [x, y, z, rotation, opacity, peek, lit] }

    private init(_ v: [Double]) {
        (x, y, z, rotation, opacity, peek, lit) = (v[0], v[1], v[2], v[3], v[4], v[5], v[6])
    }

    init(x: Double = 0, y: Double = 0, z: Double = 0, rotation: Double = 0, opacity: Double = 1) {
        (self.x, self.y, self.z, self.rotation, self.opacity) = (x, y, z, rotation, opacity)
    }

    static var zero: Self { Self([0, 0, 0, 0, 0, 0, 0]) }
    static func + (a: Self, b: Self) -> Self { Self(zip(a.values, b.values).map(+)) }
    static func - (a: Self, b: Self) -> Self { Self(zip(a.values, b.values).map(-)) }
    mutating func scale(by rhs: Double) { self = Self(values.map { $0 * rhs }) }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

enum ListeningRackLayout {
    static let caseSize: CGFloat = 132
    static let spine: CGFloat = 18
    static let discSize: CGFloat = 120
    static let perspective: Double = 440
    static let perspectiveY: Double = 94
    static let shelfTop: Double = 28
    static let canvasHeight: CGFloat = 178
    static let plateHeight: CGFloat = 28
    static let slotHeight: CGFloat = canvasHeight + BSLayout.minTouchTarget
    static let edgeFade: CGFloat = 0.12

    static let swipeThreshold: CGFloat = 14
    static let followThreshold: CGFloat = 6
    static let flickWeight: CGFloat = 0.25
    static let swipeStep: CGFloat = 44
    static let scrubThreshold: CGFloat = 8
    static let scrubStep: CGFloat = 12
    static let peekIn: Double = 4
    static let peekOut: Double = 54
    static let discOutShift: Double = 14
    static let discOutGap: Double = 30
    static let visibleReach = 3
    static let renderReach = 4
    static let placeholderCount = 3

    static let motion = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6)
    static let scrubMotion = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)
    static let discDelay = 0.15
    static let placeholderDelay = Duration.milliseconds(600)
    static let prefetchDelay = Duration.milliseconds(500)

    /// Spine offsets from the centre: the first neighbour clears the pulled-out case, then gaps widen.
    static func spineX(_ k: Int) -> Double {
        var x: Double = k > 0 ? 98 : 0
        for _ in 1..<max(1, min(k, 11)) { x += 22 + 0.2 * x }
        return x
    }

    static func pose(at d: Int, discOut: Bool) -> ListeningRackPose {
        let shift = discOut ? -discOutShift : 0
        guard d != 0 else { return ListeningRackPose(x: shift, y: -16, z: 96, rotation: -90) }
        let k = abs(d), s = Double(d.signum())
        return ListeningRackPose(
            x: s * spineX(k) + (s > 0 && discOut ? discOutGap : 0) + shift,
            z: -6 * Double(k - 1),
            rotation: s * min(14 + 8 * Double(k - 1), 38),
            opacity: k > visibleReach ? 0 : 1
        )
    }

    /// A pose between two resting slots, so the row can sit anywhere under the finger.
    static func pose(following d: Double, discOut: Bool) -> ListeningRackPose {
        let lower = Int(d.rounded(.down)), t = d - Double(lower)
        var result = Self.pose(at: lower, discOut: discOut)
        if t > 0 {
            var step = Self.pose(at: lower + 1, discOut: discOut)
            step -= result
            step.scale(by: t)
            result += step
        }
        result.lit = max(0, 1 - abs(d))
        return result
    }

    static func away(side: Double) -> ListeningRackPose {
        ListeningRackPose(x: side * 300, z: -60, rotation: side * 38, opacity: 0)
    }

    /// Cases travelled for a drag, resisting past either end of the row.
    static func followShift(from index: Int, translation: CGFloat, count: Int) -> Double {
        let raw = Double(translation / swipeStep)
        let low = -Double(max(count - 1 - index, 0)), high = Double(index)
        if raw > high { let over = raw - high; return high + over / (1 + over * 2) }
        if raw < low { let over = low - raw; return low - over / (1 + over * 2) }
        return raw
    }

    static func swipeIndex(from index: Int, translation: CGFloat, predicted: CGFloat? = nil, count: Int) -> Int {
        guard abs(translation) >= swipeThreshold else { return index }
        let travel = translation + ((predicted ?? translation) - translation) * flickWeight
        let steps = max(1, Int((abs(travel) / swipeStep).rounded()))
        return clamp(index - Int(translation.sign == .minus ? -1 : 1) * steps, count)
    }

    static func scrubIndex(from index: Int, translation: CGFloat, count: Int) -> Int {
        clamp(index + Int((translation / scrubStep).rounded()), count)
    }

    /// Which neighbour (relative to the focus) a tap at `x` from the centre lands on.
    static func tapOffset(atX x: CGFloat, focus: Int, count: Int, discOut: Bool, halfWidth: CGFloat) -> Int? {
        func center(_ d: Int) -> Double {
            let px = pose(at: d, discOut: discOut).x
            return d == 0 ? px : px - Double(d.signum()) * 0.13 * abs(px)
        }
        let x0 = pose(at: 0, discOut: discOut).x
        let edgeL = x0 - 72, edgeR = x0 + 72 + (discOut ? discOutGap : 0)
        let half = Double(halfWidth)
        for d in -visibleReach...visibleReach where (0..<count).contains(focus + d) {
            let a: Double, b: Double
            if d == 0 {
                (a, b) = (edgeL, edgeR)
            } else if d < 0 {
                b = d == -1 ? edgeL : (center(d) + center(d + 1)) / 2
                a = d == -visibleReach || focus + d == 0 ? -half : (center(d) + center(d - 1)) / 2
            } else {
                a = d == 1 ? edgeR : (center(d) + center(d - 1)) / 2
                b = d == visibleReach || focus + d == count - 1 ? half : (center(d) + center(d + 1)) / 2
            }
            if (a..<b).contains(Double(x)) { return d }
        }
        return nil
    }

    private static func clamp(_ index: Int, _ count: Int) -> Int {
        min(max(index, 0), max(count - 1, 0))
    }
}

/// One shared camera for the whole shelf, so every case recedes toward the same vanishing point.
struct ListeningRackProjector {
    let width: CGFloat

    private typealias L = ListeningRackLayout

    static func translate(_ x: Double, _ y: Double, _ z: Double = 0) -> simd_double4x4 {
        simd_double4x4(rows: [[1, 0, 0, x], [0, 1, 0, y], [0, 0, 1, z], [0, 0, 0, 1]])
    }

    static func rotateY(_ degrees: Double) -> simd_double4x4 {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return simd_double4x4(rows: [[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]])
    }

    static func rotateX(_ degrees: Double) -> simd_double4x4 {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return simd_double4x4(rows: [[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]])
    }

    /// Camera and the shelf's origin (horizontal centre, top of the standing cases).
    var stage: simd_double4x4 {
        let ox = Double(width) / 2, oy = L.perspectiveY
        let camera = simd_double4x4(rows: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, -1 / L.perspective, 1]])
        return Self.translate(ox, oy) * camera * Self.translate(-ox, -oy) * Self.translate(ox, L.shelfTop)
    }

    /// A case is a box one spine wide and one cover deep, turning about its own centre.
    func box(_ pose: ListeningRackPose) -> simd_double4x4 {
        let half = Double(L.spine) / 2, depth = Double(L.caseSize)
        return stage
            * Self.translate(-half, 0)
            * Self.translate(half, depth / 2, -depth / 2)
            * Self.translate(pose.x, pose.y, pose.z)
            * Self.rotateY(pose.rotation)
            * Self.translate(-half, -depth / 2, depth / 2)
    }

    static func effect(_ m: simd_double4x4) -> ProjectionTransform {
        var t = ProjectionTransform()
        t.m11 = m[0][0]; t.m12 = m[0][1]; t.m13 = m[0][3]
        t.m21 = m[1][0]; t.m22 = m[1][1]; t.m23 = m[1][3]
        t.m31 = m[3][0]; t.m32 = m[3][1]; t.m33 = m[3][3]
        return t
    }

    static func project(_ m: simd_double4x4, _ point: CGPoint) -> CGPoint? {
        let p = m * SIMD4(Double(point.x), Double(point.y), 0, 1)
        guard p.w > 0.01 else { return nil }
        return CGPoint(x: p.x / p.w, y: p.y / p.w)
    }

    /// Back-facing planes are culled, as with `backface-visibility: hidden`.
    static func faces(_ m: simd_double4x4, size: CGSize) -> Bool {
        guard let o = project(m, .zero),
              let a = project(m, CGPoint(x: size.width, y: 0)),
              let b = project(m, CGPoint(x: 0, y: size.height)) else { return false }
        return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) > 0
    }

    static func bounds(_ m: simd_double4x4, size: CGSize) -> CGRect? {
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        let points = corners.compactMap { project(m, $0) }
        guard points.count == 4 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

/// Face placements inside a case box (spine at the front, covers on either side, disc between).
enum ListeningRackFace {
    private typealias P = ListeningRackProjector
    private static let spine = Double(ListeningRackLayout.spine)
    private static let depth = Double(ListeningRackLayout.caseSize)

    static let front = matrix_identity_double4x4
    static var right: simd_double4x4 { P.translate(spine, 0) * P.rotateY(90) }
    static var left: simd_double4x4 { P.rotateY(-90) * P.translate(-depth, 0) }
    static var back: simd_double4x4 {
        P.translate(spine / 2, 0) * P.translate(0, 0, -depth) * P.rotateY(180) * P.translate(-spine / 2, 0)
    }
    static func disc(peek: Double) -> simd_double4x4 {
        P.translate(spine / 2, 0) * P.rotateY(90) * P.translate(peek, 6)
    }
}
