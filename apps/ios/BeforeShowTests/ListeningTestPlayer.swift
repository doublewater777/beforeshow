import Foundation
import XCTest
@testable import BeforeShow

/// Scriptable stand-in for an Apple player. It is observable like the MusicKit
/// and AVFoundation players, so the deck reacts to it the same way.
@MainActor @Observable
final class ListeningTestPlayer: ListeningPlaybackServicing {
    let source: ListeningPlaybackSource
    var phase: ListeningPlaybackTransportPhase = .stopped
    var currentSongID: String?
    var hasEnded = false
    var failure: ListeningPlaybackError?
    private(set) var queuedSongIDs: [String] = []
    @ObservationIgnored var currentTime: TimeInterval = 0
    @ObservationIgnored var durations: [String: TimeInterval] = [:]

    // Scripting
    @ObservationIgnored var loadDelay: Duration?
    @ObservationIgnored var playDelay: Duration?
    @ObservationIgnored var loadError: (any Error)?
    @ObservationIgnored var playError: (any Error)?
    /// Like AVQueuePlayer, a preview queue leaves out songs without a preview.
    @ObservationIgnored var skipsItemsWithoutPreview: Bool
    /// When false, Play/Pause wait for the test to report the new phase.
    @ObservationIgnored var acknowledgesCommands = true

    // Recording
    @ObservationIgnored private(set) var loadCount = 0
    @ObservationIgnored private(set) var playCount = 0
    @ObservationIgnored private(set) var pauseCount = 0
    @ObservationIgnored private(set) var stopCount = 0
    @ObservationIgnored private(set) var nativeSkips: [Int] = []
    @ObservationIgnored private(set) var jumps: [String] = []
    @ObservationIgnored private(set) var loadedSongIDs: [String] = []
    @ObservationIgnored private(set) var loadedStartSongID: String?
    @ObservationIgnored private(set) var loadedResumeTime: TimeInterval?
    @ObservationIgnored private(set) var prefetchedSongIDs: [String] = []

    init(source: ListeningPlaybackSource = .fullCatalog) {
        self.source = source
        skipsItemsWithoutPreview = source == .preview
    }

    var currentDuration: TimeInterval? {
        currentSongID.flatMap { durations[$0] }
    }

    func prefetch(_ items: [ListeningPlaybackItem]) async {
        prefetchedSongIDs = items.map(\.songID)
    }

    func load(_ items: [ListeningPlaybackItem], startingAt songID: String?, at time: TimeInterval) async throws {
        loadCount += 1
        if let loadDelay { try await Task.sleep(for: loadDelay) }
        if let loadError { throw loadError }
        let playable = skipsItemsWithoutPreview ? items.filter { $0.previewURL != nil } : items
        guard let first = playable.first else { throw ListeningPlaybackError.emptyQueue }
        for item in playable {
            if let duration = item.duration { durations[item.songID] = duration }
        }
        queuedSongIDs = playable.map(\.songID)
        loadedSongIDs = queuedSongIDs
        loadedStartSongID = songID
        loadedResumeTime = time
        currentSongID = playable.first { $0.songID == songID }?.songID ?? first.songID
        currentTime = time
        hasEnded = false
        failure = nil
        phase = .paused
    }

    func play() async throws {
        playCount += 1
        if let playDelay { try await Task.sleep(for: playDelay) }
        if let playError { throw playError }
        guard currentSongID != nil else { throw ListeningPlaybackError.emptyQueue }
        if acknowledgesCommands { phase = .playing }
    }

    func pause() {
        pauseCount += 1
        if acknowledgesCommands, currentSongID != nil { phase = .paused }
    }

    func skipToNext() async throws {
        nativeSkips.append(1)
        try move(by: 1)
    }

    func skipToPrevious() async throws {
        nativeSkips.append(-1)
        try move(by: -1)
    }

    func skip(to songID: String) async throws {
        guard queuedSongIDs.contains(songID) else { throw ListeningPlaybackError.songUnavailable(songID) }
        jumps.append(songID)
        currentSongID = songID
        currentTime = 0
    }

    func stop() {
        stopCount += 1
        queuedSongIDs = []
        currentSongID = nil
        currentTime = 0
        hasEnded = false
        phase = .stopped
    }

    // MARK: - Changes the system makes on its own

    /// The queue moves on to its next song, as at the end of a track.
    func advanceNaturally() {
        try? move(by: 1)
    }

    /// The last song of the queue played to its end.
    func finishQueue() {
        if let last = queuedSongIDs.last {
            currentSongID = last
            currentTime = durations[last] ?? currentTime
        }
        phase = .stopped
        hasEnded = true
    }

    private func move(by delta: Int) throws {
        guard let currentSongID,
              let index = queuedSongIDs.firstIndex(of: currentSongID),
              queuedSongIDs.indices.contains(index + delta) else {
            throw ListeningPlaybackError.queueBoundary
        }
        self.currentSongID = queuedSongIDs[index + delta]
        currentTime = 0
    }
}

@MainActor
func waitUntil(
    _ condition: () -> Bool,
    timeout: Duration = .seconds(3),
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            XCTFail("Condition did not become true", file: file, line: line)
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
