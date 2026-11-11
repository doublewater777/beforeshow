import Metal
import RealityKit
import SwiftUI
import UIKit

/// The 3D record shelf: a row of CD cases under a RealityKit camera, the one in front pulled out beside the row.
@available(iOS 18.0, *)
struct ListeningPickShelf3D: View {
    let discs: [ListeningDisc]
    let position: Double
    /// Where a pick will land; its cases start loading before the row gets there.
    var landing: Int?
    /// 0 → 1 as the row arrives from its far end when the shelf opens.
    var entrance: Double = 1
    /// The scene is built; RealityKit takes a moment to start, so the entrance waits for this.
    var onReady: () -> Void = {}
    @State private var scene = ShelfScene3D()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let render = CGSize(width: size.width * ShelfScene3D.overscan, height: size.height * ShelfScene3D.overscan)
            RealityView { content in
                content.camera = .virtual
                // The far end of the row goes soft towards the top-right corner.
                if #available(iOS 26.0, *) {
                    content.renderingEffects.customPostProcessing = .effect(ShelfFarBlur(overscan: Float(ShelfScene3D.overscan)))
                }
                scene.install(in: &content)
                scene.update(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
                onReady()
            } update: { _ in
                scene.update(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
            }
            .frame(width: render.width, height: render.height)
            .projectionEffect(ShelfScene3D.levelling(in: render, view: size))
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

/// Runs `shelfFarBlur` (ListeningPickShelfBlur.metal) over each rendered frame.
@available(iOS 26.0, *)
private struct ShelfFarBlur: PostProcessEffect {
    let overscan: Float
    private var pipeline: (any MTLComputePipelineState)?

    init(overscan: Float) {
        self.overscan = overscan
    }

    mutating func prepare(for device: any MTLDevice) {
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "shelfFarBlur") else { return }
        pipeline = try? device.makeComputePipelineState(function: function)
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        guard let pipeline, let encoder = context.commandBuffer.makeComputeCommandEncoder() else { return }
        var overscan = overscan
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(context.targetColorTexture, index: 1)
        encoder.setBytes(&overscan, length: MemoryLayout<Float>.size, index: 0)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        let grid = MTLSize(width: context.targetColorTexture.width, height: context.targetColorTexture.height, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: group)
        encoder.endEncoding()
    }
}

@available(iOS 18.0, *)
@MainActor
final class ShelfScene3D {
    /// A real jewel case is 142 × 125 mm: a little wider than tall.
    static let caseWidth: Float = 1.14
    static let caseHeight: Float = 1
    static let thickness: Float = 0.085
    static let spacing: Float = 0.24
    /// Each case further back also sits a little to the right, so the row runs diagonally.
    static let stagger: Float = 0
    /// The picked case slides out sideways beside the row and stands facing you.
    static let pullOut: SIMD3<Float> = [1.5, 0.1, 0.15]
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
    static let fieldOfView: CGFloat = 30
    /// The scene renders a little beyond the view, so straightening the verticals leaves no empty corners.
    static let overscan: CGFloat = 1.25
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
    private static func renderFieldOfView(forHeight height: CGFloat) -> Float {
        Float(2 * atan(overscan * height / 2 / focal(forHeight: height)) * 180 / .pi)
    }
    private static func elevation(for size: CGSize) -> Float {
        let offset = cameraOffset(for: size)
        return asin(offset.y / simd_length(offset))
    }

    /// Looking down tilts upright edges inward. This straightens them, like a shift lens: the camera's
    /// image is re-projected as if it looked level, keeping the aim point where it was.
    static func levelling(in render: CGSize, view: CGSize) -> ProjectionTransform {
        let focal = focal(forHeight: view.height)
        let elevation = elevation(for: view)
        var level = CATransform3DIdentity
        level.m22 = 1 / CGFloat(cos(elevation))
        level.m24 = -CGFloat(tan(elevation)) / focal
        let centre = CGAffineTransform(translationX: -render.width / 2, y: -render.height / 2)
        return ProjectionTransform(centre)
            .concatenating(ProjectionTransform(level))
            .concatenating(ProjectionTransform(centre.inverted()))
    }

    /// Where the next case back in the row lands on screen, so a drag can keep the cases under the finger.
    static func screenStep(in size: CGSize) -> CGVector {
        let near = project([0, 0, 0], in: size)
        let far = project([0, 0, -spacing], in: size)
        return CGVector(dx: far.x - near.x, dy: far.y - near.y)
    }

    /// Where a point in the scene lands in the view.
    static func project(_ point: SIMD3<Float>, in size: CGSize) -> CGPoint {
        let offset = cameraOffset(for: size)
        let elevation = elevation(for: size)
        let eye = aim + offset
        let forward = simd_normalize(-offset)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        let up = simd_cross(right, forward)
        let focal = Float(focal(forHeight: size.height))
        let v = point - eye
        let depth = simd_dot(v, forward)
        let x = focal * simd_dot(v, right) / depth
        let y = -focal * simd_dot(v, up) / depth
        // The same straightening as `levelling`.
        let w = 1 - tan(elevation) * y / focal
        return CGPoint(x: size.width / 2 + CGFloat(x / w), y: size.height / 2 + CGFloat(y / cos(elevation) / w))
    }

    /// The row ends below the title at the back and above the scrubber at the front, fading out at both.
    private static func visibility(of center: SIMD3<Float>, in size: CGSize) -> Float {
        guard size.height > 0 else { return 1 }
        let top = Float(project(center + [0, caseHeight / 2, 0], in: size).y)
        let bottom = Float(project(center - [0, caseHeight / 2, 0], in: size).y)
        let height = Float(size.height)
        let back = min(1, max(0, (top - 55) / 35))
        let front = min(1, max(0, (height - 190 - bottom) / 70))
        return min(back, front)
    }

    private let anchor = Entity()
    private let camera = PerspectiveCamera()
    private var cases: [String: Entity] = [:]
    /// How fast the row is moving, in albums a second; a fast row stays one straight line.
    private var speed: Double = 0
    private var lastPosition: Double?
    private var lastTime: CFTimeInterval = 0

    @available(iOS 18.0, *)
    func install(in content: inout RealityViewCameraContent) {
        anchor.addChild(camera)

        let key = DirectionalLight()
        key.light.intensity = 1000
        key.light.color = UIColor(red: 1, green: 0.97, blue: 0.95, alpha: 1)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 16, depthBias: 2.5)
        key.look(at: [0, -0.5, -1], from: [2.4, 3.8, 2.2], relativeTo: nil, forward: .negativeZ)
        anchor.addChild(key)

        let fill = DirectionalLight()
        fill.light.intensity = 650
        fill.light.color = UIColor(red: 0.86, green: 0.84, blue: 1, alpha: 1)
        fill.look(at: [0, 0, -1], from: [-3, 0.8, 2.5], relativeTo: nil, forward: .negativeZ)
        anchor.addChild(fill)

        content.add(anchor)
    }

    func update(discs: [ListeningDisc], position: Double, landing: Int?, entrance: Double, size: CGSize) {
        guard !discs.isEmpty else { return }
        camera.camera.fieldOfViewInDegrees = Self.renderFieldOfView(forHeight: size.height)
        camera.look(at: Self.aim, from: Self.aim + Self.cameraOffset(for: size), relativeTo: nil, forward: .negativeZ)
        let base = Int(position.rounded(.down))
        let reach = Self.reach(forHeight: size.height)
        let lower = max(0, base - Int(14 * reach))
        let upper = min(discs.count - 1, base + Int(32 * reach))
        guard lower <= upper else { return }
        let now = CACurrentMediaTime()
        if let lastPosition, now > lastTime {
            speed = speed * 0.5 + abs(position - lastPosition) / max(now - lastTime, 1.0 / 120) * 0.5
        }
        lastPosition = position
        lastTime = now
        // Cases only slide out as the row slows down, like the original: nothing pops while flicking past.
        let settled = 1 - smoothstep(Float(min(1, max(0, (speed - 3) / 6))))
        // Opening: the row swings in from the right around its far end, curled, and straightens; then the front case slides out.
        let arrival = Float(entrance)
        let pullOut = smoothstep(min(1, max(0, (arrival - 0.75) / 0.25)))
        let swingProgress = min(1, arrival / 0.8)
        let fadeIn = smoothstep(min(1, arrival / 0.12))
        // Cases are kept well past the visible stretch, so scrolling back never rebuilds them.
        var kept = Set(discs[max(0, lower - 40)...min(discs.count - 1, upper + 40)].map(\.id))
        if let landing {
            // Nearest the landing first: those are the covers on screen when the row stops.
            let ahead = (max(0, landing - 14)...min(discs.count - 1, landing + 32)).sorted { abs($0 - landing) < abs($1 - landing) }
            for index in ahead where cases[discs[index].id] == nil {
                makeCase(discs[index]).isEnabled = false
            }
            kept.formUnion(ahead.map { discs[$0].id })
        }
        for (id, entity) in cases where !kept.contains(id) {
            entity.removeFromParent()
            cases[id] = nil
        }
        for (id, entity) in cases where !discs[lower...upper].contains(where: { $0.id == id }) {
            entity.isEnabled = false
        }
        for index in lower...upper {
            let disc = discs[index]
            let entity = cases[disc.id] ?? makeCase(disc)
            let d = Float(Double(index) - position)
            let pop = smoothstep(max(0, 1 - abs(d))) * settled * pullOut
            let aside = smoothstep(min(1, max(0, -d))) * Self.frontGap
            var place: SIMD3<Float> = [d * Self.stagger + pop * Self.pullOut.x, pop * Self.pullOut.y, -d * Self.spacing + aside + pop * Self.pullOut.z]
            var turn = simd_quatf(angle: pop * Self.pullTurn, axis: [0, 1, 0])
            if swingProgress < 1 {
                // Nearer cases trail further behind, which bends the row into an arc.
                let lag = 0.5 * min(1, max(0, (Self.swingPivot - d) / Self.swingPivot))
                let settle = min(1, max(0, (swingProgress - lag) / 0.5))
                let swing = simd_quatf(angle: Self.swingAngle * pow(1 - settle, 3), axis: [0, 1, 0])
                let pivot: SIMD3<Float> = [0, 0, -Self.swingPivot * Self.spacing]
                place = pivot + swing.act(place - pivot)
                turn = swing * turn
            }
            entity.position = place
            entity.orientation = turn
            let opacity = max(pop, Self.visibility(of: entity.position, in: size)) * fadeIn
            entity.components.set(OpacityComponent(opacity: opacity))
            entity.isEnabled = opacity > 0.01
        }
    }

    private func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    /// Every case shares the same meshes and plastic; only the printed insert differs.
    private struct Parts {
        let lid: MeshResource
        let tray: MeshResource
        let hinge: MeshResource
        let insert: MeshResource
        let lidPlastic: PhysicallyBasedMaterial
        let trayPlastic: PhysicallyBasedMaterial
        let hingePlastic: PhysicallyBasedMaterial
        let placeholder: PhysicallyBasedMaterial
    }

    private lazy var parts: Parts = {
        // Pale lavender plastic: a clear lid over a slightly darker tray, so the edges read as two thin layers.
        func plastic(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PhysicallyBasedMaterial {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: red, green: green, blue: blue, alpha: 1))
            material.roughness = 0.42
            material.metallic = 0.0
            material.clearcoat = 0.6
            material.clearcoatRoughness = 0.12
            return material
        }
        var placeholder = PhysicallyBasedMaterial()
        placeholder.baseColor = .init(tint: UIColor(white: 0.25, alpha: 1))
        let lidDepth = Self.thickness * 0.38
        return Parts(
            lid: .generateBox(width: Self.caseWidth, height: Self.caseHeight, depth: lidDepth, cornerRadius: 0.01),
            tray: .generateBox(width: Self.caseWidth - 0.03, height: Self.caseHeight - 0.03, depth: Self.thickness - lidDepth, cornerRadius: 0.01),
            hinge: .generateBox(width: 0.04, height: Self.caseHeight, depth: Self.thickness + 0.006),
            insert: .generatePlane(width: 1.06, height: 0.96),
            lidPlastic: plastic(0.84, 0.82, 0.9),
            trayPlastic: plastic(0.66, 0.64, 0.74),
            hingePlastic: plastic(0.9, 0.89, 0.95),
            placeholder: placeholder
        )
    }()

    private func makeCase(_ disc: ListeningDisc) -> Entity {
        let parts = parts
        let root = Entity()
        let lidDepth = Self.thickness * 0.38
        let trayDepth = Self.thickness - lidDepth
        let lid = ModelEntity(mesh: parts.lid, materials: [parts.lidPlastic])
        lid.position = [0, 0, Self.thickness / 2 - lidDepth / 2]
        root.addChild(lid)
        let tray = ModelEntity(mesh: parts.tray, materials: [parts.trayPlastic])
        tray.position = [0.015, 0, -Self.thickness / 2 + trayDepth / 2]
        root.addChild(tray)
        let hinge = ModelEntity(mesh: parts.hinge, materials: [parts.hingePlastic])
        hinge.position = [-Self.caseWidth / 2 + 0.02, 0, 0]
        root.addChild(hinge)
        let insert = ModelEntity(mesh: parts.insert, materials: [parts.placeholder])
        insert.position = [0.03, 0, Self.thickness / 2 + 0.002]
        root.addChild(insert)

        anchor.addChild(root)
        cases[disc.id] = root
        loadInsert(for: disc, into: insert)
        return root
    }

    /// The insert is drawn off the main thread; only the finished texture lands on the case.
    private func loadInsert(for disc: ListeningDisc, into insert: ModelEntity) {
        let title = disc.title.uppercased()
        let year = disc.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
        Task { @MainActor in
            guard let url = disc.artworkURL, let cover = await ShowCoverImageCache.shared.image(from: url) else { return }
            guard let cgImage = await Task.detached(priority: .userInitiated, operation: {
                ShelfInsertArt.draw(title: title, year: year, cover: cover)
            }).value,
                let texture = try? await TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(texture: .init(texture))
            material.roughness = 0.35
            material.metallic = 0.0
            material.clearcoat = 1.0
            material.clearcoatRoughness = 0.05
            insert.model?.materials = [material]
        }
    }
}

/// The printed insert: spine band with the title, then the cover.
private enum ShelfInsertArt {
    static let size = CGSize(width: 416, height: 376)
    static let band: CGFloat = 45

    nonisolated static func draw(title: String, year: String?, cover: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let tone = ListeningArtworkTone.average(cover)
            let spine = tone.map(ListeningArtworkTone.spine(for:))
            let fill = spine?.fill ?? UIColor(white: 0.12, alpha: 1)
            let ink = spine?.isLight == true ? UIColor.black.withAlphaComponent(0.8) : .white
            fill.setFill()
            context.fill(CGRect(x: 0, y: 0, width: band, height: size.height))

            // Cover, filling the rest of the insert.
            let area = CGRect(x: band, y: 0, width: size.width - band, height: size.height)
            let scale = max(area.width / cover.size.width, area.height / cover.size.height)
            let drawn = CGSize(width: cover.size.width * scale, height: cover.size.height * scale)
            context.cgContext.saveGState()
            context.cgContext.clip(to: area)
            cover.draw(in: CGRect(x: area.midX - drawn.width / 2, y: area.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
            context.cgContext.restoreGState()

            // Title up the spine, year at its foot.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .heavy), .kern: 1.6,
                .foregroundColor: ink, .paragraphStyle: paragraph,
            ]
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: band / 2, y: size.height * 0.42)
            context.cgContext.rotate(by: -.pi / 2)
            (title as NSString).draw(in: CGRect(x: -132, y: -11, width: 264, height: 22), withAttributes: titleAttributes)
            context.cgContext.restoreGState()
            if let year {
                let yearAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: ink, .paragraphStyle: paragraph,
                ]
                (year as NSString).draw(in: CGRect(x: 0, y: size.height - 40, width: band, height: 18), withAttributes: yearAttributes)
            }
        }
        return image.cgImage
    }
}
