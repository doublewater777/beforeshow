import RealityKit
import SwiftUI
import UIKit

/// The 3D record shelf: a row of CD cases under a RealityKit camera, the one in front pulled out beside the row.
@available(iOS 18.0, *)
struct ListeningPickShelf3D: View {
    let discs: [ListeningDisc]
    let position: Double
    /// Where a pick will land; its inserts load before the row gets there.
    var landing: Int?
    /// 0 → 1 as the row arrives from its far end when the shelf opens.
    var entrance: Double = 1
    /// The opening is ready to play: RealityKit has started and every case the swing shows is printed.
    var onReady: () -> Void = {}
    @State private var scene = ShelfScene3D()
    /// Defer RealityKit mounting without adding a fixed delay.
    @State private var isMounted = false
    /// The row's first frames render unseen, so the swing plays on built cases and compiled materials.
    @State private var isRevealed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                if isMounted {
                    stage(in: proxy.size)
                }
            }
            // Inserts load while RealityKit starts: the cases the swing shows first, nearest the opening album first.
            .task(id: discs.map(\.id)) {
                await scene.preload(discs, around: position, size: proxy.size)
            }
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            isMounted = true
        }
    }

    private func stage(in size: CGSize) -> some View {
        let render = CGSize(width: size.width * ShelfScene3D.overscan, height: size.height * ShelfScene3D.overscan)
        return RealityView { content in
            content.camera = .virtual
            // The far end of the row goes soft towards the top-right corner.
            if #available(iOS 26.0, *) {
                content.renderingEffects.customPostProcessing = .effect(ShelfFarBlur(overscan: Float(ShelfScene3D.overscan)))
            }
            scene.install(in: &content)
            scene.beginOpening(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
        } update: { _ in
            scene.update(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
        }
        .frame(width: render.width, height: render.height)
        .projectionEffect(ShelfScene3D.levelling(in: render, view: size))
        .frame(width: size.width, height: size.height)
        .clipped()
        .opacity(isRevealed ? 1 : 0)
        .task {
            await scene.waitForOpening()
            guard !Task.isCancelled else { return }
            isRevealed = true
            onReady()
        }
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
        // The margins clear the title and controls; a view smaller than a phone, such as a style preview, shrinks them.
        let scale = min(1, height / 700)
        let back = min(1, max(0, (top - 55 * scale) / (35 * scale)))
        let front = min(1, max(0, (height - 190 * scale - bottom) / (70 * scale)))
        return min(back, front)
    }

    private static func intersectsViewport(center: SIMD3<Float>, turn: simd_quatf, size: CGSize) -> Bool {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        // Include the hinge, which is slightly deeper than the lid and tray.
        let depth = (thickness + 0.006) / 2
        for x in [-caseWidth / 2, caseWidth / 2] {
            for y in [-caseHeight / 2, caseHeight / 2] {
                for z in [-depth, depth] {
                    let point = project(center + turn.act([x, y, z]), in: size)
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }
            }
        }
        return maxX > 0 && minX < size.width && maxY > 0 && minY < size.height
    }

    /// The albums kept as cases round `position`: as far back as the row is seen, and the few in front.
    private static func window(count: Int, position: Double, size: CGSize) -> ClosedRange<Int>? {
        let base = Int(position.rounded(.down))
        let reach = reach(forHeight: size.height)
        let lower = max(0, base - Int(14 * reach))
        let upper = min(count - 1, base + Int(32 * reach))
        return lower <= upper ? lower...upper : nil
    }

    /// Where the case `d` albums along from the current one stands, `arrival` of the way into the opening;
    /// nil when it is not drawn.
    private static func pose(offset d: Float, settled: Float, arrival: Float, size: CGSize) -> (place: SIMD3<Float>, turn: simd_quatf, opacity: Float)? {
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
        let opacity = max(pop, visibility(of: place, in: size)) * fadeIn
        guard opacity > 0.01, intersectsViewport(center: place, turn: turn, size: size) else { return nil }
        return (place, turn, opacity)
    }

    private static func smoothstep(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    /// Every album the opening shows at some point, as the row swings in and comes to rest.
    static func entranceIndices(count: Int, position: Double, size: CGSize) -> [Int] {
        guard let window = window(count: count, position: position, size: size) else { return [] }
        return window.filter { index in
            (1...30).contains { pose(offset: Float(Double(index) - position), settled: 1, arrival: Float($0) / 30, size: size) != nil }
        }
    }

    /// The swing starts once every case it shows is printed, or this long after RealityKit has drawn its first frame:
    /// a cold start spends its first frame compiling shaders, and the prints queue behind it.
    static let openingBudget: Duration = .milliseconds(450)

    static func isOpeningPrinted(cases: [String], sinceFirstFrame: Duration?, isSettled: (String) -> Bool) -> Bool {
        cases.allSatisfy(isSettled) || sinceFirstFrame.map { $0 >= openingBudget } == true
    }

    private struct Request {
        let discs: [ListeningDisc]
        let position: Double
        let landing: Int?
        let entrance: Double
        let size: CGSize
    }

    private enum Opening {
        case pending
        /// Hidden: the row stands at rest so its first frames draw unseen; the swing waits for the prints of these cases.
        case warming(cases: [String])
        case done
    }

    // Made on first use: the first entity of a launch starts RealityKit, which must wait until the scene mounts.
    private lazy var anchor = Entity()
    private lazy var camera = PerspectiveCamera()
    private var opening = Opening.pending
    /// The latest row asked for; held back while the opening warms up.
    private var request: Request?
    private var frames = 0
    /// When the second scene update came, which waits on the first frame being drawn.
    private var firstFrame: ContinuousClock.Instant?
    private var frameUpdates: EventSubscription?
    private var cases: [String: Entity] = [:]
    /// Printed inserts by disc, kept so a case made again later needs no new drawing.
    private var loadedInserts: [String: PhysicallyBasedMaterial] = [:]
    private var retainedInsertIDs: Set<String>?
    private var loadingInserts: Set<String> = []
    /// No artwork, or it would not load: the opening does not wait on these.
    private var failedInserts: Set<String> = []
    /// Cases made while their insert was still loading.
    private var waitingInserts: [String: [ModelEntity]] = [:]
    /// How fast the row is moving, in albums a second; a fast row stays one straight line.
    private var speed: Double = 0
    private var lastPosition: Double?
    private var lastTime: CFTimeInterval = 0
    private var lastLanding: Int?

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
        frameUpdates = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.frames == 1 { self.firstFrame = .now }
                self.frames += 1
            }
        }
    }

    func update(discs: [ListeningDisc], position: Double, landing: Int?, entrance: Double, size: CGSize) {
        let request = Request(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
        self.request = request
        if case .warming = opening { return }
        apply(request)
    }

    /// Builds the opening while the view is hidden: every case the swing will show, so the swing itself builds none,
    /// and the row at rest, so its first frames compile the materials and draw the prints unseen.
    func beginOpening(discs: [ListeningDisc], position: Double, landing: Int?, entrance: Double, size: CGSize) {
        request = Request(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
        guard !discs.isEmpty, size.width > 0, size.height > 0 else {
            opening = .done
            return
        }
        let entrance = Self.entranceIndices(count: discs.count, position: position, size: size)
        for index in entrance {
            (cases[discs[index].id] ?? makeCase(discs[index], loadsInsert: false)).isEnabled = false
        }
        apply(Request(discs: discs, position: position, landing: landing, entrance: 1, size: size))
        opening = .warming(cases: entrance.map { discs[$0].id })
    }

    /// Returns once the opening can play in view: its cases printed (within the budget) and drawn at rest, then set
    /// back to where the swing starts.
    func waitForOpening() async {
        while case .pending = opening {
            guard (try? await Task.sleep(for: .milliseconds(8))) != nil else { return }
        }
        guard case let .warming(ids) = opening else { return }
        while !Self.isOpeningPrinted(cases: ids, sinceFirstFrame: firstFrame?.duration(to: .now), isSettled: isSettled) {
            guard (try? await Task.sleep(for: .milliseconds(16))) != nil else { return }
        }
        await renderedFrames(2)
        opening = .done
        if let request { apply(request) }
        // The view comes into sight only after the frame showing the swing's start, never the hidden row at rest.
        await renderedFrames(2)
    }

    private func isSettled(_ id: String) -> Bool {
        loadedInserts[id] != nil || !loadingInserts.contains(id) && failedInserts.contains(id)
    }

    /// The opening has played: the swing is over, or there was none.
    private var isAtRest: Bool {
        guard case .done = opening else { return false }
        return (request?.entrance ?? 1) >= 1
    }

    private func renderedFrames(_ count: Int) async {
        let target = frames + count
        for _ in 0..<25 where frames < target {
            guard (try? await Task.sleep(for: .milliseconds(8))) != nil else { return }
        }
    }

    private func apply(_ request: Request) {
        let (discs, position, landing, size) = (request.discs, request.position, request.landing, request.size)
        guard !discs.isEmpty, size.width > 0, size.height > 0,
              let window = Self.window(count: discs.count, position: position, size: size) else { return }
        camera.camera.fieldOfViewInDegrees = Self.renderFieldOfView(forHeight: size.height)
        camera.look(at: Self.aim, from: Self.aim + Self.cameraOffset(for: size), relativeTo: nil, forward: .negativeZ)
        let (lower, upper) = (window.lowerBound, window.upperBound)
        let now = CACurrentMediaTime()
        if let lastPosition, now > lastTime {
            speed = speed * 0.5 + abs(position - lastPosition) / max(now - lastTime, 1.0 / 120) * 0.5
        }
        lastPosition = position
        lastTime = now
        // Cases only slide out as the row slows down, like the original: nothing pops while flicking past.
        let settled = 1 - Self.smoothstep(Float(min(1, max(0, (speed - 3) / 6))))
        // Keep nearby inserts warm independently of which cases are currently in the scene.
        var kept = Set(discs[max(0, lower - 40)...min(discs.count - 1, upper + 40)].map(\.id))
        if let landing {
            let ahead = Self.openingOrder(count: discs.count, around: Double(landing)).map { discs[$0] }
            kept.formUnion(ahead.map(\.id))
            if landing != lastLanding {
                // Continue loading when the pick settles, so its now-visible insert can still arrive.
                Task { await preload(ahead) }
            }
        }
        lastLanding = landing
        retainedInsertIDs = kept
        for id in loadedInserts.keys where !kept.contains(id) {
            loadedInserts[id] = nil
        }
        for index in window {
            let disc = discs[index]
            // Cases within reach that are out of sight are only switched off, so the row never rebuilds them mid-motion.
            guard let pose = Self.pose(offset: Float(Double(index) - position), settled: settled, arrival: Float(request.entrance), size: size) else {
                cases[disc.id]?.isEnabled = false
                continue
            }
            let entity = cases[disc.id] ?? makeCase(disc)
            if !entity.isEnabled { entity.isEnabled = true }
            entity.position = pose.place
            entity.orientation = pose.turn
            entity.components.set(OpacityComponent(opacity: pose.opacity))
        }
        let reachable = Set(discs[window].map(\.id))
        for (id, entity) in cases where !reachable.contains(id) {
            entity.removeFromParent()
            cases[id] = nil
            waitingInserts[id] = nil
        }
    }

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
        /// The glossy finish every print shares; each print only adds its texture, since every property set on a
        /// material rebuilds its shader on the main thread.
        let printed: PhysicallyBasedMaterial
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
        var printed = PhysicallyBasedMaterial()
        printed.roughness = 0.35
        printed.metallic = 0.0
        printed.clearcoat = 1.0
        printed.clearcoatRoughness = 0.05
        let lidDepth = Self.thickness * 0.38
        return Parts(
            lid: .generateBox(width: Self.caseWidth, height: Self.caseHeight, depth: lidDepth, cornerRadius: 0.01),
            tray: .generateBox(width: Self.caseWidth - 0.03, height: Self.caseHeight - 0.03, depth: Self.thickness - lidDepth, cornerRadius: 0.01),
            hinge: .generateBox(width: 0.04, height: Self.caseHeight, depth: Self.thickness + 0.006),
            insert: .generatePlane(width: 1.06, height: 0.96),
            lidPlastic: plastic(0.84, 0.82, 0.9),
            trayPlastic: plastic(0.66, 0.64, 0.74),
            hingePlastic: plastic(0.9, 0.89, 0.95),
            placeholder: placeholder,
            printed: printed
        )
    }()

    /// `loadsInsert` false leaves the print to the opening's ordered preload.
    private func makeCase(_ disc: ListeningDisc, loadsInsert: Bool = true) -> Entity {
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
        if let material = loadedInserts[disc.id] {
            insert.model?.materials = [material]
        } else {
            waitingInserts[disc.id, default: []].append(insert)
            if loadsInsert { Task { await loadInsert(for: disc) } }
        }
        return root
    }

    /// The stretch round `position`, nearest first: where a pick lands, so its inserts load before the row gets there.
    static func openingOrder(count: Int, around position: Double) -> [Int] {
        guard count > 0 else { return [] }
        let base = min(max(Int(position.rounded()), 0), count - 1)
        return Array(max(0, base - 14)...min(count - 1, base + 32)).sorted { abs($0 - base) < abs($1 - base) }
    }

    /// The opening's inserts: every case the swing shows, which it waits for, nearest the opening album first; then,
    /// once the row has come to rest, the rest within reach, so nothing lands while it swings.
    func preload(_ discs: [ListeningDisc], around position: Double, size: CGSize) async {
        let nearest = { (lhs: Int, rhs: Int) in abs(Double(lhs) - position) < abs(Double(rhs) - position) }
        let entrance = Self.entranceIndices(count: discs.count, position: position, size: size)
        await preload(entrance.sorted(by: nearest).map { discs[$0] })
        while !isAtRest {
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
        guard let window = Self.window(count: discs.count, position: position, size: size) else { return }
        let shown = Set(entrance)
        let rest = window.filter { !shown.contains($0) }.sorted(by: nearest)
        await preload(rest.map { discs[$0] }, priority: .utility)
    }

    /// Loads inserts a few at a time, in the order given.
    func preload(_ discs: [ListeningDisc], priority: TaskPriority = .userInitiated) async {
        let ids = discs.map(\.id)
        let byID = Dictionary(discs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        await withTaskGroup(of: Void.self) { [self] group in
            for (index, id) in ids.enumerated() {
                if index >= 6 { await group.next() }
                guard !Task.isCancelled else { break }
                group.addTask { await self.loadInsert(id: id, from: byID, priority: priority) }
            }
        }
    }

    private func loadInsert(id: String, from discs: [String: ListeningDisc], priority: TaskPriority) async {
        guard let disc = discs[id] else { return }
        await loadInsert(for: disc, priority: priority)
    }

    /// The insert is drawn off the main thread; only the finished texture lands on the case.
    private func loadInsert(for disc: ListeningDisc, priority: TaskPriority = .userInitiated) async {
        guard loadedInserts[disc.id] == nil, loadingInserts.insert(disc.id).inserted else { return }
        defer {
            loadingInserts.remove(disc.id)
            waitingInserts[disc.id] = nil
            if loadedInserts[disc.id] == nil { failedInserts.insert(disc.id) }
        }
        let title = disc.title.uppercased()
        let year = disc.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
        guard let url = disc.artworkURL, let cover = await ShowCoverImageCache.shared.image(from: url) else { return }
        guard let cgImage = await Task.detached(priority: priority, operation: {
            ShelfInsertArt.draw(title: title, year: year, cover: cover)
        }).value,
            let texture = try? await TextureResource(image: cgImage, options: .init(semantic: .color)) else { return }
        guard retainedInsertIDs?.contains(disc.id) != false else { return }
        var material = parts.printed
        material.baseColor = .init(texture: .init(texture))
        loadedInserts[disc.id] = material
        for insert in waitingInserts.removeValue(forKey: disc.id) ?? [] {
            insert.model?.materials = [material]
        }
    }
}
