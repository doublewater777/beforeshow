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
        case .connecting: ListeningCopy.text("正在准备…")
        case .fullPlayback: ListeningCopy.text("完整播放")
        case .preview: ListeningCopy.text("试听模式")
        case .metadataOnly: ListeningCopy.text("仅歌曲信息")
        case .unavailable: ListeningCopy.text("暂不可播放")
        }
    }

    var iconName: String {
        switch self {
        case .connecting: "hourglass"
        case .fullPlayback: "apple.logo"
        case .preview: "waveform"
        case .metadataOnly: "list.bullet.rectangle"
        case .unavailable: "exclamationmark.triangle"
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
    case waiting
    case playing
    case seeking
    case paused
    case interrupted
    case stopped
    case finished
    case failed

    init(playback: ListeningPlaybackSnapshot) {
        self = switch playback.state {
        case .idle, .ready: .stopped
        case .preparing: .preparing
        case .waiting: .waiting
        case .playing: .playing
        case .seeking: .seeking
        case .paused: .paused
        case .interrupted: .interrupted
        case .finished: .finished
        case .failed: .failed
        }
        guard self != .preparing, self != .failed else { return }

        if playback.intent == .paused {
            self = .paused
        } else if playback.intent == .playing,
                  self == .stopped || self == .paused || self == .finished {
            self = .waiting
        }
    }

    var isPlaybackActive: Bool {
        switch self {
        case .preparing, .waiting, .playing, .seeking: true
        case .noDisc, .paused, .interrupted, .stopped, .finished, .failed: false
        }
    }
}

struct ListeningPlayerPresentation: Equatable {
    let phase: ListeningPlayerPhase
    let source: ListeningPlaybackSource?
    let previewRemaining: TimeInterval?
    let playPauseAction: ListeningPlayPauseAction
    let blockingReason: String?
    let recoveryAction: ListeningRecoveryAction?
    let errorText: String?
    let noDiscMessage: String?

    var canPlayPause: Bool { playPauseAction != .disabled }
    var showsPauseControl: Bool { playPauseAction == .pause }

    var isPlaybackActive: Bool { phase.isPlaybackActive }

    var shouldRotateDisc: Bool { isPlaybackActive }

    var statusText: String {
        if let errorText, phase == .failed { return errorText }
        if let blockingReason, phase == .stopped { return blockingReason }
        switch phase {
        case .noDisc:
            return noDiscMessage ?? ListeningCopy.text("暂不可播放")
        case .preparing, .waiting:
            return ListeningCopy.text("载入中…")
        case .playing, .seeking:
            if source == .preview, let previewRemaining {
                return ListeningCopy.format("试听中 · 剩余 %d 秒", Int(ceil(max(0, previewRemaining))))
            }
            return ListeningCopy.text("播放中")
        case .paused, .interrupted:
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

enum ListeningMusicAccessPrompt: Equatable {
    case notDetermined
    case denied
    case restricted
}

/// What the room shell renders in the cabinet area. The view does not re-derive
/// authorization, catalog loading, or artist matching to choose it.
enum ListeningCatalogChrome: Equatable {
    case preparing
    case needsMusicAccess(ListeningMusicAccessPrompt)
    case connectArtist(slotIndex: Int?, name: String, isBrowsing: Bool)
    case unavailable(isStale: Bool)
    case empty
}

struct ListeningHardwareSnapshot: Equatable {
    var discID: String?
    var discTitle: String?
    var position: CDMechanism.Position = .stored
    var isAutomatic = false
    var isReturning = false
    var isCabinetDragging = false
    var isClosed = true
    var isOpen = false
    var hasDisc = false
    var artworkURL: URL?
    var notice: String?
    var occupiedAttemptCount = 0
    var lid = 0.0
    var discX = 230.0
    var discY = 489.0
    var lift = 0.0
    var discScale = 1.0
    var reducedMotion = false
    var partsAreMoving = false

    static let empty = ListeningHardwareSnapshot()
}

struct ListeningDisplayProjection: Equatable {
    let page: ListeningPresentation
    let roomMode: ListeningRoomPlaybackMode
    let headerNotice: ListeningHeaderNotice?
    let recoveryAction: ListeningRecoveryAction?
    let catalogChrome: ListeningCatalogChrome
    let hardware: ListeningHardwareSnapshot
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
        playback: ListeningPlaybackSnapshot,
        playbackError: String?,
        browsingArtist: ListeningBrowseArtist? = nil,
        isCatalogEnriching: Bool = false,
        unmatchedArtist: ListeningBrowseArtist? = nil,
        hardware: ListeningHardwareSnapshot = .empty
    ) -> ListeningDisplayProjection {
        let hasAnyTracks = allDiscs.contains(where: { !$0.tracks.isEmpty })
        let mode = roomMode(
            access: access,
            isAuthorizing: isAuthorizing || (!hasAnyTracks && (page == .loading || page == .loadingCatalog)),
            allDiscs: allDiscs,
            playback: playback
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
            playback: playback,
            playbackError: playbackError
        )

        return ListeningDisplayProjection(
            page: page,
            roomMode: mode,
            headerNotice: modeNotice,
            recoveryAction: recovery,
            catalogChrome: catalogChrome(
                page: page,
                access: access,
                isAuthorizing: isAuthorizing,
                allDiscs: allDiscs,
                libraryDiscs: libraryDiscs,
                browsingArtist: browsingArtist,
                isCatalogEnriching: isCatalogEnriching,
                unmatchedArtist: unmatchedArtist
            ),
            hardware: hardware,
            shelfDiscs: Array(libraryDiscs.prefix(Shelf.visibleCount)),
            showsAllDiscs: libraryDiscs.count > Shelf.visibleCount,
            player: player,
            access: access
        )
    }

    static func catalogChrome(
        page: ListeningPresentation,
        access: ListeningMusicAccess,
        isAuthorizing: Bool,
        allDiscs: [ListeningDisc],
        libraryDiscs: [ListeningDisc],
        browsingArtist: ListeningBrowseArtist?,
        isCatalogEnriching: Bool,
        unmatchedArtist: ListeningBrowseArtist?
    ) -> ListeningCatalogChrome {
        if isAuthorizing { return .preparing }
        if access.authorizationStatus != .authorized, allDiscs.isEmpty {
            return .needsMusicAccess(accessPrompt(access))
        }
        if let browsingArtist, !browsingArtist.isConnected {
            return .connectArtist(
                slotIndex: browsingArtist.slotIndex,
                name: browsingArtist.name,
                isBrowsing: true
            )
        }
        if isCatalogEnriching, libraryDiscs.isEmpty { return .preparing }
        switch page {
        case .loading, .loadingCatalog:
            return .preparing
        case .noConnectedArtists:
            return .connectArtist(
                slotIndex: unmatchedArtist?.slotIndex,
                name: unmatchedArtist?.name ?? "",
                isBrowsing: false
            )
        case .cachedWithError:
            return .unavailable(isStale: true)
        case .fatalUnavailable:
            return .unavailable(isStale: false)
        case .needsAuthorization, .noCurrentShow, .ready:
            return .empty
        }
    }

    private static func accessPrompt(_ access: ListeningMusicAccess) -> ListeningMusicAccessPrompt {
        switch access.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .notDetermined
        }
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
        allDiscs: [ListeningDisc],
        playback: ListeningPlaybackSnapshot
    ) -> ListeningRoomPlaybackMode {
        if isAuthorizing { return .connecting }
        // An established transport is the truth for what is playing now. Access
        // changes describe whether a future transport may be prepared; they must not
        // relabel an already-running preview or a full-catalog session whose access
        // check merely became temporarily inconclusive.
        if playback.source == .preview {
            return .preview
        }
        if playback.source == .fullCatalog {
            return .fullPlayback
        }
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
        case .connecting:
            return nil
        case .fullPlayback:
            if access.authorizationStatus == .authorized,
               access.catalogPlaybackAccess == .accessCheckFailed {
                return ListeningHeaderNotice(
                    message: ListeningCopy.text("暂时无法确认之后的完整播放权限。"),
                    recoveryAction: .retryAccess
                )
            }
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
        case .denied:
            return ListeningHeaderNotice(
                message: ListeningCopy.text(
                    hasPreview
                        ? "当前未允许访问 Apple Music。"
                        : "当前未允许访问 Apple Music，且这些歌曲没有可用试听片段。"
                ),
                recoveryAction: .openSettings
            )
        case .restricted:
            return ListeningHeaderNotice(
                message: ListeningCopy.text(
                    hasPreview
                        ? "Apple Music 访问受到系统限制，当前使用歌曲试听片段。"
                        : "Apple Music 访问受到系统限制，且这些歌曲没有可用试听片段。"
                ),
                recoveryAction: nil
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
                    message: hasPreview
                        ? BSLocalization.text("未开通 Apple Music 会员，提供 30 秒官方试听")
                        : ListeningCopy.text("当前 Apple Music 账户不支持完整播放，这些歌曲也没有可用试听片段。"),
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
        case .denied:
            return .openSettings
        case .restricted:
            return nil
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
        playback: ListeningPlaybackSnapshot,
        playbackError: String?
    ) -> ListeningPlayerPresentation {
        guard loadedDisc != nil, isDiscSeated, currentTrack != nil, let trackPresentation else {
            return ListeningPlayerPresentation(
                phase: .noDisc,
                source: nil,
                previewRemaining: nil,
                playPauseAction: .disabled,
                blockingReason: nil,
                recoveryAction: nil,
                errorText: nil,
                noDiscMessage: noDiscMessage(for: mode)
            )
        }

        let accessRecovery = recoveryAction(page: page, access: access, isAuthorizing: false)
        let keepsEstablishedFullCatalogSession = ListeningPlaybackSourceResolver.resolve(
            capability: trackPresentation.capability,
            access: access,
            establishedSource: playback.state.isFinished ? nil : playback.source
        ) == .fullCatalog
        if !trackPresentation.isPlayable && !keepsEstablishedFullCatalogSession {
            return ListeningPlayerPresentation(
                phase: .stopped,
                source: nil,
                previewRemaining: nil,
                playPauseAction: .disabled,
                blockingReason: trackPresentation.statusText,
                recoveryAction: accessRecovery,
                errorText: nil,
                noDiscMessage: nil
            )
        }

        if let playbackError {
            return ListeningPlayerPresentation(
                phase: .failed,
                source: playback.source,
                previewRemaining: previewRemaining(from: playback.state),
                playPauseAction: .disabled,
                blockingReason: playbackError,
                recoveryAction: .retryPlayback,
                errorText: playbackError,
                noDiscMessage: nil
            )
        }
        if case .failed = playback.state {
            return ListeningPlayerPresentation(
                phase: .failed,
                source: nil,
                previewRemaining: nil,
                playPauseAction: .disabled,
                blockingReason: ListeningCopy.text("暂时无法播放"),
                recoveryAction: .retryPlayback,
                errorText: ListeningCopy.text("暂时无法播放"),
                noDiscMessage: nil
            )
        }

        let lidReason = isLidClosed ? nil : ListeningCopy.text("请先合上播放器上盖")
        return ListeningPlayerPresentation(
            phase: ListeningPlayerPhase(playback: playback),
            source: playback.source,
            previewRemaining: previewRemaining(from: playback.state),
            playPauseAction: ListeningPlayPauseAction.resolve(
                state: playback.state,
                intent: playback.intent,
                canInitiatePlayback: trackPresentation.isPlayable || keepsEstablishedFullCatalogSession
            ),
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
            ListeningCopy.text("正在准备…")
        }
    }

    private static func previewRemaining(from state: ListeningPlaybackState) -> TimeInterval? {
        switch state {
        case let .ready(_, source, current, duration),
             let .waiting(_, source, current, duration),
             let .playing(_, source, current, duration),
             let .seeking(_, source, current, duration),
             let .paused(_, source, current, duration),
             let .interrupted(_, source, current, duration):
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
    private var hardwareSnapshot: ListeningHardwareSnapshot {
        let motion = mechanism.motion
        let partsAreMoving = motion.lid.target != nil
            || motion.discX.target != nil
            || motion.discY.target != nil
            || motion.discScale.target != nil
            || motion.lift.target != nil
        return ListeningHardwareSnapshot(
            discID: mechanism.disc?.id,
            discTitle: mechanism.disc?.title,
            position: mechanism.position,
            isAutomatic: mechanism.isAutomatic,
            isReturning: mechanism.isReturning,
            isCabinetDragging: mechanism.isCabinetDragging,
            isClosed: mechanism.isClosed,
            isOpen: mechanism.isOpen,
            hasDisc: mechanism.hasDisc,
            artworkURL: mechanism.disc?.artworkURL,
            notice: mechanism.notice,
            occupiedAttemptCount: mechanism.occupiedAttemptCount,
            lid: motion.lid.value,
            discX: motion.discX.value,
            discY: motion.discY.value,
            lift: motion.lift.value,
            discScale: motion.discScale.value,
            reducedMotion: motion.reducedMotion,
            partsAreMoving: partsAreMoving
        )
    }

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
            playback: playback,
            playbackError: playbackError,
            browsingArtist: browsingArtist,
            isCatalogEnriching: isCatalogEnriching,
            unmatchedArtist: browseArtists.first { !$0.isConnected },
            hardware: hardwareSnapshot
        )
    }

    var hasLoadedDisc: Bool { mechanism.hasDisc }

    var hardwareGeometry: CDPlayerConfiguration.Geometry { mechanism.configuration.geometry }

    var playerConfiguration: CDPlayerConfiguration { mechanism.configuration }

    func disc(id: String) -> ListeningDisc? {
        if mechanism.disc?.id == id { return mechanism.disc }
        return discs.first { $0.id == id }
    }

    var atmospherePhase: ListeningAtmospherePhase {
        ListeningAtmospherePhase(
            isPlacing: mechanism.isAutomatic || mechanism.position == .removed || mechanism.isOpen,
            isPlaying: display.player.isPlaybackActive
        )
    }

    func setReducedMotion(_ value: Bool) {
        mechanism.motion.reducedMotion = value
    }

    func stopHardwareMotion() {
        mechanism.motion.stop()
    }

    func dismissError() {
        errorText = nil
    }

    func beginCabinetDragIfNeeded(_ disc: ListeningDisc) -> Bool {
        guard !mechanism.isCabinetDragging else { return false }
        return beginPlayableDiscDrag(disc)
    }

    func updateCabinetDrag(of disc: ListeningDisc, translation: CGSize, scale: CGFloat) {
        guard mechanism.isCabinetDragging, mechanism.disc?.id == disc.id, scale > 0 else { return }
        let tilt = mechanism.configuration.geometry.tiltDegrees * .pi / 180
        mechanism.dragDisc(CGSize(
            width: translation.width / scale,
            height: translation.height / scale / cos(tilt)
        ))
    }

    func endCabinetDrag(of disc: ListeningDisc) {
        guard mechanism.isCabinetDragging, mechanism.disc?.id == disc.id else { return }
        mechanism.endDiscDrag()
    }

    func dragLoadedDisc(translation: CGSize, scale: CGFloat) {
        guard scale > 0 else { return }
        let tilt = mechanism.configuration.geometry.tiltDegrees * .pi / 180
        mechanism.dragDisc(CGSize(
            width: translation.width / scale,
            height: translation.height / scale / cos(tilt)
        ))
    }

    func endLoadedDiscDrag() {
        mechanism.endDiscDrag()
    }

    func removeLoadedDisc() {
        mechanism.removeDisc()
    }

    func returnLoadedDisc() {
        if mechanism.position == .seated {
            mechanism.returnCurrentDiscToCabinet()
        } else {
            mechanism.returnDisc()
        }
    }

    func insertLoadedDisc() {
        mechanism.insertDisc()
    }

    func dragLid(translation: CGFloat, scale: CGFloat) {
        guard scale > 0 else { return }
        mechanism.dragLid(translation / scale)
    }

    func endLidDrag(translation: CGFloat, predicted: CGFloat, scale: CGFloat) {
        guard scale > 0 else { return }
        mechanism.endLidDrag(translation / scale, predicted: predicted / scale)
    }

    func setLid(open: Bool) {
        mechanism.setLid(open: open)
    }

    func adjacentLoadedTrack(delta: Int) -> ListeningDiscTrack? {
        guard mechanism.isClosed, let disc = mechanism.disc else { return nil }
        let index = trackIndex + delta
        guard disc.tracks.indices.contains(index) else { return nil }
        return disc.tracks[index]
    }

    func applyListeningFrames(_ frames: [String: CGRect]) {
        guard let stage = frames["stage"], stage.width > 0 else { return }
        let geometry = mechanism.configuration.geometry
        let stageScale = stage.width / geometry.canvas.width
        let cosine = cos(geometry.tiltDegrees * .pi / 180)
        func convert(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - stage.minX) / stageScale,
                y: geometry.hingeY + ((point.y - stage.minY) / stageScale - geometry.hingeY) / cosine
            )
        }
        var newSlots: [String: CGPoint] = [:]
        var newCabinetScale = mechanism.cabinetScale
        for disc in discs {
            if let frame = frames["slot:\(disc.id)"] {
                newSlots[disc.id] = convert(CGPoint(x: frame.midX, y: frame.midY))
                newCabinetScale = frame.width / stageScale / geometry.discDiameter
            }
        }
        if mechanism.cabinetSlots != newSlots {
            mechanism.cabinetSlots = newSlots
        }
        if abs(mechanism.cabinetScale - newCabinetScale) > 0.001 {
            mechanism.cabinetScale = newCabinetScale
        }
        if let frame = frames["cabinet"] {
            let origin = convert(frame.origin)
            let newDropZone = CGRect(
                x: origin.x,
                y: origin.y,
                width: frame.width / stageScale,
                height: frame.height / stageScale / cosine
            )
            if mechanism.cabinetDropZone != newDropZone {
                mechanism.cabinetDropZone = newDropZone
            }
        }
    }

    func discPresentation(for disc: ListeningDisc) -> ListeningDiscPresentation {
        ListeningDisplayProjector.discPresentation(for: disc, access: access)
    }

    func trackPresentation(for track: ListeningDiscTrack) -> ListeningTrackPresentation {
        if canReuseEstablishedFullCatalogTransport(for: track) {
            return ListeningTrackPresentation(capability: .fullPlayback)
        }
        return ListeningDisplayProjector.trackPresentation(for: track, access: access)
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
