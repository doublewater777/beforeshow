import SwiftUI

@MainActor @Observable final class CDMechanism {
    enum Position: Equatable { case stored, seated, removed }
    var configuration = CDPlayerConfiguration.standard
    let motion = CDMotionDriver()
    private(set) var disc: ListeningDisc?
    private(set) var position: Position = .stored
    private(set) var isAutomatic = false
    private(set) var isReturning = false
    private(set) var isCabinetDragging = false
    private(set) var occupiedAttemptCount = 0
    var notice: String?
    @ObservationIgnored var onOpen: () -> Void = {}
    @ObservationIgnored var onTransition: (String) -> Void = { _ in }
    @ObservationIgnored var cabinetSlots: [String: CGPoint] = [:]
    @ObservationIgnored var cabinetDropZone = CGRect.zero
    @ObservationIgnored var cabinetScale = 0.25
    @ObservationIgnored private var lidOrigin: Double?
    @ObservationIgnored private var discOrigin: CGPoint?
    @ObservationIgnored private var pendingClose = false
    @ObservationIgnored private var pendingSeat = false
    @ObservationIgnored private var waitingForOpenToSeat = false

    init() {
        motion.onFrame = { [weak self] in self?.refresh() }
    }

    var isOpen: Bool { motion.lid.value > 0.82 }
    var isClosed: Bool { motion.lid.value < 0.002 && motion.lid.target != 1 }
    var hasDisc: Bool { position == .seated }

    /// Refresh metadata for the same physical compilation, without swapping it.
    func updateContents(_ replacement: ListeningDisc) {
        guard !isAutomatic, disc?.id == replacement.id else { return }
        disc = replacement
    }

    func setLid(open: Bool) {
        guard open || !isCompletingInsertion else { return }
        if open { onOpen(); pendingClose = false } else if !isClosed { pendingClose = true }
        motion.lid.move(to: open ? 1 : 0)
        motion.wake()
        if open { onTransition("open") }
    }

    func dragLid(_ translation: CGFloat) {
        guard !isAutomatic, !isCompletingInsertion else { return }
        if lidOrigin == nil {
            onOpen(); motion.lid.grab(); pendingClose = false; lidOrigin = motion.lid.value
        }
        motion.lid.value = max(0, min(1, lidOrigin! - translation / configuration.geometry.dragTravel))
        motion.wake()
    }

    func endLidDrag(_ translation: CGFloat, predicted: CGFloat) {
        guard lidOrigin != nil else { return }
        lidOrigin = nil
        let delta = -(predicted - translation) / configuration.geometry.dragTravel
        motion.lid.velocity = max(-3, min(3, delta / 0.2))
        setLid(open: motion.lid.value + delta > 0.5)
    }

    func removeDisc() {
        guard isOpen, position == .seated else { return }
        pendingSeat = false
        waitingForOpenToSeat = false
        position = .removed
        motion.lift.move(to: 1)
        motion.discX.move(to: configuration.geometry.parkedDisc.x)
        motion.discY.move(to: configuration.geometry.parkedDisc.y)
        motion.wake()
        onTransition("remove")
    }

    func insertDisc() {
        guard position == .removed, !isReturning, isOpen || motion.lid.target == 1 else { return }
        waitingForOpenToSeat = !isOpen
        pendingSeat = isOpen
        motion.discX.move(to: configuration.geometry.discCenter.x)
        motion.discY.move(to: configuration.geometry.discCenter.y)
        motion.discScale.move(to: 1)
        if isOpen { motion.lift.move(to: 0) }
        motion.wake()
        onTransition("insert")
    }

    func returnDisc() {
        guard position == .removed, let disc else { return }
        pendingSeat = false
        waitingForOpenToSeat = false
        let destination = cabinetPosition(for: disc)
        isReturning = true
        motion.discX.move(to: destination.x); motion.discY.move(to: destination.y)
        motion.lift.move(to: 0); motion.discScale.move(to: cabinetScale)
        motion.wake()
    }

    func returnCurrentDiscToCabinet() {
        guard isOpen, position == .seated else { return }
        position = .removed
        motion.lift.move(to: 1)
        motion.wake()
        onTransition("remove")
        returnDisc()
    }

    func refresh() {
        if pendingClose && motion.lid.target == nil && motion.lid.value < 0.002 {
            pendingClose = false; onTransition("close")
        }
        if waitingForOpenToSeat && isOpen {
            waitingForOpenToSeat = false
            pendingSeat = true
            motion.lift.move(to: 0)
            motion.wake()
        }
        if pendingSeat && discSettled {
            pendingSeat = false
            position = .seated
            onTransition("seat")
        }
        if isReturning && discSettled {
            isReturning = false
            position = .stored
            motion.resetDiscRotation()
            onTransition("store")
        }
    }

    @discardableResult
    func beginCabinetDrag(_ disc: ListeningDisc) -> Bool {
        guard position == .stored, !isAutomatic else {
            if position != .stored {
                occupiedAttemptCount += 1
                notice = BSLocalization.text("请先取出当前 CD，并放回唱片柜")
                onTransition("blocked")
            }
            return false
        }
        notice = nil
        if !isOpen { setLid(open: true) }
        liftFromCabinet(disc)
        isCabinetDragging = true
        discOrigin = CGPoint(x: motion.discX.value, y: motion.discY.value)
        motion.wake()
        onTransition("pickup")
        return true
    }

    func takeFromCabinet(_ disc: ListeningDisc) {
        guard beginCabinetDrag(disc) else { return }
        let origin = CGPoint(x: motion.discX.value, y: motion.discY.value)
        motion.discX.value = configuration.geometry.discCenter.x
        motion.discY.value = configuration.geometry.discCenter.y
        endDiscDrag()
        // Keep the same visible shelf → tray path for the non-drag action.
        motion.discX.value = origin.x; motion.discY.value = origin.y
    }

    /// Silently place a disc into the tray ready to play, skipping opening/closing animations.
    func restoreSeated(_ disc: ListeningDisc) {
        guard !isAutomatic else { return }
        self.disc = disc
        position = .seated
        isReturning = false
        isCabinetDragging = false
        pendingClose = false
        pendingSeat = false
        waitingForOpenToSeat = false
        motion.lid.value = 0
        motion.lid.target = nil
        motion.discX.value = configuration.geometry.discCenter.x
        motion.discX.target = nil
        motion.discY.value = configuration.geometry.discCenter.y
        motion.discY.target = nil
        motion.discScale.value = 1
        motion.discScale.target = nil
        motion.lift.value = 0
        motion.lift.target = nil
        motion.resetDiscRotation()
    }

    private func liftFromCabinet(_ disc: ListeningDisc) {
        motion.resetDiscRotation()
        self.disc = disc; position = .removed
        let origin = cabinetPosition(for: disc)
        motion.discX.grab(); motion.discY.grab(); motion.discScale.grab()
        motion.discX.value = origin.x; motion.discY.value = origin.y
        motion.lift.value = 0; motion.discScale.value = cabinetScale; motion.discScale.move(to: 1)
        motion.wake()
    }

    private func cabinetPosition(for disc: ListeningDisc) -> CGPoint {
        if let slot = cabinetSlots[disc.id] { return slot }
        // The original album may be outside the visible shelf or artist scope.
        if !cabinetDropZone.isEmpty {
            return CGPoint(x: cabinetDropZone.midX, y: cabinetDropZone.midY)
        }
        return configuration.geometry.parkedDisc
    }

    func dragDisc(_ translation: CGSize) {
        guard !isAutomatic, !isReturning else { return }
        if position == .seated {
            guard isOpen else { return }
            position = .removed
            pendingSeat = false
            waitingForOpenToSeat = false
            motion.lift.grab()
            motion.lift.value = 1
            onTransition("remove")
        }
        guard position == .removed else { return }
        if discOrigin == nil {
            motion.discX.grab(); motion.discY.grab()
            discOrigin = CGPoint(x: motion.discX.value, y: motion.discY.value)
        }
        motion.discX.value = discOrigin!.x + translation.width
        motion.discY.value = discOrigin!.y + translation.height
        motion.wake()
    }

    func endDiscDrag() {
        guard discOrigin != nil else { return }
        discOrigin = nil
        let fromCabinet = isCabinetDragging
        isCabinetDragging = false
        let center = configuration.geometry.discCenter
        if (isOpen || motion.lid.target == 1), hypot(motion.discX.value - center.x, motion.discY.value - center.y) < 220 {
            insertDisc()
        } else if fromCabinet || cabinetDropZone.contains(CGPoint(x: motion.discX.value, y: motion.discY.value)) {
            returnDisc()
        } else {
            returnDisc()
        }
        motion.wake()
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
        setLid(open: false); try await settle()
    }

    func unload() async throws {
        guard !isAutomatic else { return }
        isAutomatic = true
        defer { isAutomatic = false }
        try await unloadSteps()
    }

    func closeForPlayback() async throws {
        guard !isAutomatic, position == .seated else { return }
        isAutomatic = true
        defer { isAutomatic = false }
        setLid(open: false)
        try await settle()
        try Task.checkCancellation()
    }

    private func unloadSteps() async throws {
        setLid(open: true); try await settle()
        if position == .seated { removeDisc(); try await settle() }
        if position == .removed { returnDisc(); try await settle(); refresh() }
    }

    private var discSettled: Bool {
        motion.discX.target == nil && motion.discY.target == nil &&
        motion.discScale.target == nil && motion.lift.target == nil
    }

    private var isCompletingInsertion: Bool {
        waitingForOpenToSeat || pendingSeat
    }

    private var settled: Bool {
        motion.lid.target == nil && discSettled
    }

    private func settle() async throws {
        while !settled { try await Task.sleep(for: .milliseconds(16)) }
        try Task.checkCancellation()
        refresh()
    }
}
