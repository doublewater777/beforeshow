import SwiftUI

@MainActor @Observable final class CDMechanism {
    enum Position: Equatable { case stored, seated, released, removed }
    let configuration = CDPlayerConfiguration.panasonic
    let motion = CDMotionDriver()
    private(set) var disc: ListeningDisc?
    private(set) var position: Position = .stored
    private(set) var isAutomatic = false
    private(set) var isReturning = false
    private(set) var isCabinetDragging = false
    var notice: String?
    @ObservationIgnored var onOpen: () -> Void = {}
    @ObservationIgnored var onTransition: (String) -> Void = { _ in }
    @ObservationIgnored var cabinetSlots: [String: CGPoint] = [:]
    @ObservationIgnored var cabinetDropZone = CGRect.zero
    @ObservationIgnored var cabinetScale = 0.25
    @ObservationIgnored private var lidOrigin: Double?
    @ObservationIgnored private var discOrigin: CGPoint?
    var isOpen: Bool { motion.lid.value > 0.98 }
    var isClosed: Bool { motion.lid.value < 0.002 && motion.lid.target != 1 }
    var hasDisc: Bool { position == .seated || position == .released }
    var canSeat: Bool {
        isOpen && position == .released &&
        hypot(motion.discX.value - configuration.geometry.discCenter.x,
              motion.discY.value - configuration.geometry.discCenter.y) < 2
    }
    /// Refresh metadata for the same physical compilation, without swapping it.
    func updateContents(_ replacement: ListeningDisc) {
        guard !isAutomatic, disc?.id == replacement.id else { return }
        disc = replacement
    }
    func setLid(open: Bool) {
        guard open || position != .released else { notice = BSLocalization.text("请先卡紧或取出 CD"); return }
        if open { onOpen() }
        motion.lid.move(to: open ? 1 : 0)
        onTransition(open ? "open" : "close")
    }
    func dragLid(_ translation: CGFloat) {
        guard !isAutomatic else { return }
        if lidOrigin == nil {
            onOpen(); motion.lid.grab(); lidOrigin = motion.lid.value
        }
        motion.lid.value = max(position == .released ? 0.99 : 0, min(1, lidOrigin! - translation / configuration.geometry.dragTravel))
    }
    func endLidDrag(_ translation: CGFloat, predicted: CGFloat) {
        guard lidOrigin != nil else { return }
        lidOrigin = nil
        let delta = -(predicted - translation) / configuration.geometry.dragTravel
        motion.lid.velocity = max(-3, min(3, delta / 0.2))
        setLid(open: position == .released || motion.lid.value + delta > 0.5)
    }
    func releaseDisc() {
        guard isOpen, position == .seated else { return }
        position = .released; motion.lift.move(to: 1); onTransition("release")
    }
    func removeDisc() {
        guard isOpen, position == .released else { return }
        position = .removed
        motion.discX.move(to: configuration.geometry.parkedDisc.x)
        motion.discY.move(to: configuration.geometry.parkedDisc.y)
        onTransition("remove")
    }
    func seatDisc() {
        guard canSeat else { return }
        position = .seated; motion.lift.move(to: 0); onTransition("seat")
    }
    func insertDisc() {
        guard isOpen, position == .removed, !isReturning else { return }
        position = .released
        motion.discX.move(to: configuration.geometry.discCenter.x)
        motion.discY.move(to: configuration.geometry.discCenter.y)
        motion.discScale.move(to: 1); motion.lift.move(to: 1)
        onTransition("insert")
    }
    func returnDisc() {
        guard position == .removed, let disc else { return }
        let destination = cabinetSlots[disc.id] ?? CGPoint(x: configuration.geometry.canvas.width / 2, y: configuration.geometry.canvas.height + 75)
        isReturning = true
        motion.discX.move(to: destination.x); motion.discY.move(to: destination.y)
        motion.lift.move(to: 0); motion.discScale.move(to: cabinetScale)
    }
    func refresh() {
        if isReturning && settled {
            isReturning = false; position = .stored; onTransition("store")
        }
    }
    func beginCabinetDrag(_ disc: ListeningDisc) {
        guard position == .stored, isOpen, !isAutomatic else { return }
        liftFromCabinet(disc)
        isCabinetDragging = true
        discOrigin = CGPoint(x: motion.discX.value, y: motion.discY.value)
    }
    private func liftFromCabinet(_ disc: ListeningDisc) {
        self.disc = disc; position = .removed
        let origin = cabinetSlots[disc.id] ?? configuration.geometry.parkedDisc
        motion.discX.grab(); motion.discY.grab(); motion.discScale.grab()
        motion.discX.value = origin.x; motion.discY.value = origin.y
        motion.lift.value = 0; motion.discScale.value = cabinetScale; motion.discScale.move(to: 1)
    }
    func dragDisc(_ translation: CGSize) {
        guard !isAutomatic, !isReturning, position == .removed || (isOpen && position == .released) else { return }
        if discOrigin == nil {
            motion.discX.grab(); motion.discY.grab()
            discOrigin = CGPoint(x: motion.discX.value, y: motion.discY.value)
        }
        motion.discX.value = discOrigin!.x + translation.width
        motion.discY.value = discOrigin!.y + translation.height
    }
    func endDiscDrag() {
        guard discOrigin != nil else { return }
        discOrigin = nil
        let fromCabinet = isCabinetDragging
        isCabinetDragging = false
        let center = configuration.geometry.discCenter
        if isOpen && hypot(motion.discX.value - center.x, motion.discY.value - center.y) < 125 {
            if position == .released { position = .removed }
            insertDisc()
        } else if fromCabinet || cabinetDropZone.contains(CGPoint(x: motion.discX.value, y: motion.discY.value)) {
            if position == .released { position = .removed; onTransition("remove") }
            returnDisc()
        } else {
            if position == .released { position = .removed; onTransition("remove") }
            motion.discX.move(to: configuration.geometry.parkedDisc.x)
            motion.discY.move(to: configuration.geometry.parkedDisc.y)
        }
    }
    /// Automatic loading invokes the exact same mechanical mutations as gestures.
    /// Every leg awaits the actual spring's resting position, not a guessed delay.
    func load(_ disc: ListeningDisc) async throws {
        guard !isAutomatic else { return }
        isAutomatic = true
        defer { isAutomatic = false }
        try await unloadSteps()
        try Task.checkCancellation()
        liftFromCabinet(disc); insertDisc(); try await settle()
        seatDisc(); try await settle()
        setLid(open: false); try await settle()
    }
    func unload() async throws {
        guard !isAutomatic else { return }
        isAutomatic = true
        defer { isAutomatic = false }
        try await unloadSteps()
    }
    private func unloadSteps() async throws {
        setLid(open: true); try await settle()
        if position == .seated { releaseDisc(); try await settle() }
        if position == .released { removeDisc(); try await settle() }
        if position == .removed { returnDisc(); try await settle(); refresh() }
    }
    private var settled: Bool {
        motion.lid.target == nil && motion.discX.target == nil && motion.discY.target == nil &&
        motion.discScale.target == nil && motion.lift.target == nil
    }
    private func settle() async throws {
        while !settled { try await Task.sleep(for: .milliseconds(16)) }
        try Task.checkCancellation()
    }
}
