import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The single user-facing projection for Listen playback capability and actions.
/// Views render this state and send intents back to the coordinator instead of
/// re-deriving Music authorization, preview availability, or catalog metadata.
enum ListeningRoomPlaybackMode: Equatable {
    case connecting
    case fullPlayback
    case preview
    case metadataOnly
    case unavailable

    var title: String {
        switch self {
        case .connecting: ListeningCopy.text("连接中…")
        case .fullPlayback: ListeningCopy.text("完整播放")
        case .preview: ListeningCopy.text("试听模式")
        case .metadataOnly: ListeningCopy.text("仅歌曲信息")
        case .unavailable: ListeningCopy.text("暂不可播放")
        }
    }
}

enum ListeningRecoveryAction: Equatable {
    case authorize
    case openSettings
    case retryAccess
    case retryCatalog
    case retryPlayback

    var title: String {
        switch self {
        case .authorize: ListeningCopy.text("立即授权")
        case .openSettings: ListeningCopy.text("打开设置")
        case .retryAccess, .retryCatalog, .retryPlayback: ListeningCopy.text("重试")
        }
    }
}

enum ListeningDiscPrimaryAction: Equatable {
    case load(songID: String)
    case openAppleMusic(URL)
    case informationOnly
    case unavailable
}

struct ListeningTrackPresentation: Equatable {
    let capability: ListeningMusicCapability

    var isPlayable: Bool {
        ListeningPlaybackSourceResolver.resolve(capability: capability) != nil
    }

    var statusText: String {
        switch capability {
        case .fullPlayback: ListeningCopy.text("完整播放")
        case .previewOnly: ListeningCopy.text("试听")
        case .metadataOnly: ListeningCopy.text("仅歌曲信息")
        case .unavailable: ListeningCopy.text("暂不可播放")
        }
    }
}

struct ListeningDiscPresentation: Equatable {
    let capability: ListeningMusicCapability
    let defaultPlayableTrackID: String?
    let primaryAction: ListeningDiscPrimaryAction
    let hasPartialPreview: Bool

    var canLoad: Bool { defaultPlayableTrackID != nil }

    var statusText: String {
        switch capability {
        case .fullPlayback:
            ListeningCopy.text("完整播放")
        case .previewOnly:
            hasPartialPreview ? ListeningCopy.text("部分曲目可试听") : ListeningCopy.text("30 秒试听")
        case .metadataOnly:
            ListeningCopy.text("仅歌曲信息")
        case .unavailable:
            ListeningCopy.text("暂不可播放")
        }
    }
}

enum ListeningPlayerPhase: Equatable {
    case noDisc
    case preparing
    case playing
    case paused
    case stopped
    case finished
    case failed
}

struct ListeningPlayerPresentation: Equatable {
    let phase: ListeningPlayerPhase
    let source: ListeningPlaybackSource?
    let previewRemaining: TimeInterval?
    let canPlayPause: Bool
    let blockingReason: String?
    let recoveryAction: ListeningRecoveryAction?
    let errorText: String?
    let noDiscMessage: String?

    var statusText: String {
        if let errorText, phase == .failed { return errorText }
        if let blockingReason, phase == .stopped { return blockingReason }
        switch phase {
        case .noDisc:
            return noDiscMessage ?? ListeningCopy.text("暂不可播放")
        case .preparing:
            return ListeningCopy.text("载入中…")
        case .playing:
            if source == .preview, let previewRemaining {
                return ListeningCopy.format("试听中 · 剩余 %d 秒", Int(ceil(max(0, previewRemaining))))
            }
            return ListeningCopy.text("播放中")
        case .paused:
            if source == .preview, let previewRemaining {
                return ListeningCopy.format("试听暂停 · 剩余 %d 秒", Int(ceil(max(0, previewRemaining))))
            }
            return ListeningCopy.text("暂停")
        case .stopped:
            return ListeningCopy.text("停止")
        case .finished:
            return ListeningCopy.text("播放结束")
        case .failed:
            return ListeningCopy.text("暂时无法播放")
        }
    }
}

struct ListeningHeaderNotice: Equatable {
    let message: String
    let recoveryAction: ListeningRecoveryAction?
}

struct ListeningDisplayProjection: Equatable {
    let page: ListeningPresentation
    let roomMode: ListeningRoomPlaybackMode
    let headerNotice: ListeningHeaderNotice?
    let recoveryAction: ListeningRecoveryAction?
    let shelfDiscs: [ListeningDisc]
    let showsAllDiscs: Bool
    let player: ListeningPlayerPresentation
    let access: ListeningMusicAccess

    func discPresentation(for disc: ListeningDisc) -> ListeningDiscPresentation {
        ListeningDisplayProjector.discPresentation(for: disc, access: access)
    }

    func trackPresentation(for track: ListeningDiscTrack) -> ListeningTrackPresentation {
        ListeningDisplayProjector.trackPresentation(for: track, access: access)
    }
}

enum ListeningDisplayProjector {
    enum Shelf {
        static let visibleCount = 3
    }

    static func make(
        page: ListeningPresentation,
        access: ListeningMusicAccess,
        isAuthorizing: Bool,
        allDiscs: [ListeningDisc],
        libraryDiscs: [ListeningDisc],
        loadedDisc: ListeningDisc?,
        isDiscSeated: Bool,
        isLidClosed: Bool,
        currentTrack: ListeningDiscTrack?,
        playbackState: ListeningPlaybackState,
        playbackError: String?
    ) -> ListeningDisplayProjection {
        let hasAnyTracks = allDiscs.contains(where: { !$0.tracks.isEmpty })
        let mode = roomMode(
            access: access,
            isAuthorizing: isAuthorizing || (!hasAnyTracks && (page == .loading || page == .loadingCatalog)),
            allDiscs: allDiscs
        )
        let modeNotice = headerNotice(mode: mode, access: access)
        let recovery = recoveryAction(page: page, access: access, isAuthorizing: isAuthorizing)
        let currentTrackState = currentTrack.map { trackPresentation(for: $0, access: access) }
        let player = playerPresentation(
            mode: mode,
            access: access,
            page: page,
            loadedDisc: loadedDisc,
            isDiscSeated: isDiscSeated,
            isLidClosed: isLidClosed,
            currentTrack: currentTrack,
            trackPresentation: currentTrackState,
            playbackState: playbackState,
            playbackError: playbackError
        )

        return ListeningDisplayProjection(
            page: page,
            roomMode: mode,
            headerNotice: modeNotice,
            recoveryAction: recovery,
            shelfDiscs: Array(libraryDiscs.prefix(Shelf.visibleCount)),
            showsAllDiscs: libraryDiscs.count > Shelf.visibleCount,
            player: player,
            access: access
        )
    }

    static func trackPresentation(
        for track: ListeningDiscTrack,
        access: ListeningMusicAccess
    ) -> ListeningTrackPresentation {
        ListeningTrackPresentation(
            capability: ListeningMusicCapabilityResolver.resolve(
                access: access,
                hasPreviewAsset: track.previewURL != nil,
                hasCatalogMetadata: true
            )
        )
    }

    static func discPresentation(
        for disc: ListeningDisc,
        access: ListeningMusicAccess
    ) -> ListeningDiscPresentation {
        let tracks = disc.tracks.map { trackPresentation(for: $0, access: access) }
        let capabilities = tracks.map(\.capability)
        let capability: ListeningMusicCapability
        if capabilities.contains(.fullPlayback) {
            capability = .fullPlayback
        } else if capabilities.contains(.previewOnly) {
            capability = .previewOnly
        } else if capabilities.contains(.metadataOnly) {
            capability = .metadataOnly
        } else {
            capability = .unavailable
        }

        let firstPlayable = zip(disc.tracks, tracks).first(where: { $0.1.isPlayable })?.0.id
        let previewCount = capabilities.filter { $0 == .previewOnly }.count
        let partialPreview = capability == .previewOnly && previewCount < disc.tracks.count

        let primaryAction: ListeningDiscPrimaryAction
        if let firstPlayable {
            primaryAction = .load(songID: firstPlayable)
        } else if capability == .metadataOnly,
                  let url = disc.appleMusicURL {
            primaryAction = .openAppleMusic(url)
        } else if capability == .metadataOnly {
            primaryAction = .informationOnly
        } else {
            primaryAction = .unavailable
        }

        return ListeningDiscPresentation(
            capability: capability,
            defaultPlayableTrackID: firstPlayable,
            primaryAction: primaryAction,
            hasPartialPreview: partialPreview
        )
    }

    private static func roomMode(
        access: ListeningMusicAccess,
        isAuthorizing: Bool,
        allDiscs: [ListeningDisc]
    ) -> ListeningRoomPlaybackMode {
        if isAuthorizing { return .connecting }
        guard allDiscs.contains(where: { !$0.tracks.isEmpty }) else { return .unavailable }
        if access.authorizationStatus == .authorized, access.canPlayCatalogContent {
            return .fullPlayback
        }
        if allDiscs.contains(where: { $0.tracks.contains(where: { $0.previewURL != nil }) }) {
            return .preview
        }
        return .metadataOnly
    }

    static func headerNotice(
        mode: ListeningRoomPlaybackMode,
        access: ListeningMusicAccess
    ) -> ListeningHeaderNotice? {
        switch mode {
        case .connecting, .fullPlayback:
            return nil
        case .preview:
            return restrictedPlaybackNotice(access: access, hasPreview: true)
        case .metadataOnly:
            return restrictedPlaybackNotice(access: access, hasPreview: false)
        case .unavailable:
            return ListeningHeaderNotice(
                message: ListeningCopy.text("当前没有可播放的歌曲。"),
                recoveryAction: nil
            )
        }
    }

    private static func restrictedPlaybackNotice(
        access: ListeningMusicAccess,
        hasPreview: Bool
    ) -> ListeningHeaderNotice {
        switch access.authorizationStatus {
        case .notDetermined:
            return ListeningHeaderNotice(
                message: ListeningCopy.text(
                    hasPreview
                        ? "允许访问 Apple Music 后，可尝试完整播放。"
                        : "允许访问 Apple Music 后，可尝试完整播放；当前没有可用试听片段。"
                ),
                recoveryAction: .authorize
            )
        case .denied, .restricted:
            return ListeningHeaderNotice(
                message: ListeningCopy.text(
                    hasPreview
                        ? "当前未允许访问 Apple Music。"
                        : "当前未允许访问 Apple Music，且这些歌曲没有可用试听片段。"
                ),
                recoveryAction: .openSettings
            )
        case .authorized:
            switch access.catalogPlaybackAccess {
            case .available:
                return ListeningHeaderNotice(
                    message: ListeningCopy.text(
                        hasPreview ? "当前使用歌曲试听片段。" : "当前仅提供歌曲信息"
                    ),
                    recoveryAction: nil
                )
            case .accountLimited:
                return ListeningHeaderNotice(
                    message: ListeningCopy.text(
                        hasPreview
                            ? "当前 Apple Music 账户不支持完整播放，因此使用歌曲试听片段。"
                            : "当前 Apple Music 账户不支持完整播放，这些歌曲也没有可用试听片段。"
                    ),
                    recoveryAction: nil
                )
            case .accessCheckFailed:
                return ListeningHeaderNotice(
                    message: ListeningCopy.text(
                        hasPreview
                            ? "暂时无法确认完整播放权限，当前使用试听片段。"
                            : "暂时无法确认完整播放权限，这些歌曲也没有可用试听片段。"
                    ),
                    recoveryAction: .retryAccess
                )
            }
        }
    }

    private static func recoveryAction(
        page: ListeningPresentation,
        access: ListeningMusicAccess,
        isAuthorizing: Bool
    ) -> ListeningRecoveryAction? {
        guard !isAuthorizing else { return nil }
        switch access.authorizationStatus {
        case .notDetermined:
            return .authorize
        case .denied, .restricted:
            return .openSettings
        case .authorized:
            switch page {
            case .cachedWithError, .fatalUnavailable:
                return .retryCatalog
            default:
                return nil
            }
        }
    }

    private static func playerPresentation(
        mode: ListeningRoomPlaybackMode,
        access: ListeningMusicAccess,
        page: ListeningPresentation,
        loadedDisc: ListeningDisc?,
        isDiscSeated: Bool,
        isLidClosed: Bool,
        currentTrack: ListeningDiscTrack?,
        trackPresentation: ListeningTrackPresentation?,
        playbackState: ListeningPlaybackState,
        playbackError: String?
    ) -> ListeningPlayerPresentation {
        guard loadedDisc != nil, isDiscSeated, currentTrack != nil, let trackPresentation else {
            return ListeningPlayerPresentation(
                phase: .noDisc,
                source: nil,
                previewRemaining: nil,
                canPlayPause: false,
                blockingReason: nil,
                recoveryAction: nil,
                errorText: nil,
                noDiscMessage: noDiscMessage(for: mode)
            )
        }

        let accessRecovery = recoveryAction(page: page, access: access, isAuthorizing: false)
        if !trackPresentation.isPlayable {
            return ListeningPlayerPresentation(
                phase: .stopped,
                source: nil,
                previewRemaining: nil,
                canPlayPause: false,
                blockingReason: trackPresentation.statusText,
                recoveryAction: accessRecovery,
                errorText: nil,
                noDiscMessage: nil
            )
        }

        if let playbackError {
            return ListeningPlayerPresentation(
                phase: .failed,
                source: source(from: playbackState),
                previewRemaining: previewRemaining(from: playbackState),
                canPlayPause: false,
                blockingReason: playbackError,
                recoveryAction: .retryPlayback,
                errorText: playbackError,
                noDiscMessage: nil
            )
        }
        if case .failed = playbackState {
            return ListeningPlayerPresentation(
                phase: .failed,
                source: nil,
                previewRemaining: nil,
                canPlayPause: false,
                blockingReason: ListeningCopy.text("暂时无法播放"),
                recoveryAction: .retryPlayback,
                errorText: ListeningCopy.text("暂时无法播放"),
                noDiscMessage: nil
            )
        }

        let phase: ListeningPlayerPhase
        switch playbackState {
        case .preparing:
            phase = .preparing
        case .playing:
            phase = .playing
        case .paused:
            phase = .paused
        case .finished:
            phase = .finished
        case .idle, .ready:
            phase = .stopped
        case .failed:
            phase = .failed
        }

        let lidReason = isLidClosed ? nil : ListeningCopy.text("请先合上播放器上盖")
        return ListeningPlayerPresentation(
            phase: phase,
            source: source(from: playbackState),
            previewRemaining: previewRemaining(from: playbackState),
            canPlayPause: phase != .preparing,
            blockingReason: lidReason,
            recoveryAction: nil,
            errorText: nil,
            noDiscMessage: nil
        )
    }

    private static func noDiscMessage(for mode: ListeningRoomPlaybackMode) -> String {
        switch mode {
        case .fullPlayback, .preview:
            ListeningCopy.text("选择一张唱片开始播放")
        case .metadataOnly:
            ListeningCopy.text("当前仅提供歌曲信息")
        case .unavailable:
            ListeningCopy.text("当前暂不可播放")
        case .connecting:
            ListeningCopy.text("连接中…")
        }
    }

    private static func source(from state: ListeningPlaybackState) -> ListeningPlaybackSource? {
        switch state {
        case let .preparing(source): source
        case let .ready(_, source, _, _),
             let .playing(_, source, _, _),
             let .paused(_, source, _, _),
             let .finished(_, source, _): source
        case .idle, .failed: nil
        }
    }

    private static func previewRemaining(from state: ListeningPlaybackState) -> TimeInterval? {
        switch state {
        case let .ready(_, source, current, duration),
             let .playing(_, source, current, duration),
             let .paused(_, source, current, duration):
            guard source == .preview, let duration else { return nil }
            return max(0, duration - current)
        case .idle, .preparing, .finished, .failed:
            return nil
        }
    }
}

/// Feature-scoped strings for the capability projection. Keeping these in a
/// dedicated table avoids hard-coded user-visible state while keeping the
/// existing app-wide localization seam unchanged.
enum ListeningCopy {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Listening", bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}

extension ListeningRoomCoordinator {
    var display: ListeningDisplayProjection {
        ListeningDisplayProjector.make(
            page: presentation,
            access: access,
            isAuthorizing: isAuthorizing || !accessResolved,
            allDiscs: discs,
            libraryDiscs: libraryDiscs,
            loadedDisc: mechanism.disc,
            isDiscSeated: mechanism.position == .seated,
            isLidClosed: mechanism.isClosed,
            currentTrack: track,
            playbackState: playbackState,
            playbackError: playbackError
        )
    }

    func discPresentation(for disc: ListeningDisc) -> ListeningDiscPresentation {
        ListeningDisplayProjector.discPresentation(for: disc, access: access)
    }

    func trackPresentation(for track: ListeningDiscTrack) -> ListeningTrackPresentation {
        ListeningDisplayProjector.trackPresentation(for: track, access: access)
    }

    func loadPlayableDisc(_ disc: ListeningDisc, songID: String? = nil) {
        let discState = discPresentation(for: disc)
        let targetSongID: String?
        if let songID,
           let selected = disc.tracks.first(where: { $0.id == songID }),
           trackPresentation(for: selected).isPlayable {
            targetSongID = songID
        } else if songID == nil {
            targetSongID = discState.defaultPlayableTrackID
        } else {
            targetSongID = nil
        }
        guard let targetSongID else {
            mechanism.notice = discState.statusText
            return
        }
        mechanism.notice = nil
        playbackError = nil
        loadDisc(disc, songID: targetSongID)
    }

    @discardableResult
    func beginPlayableDiscDrag(_ disc: ListeningDisc) -> Bool {
        let discState = discPresentation(for: disc)
        guard discState.canLoad else {
            mechanism.notice = discState.statusText
            return false
        }
        mechanism.notice = nil
        if mechanism.position != .stored {
            loadPlayableDisc(disc)
            return false
        }
        return mechanism.beginCabinetDrag(disc)
    }

    func takePlayableDiscFromCabinet(_ disc: ListeningDisc) {
        let discState = discPresentation(for: disc)
        guard discState.canLoad else {
            mechanism.notice = discState.statusText
            return
        }
        mechanism.notice = nil
        if mechanism.position != .stored {
            loadPlayableDisc(disc)
        } else {
            mechanism.takeFromCabinet(disc)
        }
    }

    /// Once the disc is seated into the tray, close the lid and start playback automatically.
    func finalizeManualDiscInsertionIfNeeded() {
        guard !mechanism.isAutomatic,
              mechanism.position == .seated,
              let disc = mechanism.disc,
              let songID = discPresentation(for: disc).defaultPlayableTrackID else { return }
        playFromSleeve(disc, songID: songID)
    }

    func retryCurrentPlayback() {
        guard display.player.recoveryAction == .retryPlayback else { return }
        playbackError = nil
        playPause()
    }

    func performListeningRecovery(_ action: ListeningRecoveryAction) {
        switch action {
        case .authorize:
            Task { await authorize() }
        case .openSettings:
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        case .retryAccess:
            Task { await refreshMusicAccess() }
        case .retryCatalog:
            guard let show else { return }
            Task { await load(show: show, force: true) }
        case .retryPlayback:
            retryCurrentPlayback()
        }
    }
}
