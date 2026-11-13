import QuartzCore
import simd
import UIKit

/// One jewel case as flat layers, each face mapped onto where the case's corners land on screen.
@MainActor
final class ShelfCaseLayer {
    let root = CALayer()
    private let insert = CALayer()
    /// In `Shape.all`'s order.
    private var faces: [(layer: CALayer, shade: CALayer)] = []

    /// A face of the case.
    private struct Shape {
        /// Top-left, top-right, bottom-right, bottom-left as the layer is drawn, in the case's own space.
        let corners: [SIMD3<Float>]
        let normal: SIMD3<Float>
        var centre: SIMD3<Float> { (corners[0] + corners[2]) / 2 }

        private static let w = ShelfGeometry.caseWidth / 2, h = ShelfGeometry.caseHeight / 2, t = ShelfGeometry.thickness / 2
        static let front = Shape(corners: [[-w, h, t], [w, h, t], [w, -h, t], [-w, -h, t]], normal: [0, 0, 1])
        /// The open edge, front to back.
        static let side = Shape(corners: [[w, h, t], [w, h, -t], [w, -h, -t], [w, -h, t]], normal: [1, 0, 0])
        /// Back to front.
        static let top = Shape(corners: [[-w, h, -t], [w, h, -t], [w, h, t], [-w, h, t]], normal: [0, 1, 0])
        /// Only turns into view while the row swings in.
        static let hinge = Shape(corners: [[-w, h, -t], [-w, h, t], [-w, -h, t], [-w, -h, -t]], normal: [-1, 0, 0])
        static let all = [front, side, top, hinge]
    }

    /// Where a case's layers go for one pose, worked out once for the case and its soft copy.
    struct Placement {
        let opacity: Float
        let depth: Float
        /// Each face's corners on screen and how much it darkens; nil when it is turned away.
        let faces: [(corners: [CGPoint], darkening: Float)?]
        /// The case's outline on screen.
        let bounds: CGRect
    }

    /// The plastic as it looks at rest under the shelf's light.
    private enum Colour {
        static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
            CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        }
        static let lid = rgb(209, 205, 222)
        static let hinge = rgb(221, 217, 230)
        static let sideLid = rgb(197, 193, 209)
        static let sideTray = rgb(124, 119, 134)
        static let topLid = rgb(205, 200, 218)
        static let topTray = rgb(176, 170, 192)
        static let hingeTop = rgb(226, 222, 236)
        static let hingeSide = rgb(192, 188, 204)
        static let placeholder = rgb(64, 64, 64)
    }

    init() {
        root.anchorPoint = .zero
        root.allowsGroupOpacity = false
        root.isHidden = true
        typealias G = ShelfGeometry
        // Points per scene unit inside a face; the mapping scales each face onto the screen.
        func u(_ value: Float) -> CGFloat { CGFloat(value) * 100 }
        let width = u(G.caseWidth), height = u(G.caseHeight), depth = u(G.thickness), lid = u(G.lidDepth), hinge = u(G.hingeWidth)
        insert.frame = CGRect(
            x: u(G.caseWidth / 2 + G.insertShift - G.insertSize.x / 2), y: u((G.caseHeight - G.insertSize.y) / 2),
            width: u(G.insertSize.x), height: u(G.insertSize.y)
        )
        insert.backgroundColor = Colour.placeholder
        insert.contentsGravity = .resize
        insert.minificationFilter = .trilinear
        insert.allowsEdgeAntialiasing = true
        // The front, the open edge (lid then tray), the top (tray then lid, the hinge's end at the left) and the hinge.
        addFace(CGSize(width: width, height: height), Colour.lid,
                [Self.block(CGRect(x: 0, y: 0, width: hinge, height: height), Colour.hinge), insert])
        addFace(CGSize(width: depth, height: height), Colour.sideTray,
                [Self.block(CGRect(x: 0, y: 0, width: lid, height: height), Colour.sideLid)])
        addFace(CGSize(width: width, height: depth), Colour.topTray,
                [Self.block(CGRect(x: 0, y: depth - lid, width: width, height: lid), Colour.topLid),
                 Self.block(CGRect(x: 0, y: 0, width: hinge, height: depth), Colour.hingeTop)])
        addFace(CGSize(width: depth, height: height), Colour.hingeSide, [])
    }

    func show(_ print: CGImage) {
        insert.contents = print
    }

    static func placement(_ pose: ShelfGeometry.Pose, camera: ShelfCamera) -> Placement {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        let faces = Shape.all.map { shape -> (corners: [CGPoint], darkening: Float)? in
            let normal = pose.turn.act(shape.normal)
            guard camera.sees(normal, at: pose.place + pose.turn.act(shape.centre)) else { return nil }
            let corners = shape.corners.map { camera.project(pose.place + pose.turn.act($0)) }
            for corner in corners {
                minX = min(minX, corner.x)
                maxX = max(maxX, corner.x)
                minY = min(minY, corner.y)
                maxY = max(maxY, corner.y)
            }
            return (corners, Light.darkening(from: shape.normal, to: normal))
        }
        return Placement(
            opacity: pose.opacity, depth: camera.depth(of: pose.place), faces: faces,
            bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        )
    }

    func place(_ placement: Placement) {
        root.isHidden = false
        root.opacity = placement.opacity
        // Nearer cases draw over further ones.
        root.zPosition = CGFloat(-placement.depth)
        for (face, place) in zip(faces, placement.faces) {
            face.layer.isHidden = place == nil
            guard let place else { continue }
            face.layer.transform = ShelfGeometry.mapping(face.layer.bounds.size, onto: place.corners)
            face.shade.opacity = place.darkening
        }
    }

    private func addFace(_ size: CGSize, _ colour: CGColor, _ content: [CALayer]) {
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.backgroundColor = colour
        layer.allowsEdgeAntialiasing = true
        layer.allowsGroupOpacity = false
        content.forEach(layer.addSublayer)
        let shade = Self.block(layer.bounds, UIColor.black.cgColor)
        shade.opacity = 0
        layer.addSublayer(shade)
        root.addSublayer(layer)
        faces.append((layer, shade))
    }

    private static func block(_ frame: CGRect, _ colour: CGColor) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.backgroundColor = colour
        layer.allowsEdgeAntialiasing = true
        return layer
    }

    /// The key light high on the right and a cool fill from the left. A face turned away from them while the row swings
    /// darkens from its look at rest.
    private enum Light {
        static let key = simd_normalize(SIMD3<Float>(2.4, 4.3, 3.2))
        static let fill = simd_normalize(SIMD3<Float>(-3, 0.8, 3.5))

        static func level(_ normal: SIMD3<Float>) -> Float {
            0.4 + 0.6 * max(0, simd_dot(normal, key)) + 0.4 * max(0, simd_dot(normal, fill))
        }

        static func darkening(from rest: SIMD3<Float>, to normal: SIMD3<Float>) -> Float {
            min(0.5, max(0, 1 - level(normal) / level(rest)))
        }
    }
}
