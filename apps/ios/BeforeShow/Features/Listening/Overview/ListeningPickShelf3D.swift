import SwiftUI
import UIKit

/// The 3D record shelf: a row of CD cases seen from above and to the right, the one in front pulled out beside the row.
/// Each case is flat layers mapped through the shelf's camera, so it opens without a 3D renderer to start up.
struct ListeningPickShelf3D: View {
    let discs: [ListeningDisc]
    let position: Double
    /// Where a pick will land; its inserts load before the row gets there.
    var landing: Int?
    /// 0 → 1 as the row arrives from its far end when the shelf opens.
    var entrance: Double = 1
    /// The opening is ready to play: every case the swing shows is printed, or the wait for them ran out.
    var onReady: () -> Void = {}
    @State private var scene = ShelfScene3D()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ShelfStage3D(scene: scene, discs: discs, position: position, landing: landing, entrance: entrance, size: proxy.size)
                ForEach(ShelfGeometry.softBands.indices, id: \.self) { band in
                    let soft = ShelfGeometry.softBands[band]
                    let region = soft.region(in: proxy.size)
                    // Blurred over only the corner it softens.
                    ShelfLayers(view: scene.softViews[band])
                        .blur(radius: soft.radius)
                        .mask(ShelfSoftMask(band: soft))
                        .frame(width: region.width, height: region.height)
                        .offset(x: region.minX, y: region.minY)
                }
            }
            // The cases the swing shows load first, nearest the opening album first.
            .task(id: discs.map(\.id)) {
                await scene.preload(discs, around: position, size: proxy.size)
            }
        }
        .task {
            await scene.waitForOpening()
            guard !Task.isCancelled else { return }
            onReady()
        }
    }
}

private struct ShelfStage3D: UIViewRepresentable {
    let scene: ShelfScene3D
    let discs: [ListeningDisc]
    let position: Double
    let landing: Int?
    let entrance: Double
    let size: CGSize

    func makeUIView(context: Context) -> UIView { scene.view }

    func updateUIView(_ view: UIView, context: Context) {
        scene.update(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
    }
}

private struct ShelfLayers: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// Over a soft band's region: strongest towards the top-right corner, where the far end of the row is.
private struct ShelfSoftMask: View {
    let band: ShelfGeometry.SoftBand
    /// Smoothstep in five stops.
    private static let ramp: [Gradient.Stop] = [0, 0.25, 0.5, 0.75, 1].map {
        .init(color: .black.opacity($0 * $0 * (3 - 2 * $0)), location: $0)
    }

    var body: some View {
        let (from, to) = (band.from, band.to)
        let across = (to.x - from.x) / (1 - from.x)
        LinearGradient(stops: Self.ramp, startPoint: .topLeading, endPoint: UnitPoint(x: across, y: 0))
            .mask(LinearGradient(stops: Self.ramp, startPoint: .bottomLeading, endPoint: UnitPoint(x: 0, y: to.y / from.y)))
    }
}

@MainActor
final class ShelfScene3D {
    /// The swing starts once every case it shows is printed, or this long after it was asked for.
    static let openingBudget: Duration = .milliseconds(350)

    static func isOpeningPrinted(cases: [String], waited: Duration, isSettled: (String) -> Bool) -> Bool {
        cases.allSatisfy(isSettled) || waited >= openingBudget
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
        /// The swing's cases are built out of sight and wait for their prints.
        case warming(cases: [String], since: ContinuousClock.Instant)
        case done
    }

    /// Holds the cases' layers. Made on first use: SwiftUI makes a scene each time the shelf's view is rebuilt and keeps
    /// only the first.
    private(set) lazy var view = Self.makeView()
    /// Copies of the cases that reach each band of the soft far end, drawn again blurred over the row.
    private(set) lazy var softViews = ShelfGeometry.softBands.map { _ in Self.makeView() }
    private var opening = Opening.pending
    /// The latest row asked for; held back while the opening warms up.
    private var request: Request?
    private var cases: [String: ShelfCaseLayer] = [:]
    private lazy var softCases: [[String: ShelfCaseLayer]] = ShelfGeometry.softBands.map { _ in [:] }
    /// Printed inserts by disc, kept so a case made again later needs no new drawing.
    private var loadedInserts: [String: CGImage] = [:]
    private var retainedInsertIDs: Set<String>?
    private var loadingInserts: Set<String> = []
    /// No artwork, or it would not load: the opening does not wait on these.
    private var failedInserts: Set<String> = []
    /// How fast the row is moving, in albums a second; a fast row stays one straight line.
    private var speed: Double = 0
    private var lastPosition: Double?
    private var lastTime: CFTimeInterval = 0
    private var lastLanding: Int?

    func update(discs: [ListeningDisc], position: Double, landing: Int?, entrance: Double, size: CGSize) {
        let request = Request(discs: discs, position: position, landing: landing, entrance: entrance, size: size)
        self.request = request
        switch opening {
        case .pending: beginOpening(request)
        case .warming: break
        case .done: apply(request)
        }
    }

    /// Builds every case the swing will show, out of sight, so the swing itself builds none.
    private func beginOpening(_ request: Request) {
        let (discs, size) = (request.discs, request.size)
        guard !discs.isEmpty else {
            opening = .done
            return
        }
        guard size.width > 0, size.height > 0 else { return }
        let entrance = ShelfGeometry.entranceIndices(count: discs.count, position: request.position, size: size)
        withoutAnimation {
            for index in entrance where cases[discs[index].id] == nil {
                makeCase(discs[index], loadsInsert: false)
            }
        }
        opening = .warming(cases: entrance.map { discs[$0].id }, since: .now)
    }

    /// Returns once the opening can play: its cases printed, within the budget.
    func waitForOpening() async {
        while case .pending = opening {
            guard (try? await Task.sleep(for: .milliseconds(8))) != nil else { return }
        }
        guard case let .warming(ids, since) = opening else { return }
        while !Self.isOpeningPrinted(cases: ids, waited: since.duration(to: .now), isSettled: isSettled) {
            guard (try? await Task.sleep(for: .milliseconds(16))) != nil else { return }
        }
        opening = .done
        if let request { apply(request) }
    }

    private func isSettled(_ id: String) -> Bool {
        loadedInserts[id] != nil || !loadingInserts.contains(id) && failedInserts.contains(id)
    }

    /// The opening has played: the swing is over, or there was none.
    private var isAtRest: Bool {
        guard case .done = opening else { return false }
        return (request?.entrance ?? 1) >= 1
    }

    private func apply(_ request: Request) {
        let (discs, position, landing, size) = (request.discs, request.position, request.landing, request.size)
        guard !discs.isEmpty, size.width > 0, size.height > 0,
              let window = ShelfGeometry.window(count: discs.count, position: position, size: size) else { return }
        let camera = ShelfCamera(size: size)
        let (lower, upper) = (window.lowerBound, window.upperBound)
        let now = CACurrentMediaTime()
        if let lastPosition, now > lastTime {
            speed = speed * 0.5 + abs(position - lastPosition) / max(now - lastTime, 1.0 / 120) * 0.5
        }
        lastPosition = position
        lastTime = now
        // Cases only slide out as the row slows down, like the original: nothing pops while flicking past.
        let settled = 1 - ShelfGeometry.smoothstep(Float(min(1, max(0, (speed - 3) / 6))))
        // Keep nearby inserts warm independently of which cases are currently in the scene.
        var kept = Set(discs[max(0, lower - 40)...min(discs.count - 1, upper + 40)].map(\.id))
        if let landing {
            let ahead = ShelfGeometry.openingOrder(count: discs.count, around: Double(landing)).map { discs[$0] }
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
        let softRegions = ShelfGeometry.softBands.map { $0.region(in: size) }
        withoutAnimation {
            // The soft copies draw in their corner's own view.
            for (view, region) in zip(softViews, softRegions) {
                view.layer.sublayerTransform = CATransform3DMakeTranslation(-region.minX, -region.minY, 0)
            }
            for index in window {
                let disc = discs[index]
                // Cases within reach that are out of sight are only hidden, so the row never rebuilds them mid-motion.
                guard let pose = ShelfGeometry.pose(
                    offset: Float(Double(index) - position), settled: settled, arrival: Float(request.entrance), camera: camera
                ) else {
                    cases[disc.id]?.root.isHidden = true
                    for band in softCases.indices { softCases[band][disc.id]?.root.isHidden = true }
                    continue
                }
                let placement = ShelfCaseLayer.placement(pose, camera: camera)
                (cases[disc.id] ?? makeCase(disc)).place(placement)
                for band in softCases.indices {
                    if placement.bounds.intersects(softRegions[band]) {
                        (softCases[band][disc.id] ?? addCase(disc.id, to: softViews[band], in: &softCases[band])).place(placement)
                    } else {
                        softCases[band][disc.id]?.root.isHidden = true
                    }
                }
            }
            let reachable = Set(discs[window].map(\.id))
            Self.prune(&cases, keeping: reachable)
            for band in softCases.indices { Self.prune(&softCases[band], keeping: reachable) }
        }
    }

    /// `loadsInsert` false leaves the print to the opening's ordered preload.
    @discardableResult
    private func makeCase(_ disc: ListeningDisc, loadsInsert: Bool = true) -> ShelfCaseLayer {
        let layer = addCase(disc.id, to: view, in: &cases)
        if loadsInsert, loadedInserts[disc.id] == nil {
            Task { await loadInsert(for: disc) }
        }
        return layer
    }

    private func addCase(_ id: String, to view: UIView, in cases: inout [String: ShelfCaseLayer]) -> ShelfCaseLayer {
        let layer = ShelfCaseLayer()
        view.layer.addSublayer(layer.root)
        cases[id] = layer
        if let art = loadedInserts[id] { layer.show(art) }
        return layer
    }

    private static func prune(_ cases: inout [String: ShelfCaseLayer], keeping ids: Set<String>) {
        for (id, layer) in cases where !ids.contains(id) {
            layer.root.removeFromSuperlayer()
            cases[id] = nil
        }
    }

    private static func makeView() -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        return view
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    /// The opening's inserts: every case the swing shows, which it waits for, nearest the opening album first; then,
    /// once the row has come to rest, the rest within reach.
    func preload(_ discs: [ListeningDisc], around position: Double, size: CGSize) async {
        let nearest = { (lhs: Int, rhs: Int) in abs(Double(lhs) - position) < abs(Double(rhs) - position) }
        let entrance = ShelfGeometry.entranceIndices(count: discs.count, position: position, size: size)
        await preload(entrance.sorted(by: nearest).map { discs[$0] })
        while !isAtRest {
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
        guard let window = ShelfGeometry.window(count: discs.count, position: position, size: size) else { return }
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

    /// The insert is drawn off the main thread; only the finished print lands on the case.
    private func loadInsert(for disc: ListeningDisc, priority: TaskPriority = .userInitiated) async {
        guard loadedInserts[disc.id] == nil, loadingInserts.insert(disc.id).inserted else { return }
        defer {
            loadingInserts.remove(disc.id)
            if loadedInserts[disc.id] == nil { failedInserts.insert(disc.id) }
        }
        let title = disc.title.uppercased()
        let year = disc.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
        guard let url = disc.artworkURL, let cover = await ShowCoverImageCache.shared.image(from: url),
              let art = await Task.detached(priority: priority, operation: {
                  ShelfInsertArt.draw(title: title, year: year, cover: cover)
              }).value,
              retainedInsertIDs?.contains(disc.id) != false else { return }
        loadedInserts[disc.id] = art
        withoutAnimation {
            cases[disc.id]?.show(art)
            for band in softCases.indices { softCases[band][disc.id]?.show(art) }
        }
    }
}
