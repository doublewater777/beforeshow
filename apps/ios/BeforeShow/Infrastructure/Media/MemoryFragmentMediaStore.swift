import Foundation

actor MemoryFragmentMediaStore {
    static let shared = MemoryFragmentMediaStore(location: .applicationSupport())

    let location: MemoryMediaLocation
    let fileManager: FileManager
    /// Serializes media commits against reconciliation so a stale reconciliation
    /// snapshot can never delete a concurrent commit's just-copied files.
    private let gate = MemoryMediaGate()

    init(location: MemoryMediaLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    /// Acquired by commit paths around `[copy + SwiftData save]` and by reconciliation
    /// around `[fetch snapshot + reconcile]` so the two cannot interleave.
    func acquireCommitGate() async { await gate.acquire() }
    func releaseCommitGate() async { await gate.release() }
}
