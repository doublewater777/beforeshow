import Foundation
import UIKit

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
    case failed

    var isPlaybackActive: Bool {
        switch self {
        case .preparing, .waiting, .playing, .seeking: true
        case .noDisc, .paused, .interrupted, .stopped, .failed: false
        }
    }
}

/// What the player projection reads from the deck.
struct ListeningPlayerTransport: Equatable {
    var phase: ListeningPlayerPhase = .stopped
    var source: ListeningPlaybackSource?
    var time: TimeInterval = 0
    var duration: TimeInterval?
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
    case connectArtist(slotIndex: Int?, name: String)
    case unavailable(isStale: Bool)
    case empty
}

struct ListeningDisplayProjection: Equatable {
    let page: ListeningPresentation
    let roomMode: ListeningRoomPlaybackMode
    let headerNotice: ListeningHeaderNotice?
    let recoveryAction: ListeningRecoveryAction?
    let catalogChrome: ListeningCatalogChrome
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
        currentTrack: ListeningDiscTrack?,
        transport: ListeningPlayerTransport,
        playbackError: String?,
        browsingArtist: ListeningBrowseArtist? = nil,
        isCatalogEnriching: Bool = false,
        unmatchedArtist: ListeningBrowseArtist? = nil
    ) -> ListeningDisplayProjection {
        let hasAnyTracks = allDiscs.contains(where: { !$0.tracks.isEmpty })
        let mode = roomMode(
            access: access,
            isAuthorizing: isAuthorizing || (!hasAnyTracks && (page == .loading || page == .loadingCatalog)),
            allDiscs: allDiscs,
            transport: transport
        )
        let modeNotice = headerNotice(mode: mode, access: access)
        let recovery = recoveryAction(page: page, access: access, isAuthorizing: isAuthorizing)
        let currentTrackState = currentTrack.map { trackPresentation(for: $0, access: access) }
        let player = playerPresentation(
            mode: mode,
            access: access,
            page: page,
            loadedDisc: loadedDisc,
            currentTrack: currentTrack,
            trackPresentation: currentTrackState,
            transport: transport,
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
                name: browsingArtist.name
            )
        }
        if isCatalogEnriching, libraryDiscs.isEmpty { return .preparing }
        switch page {
        case .loading, .loadingCatalog:
            return .preparing
        case .noConnectedArtists:
            return .connectArtist(
                slotIndex: unmatchedArtist?.slotIndex,
                name: unmatchedArtist?.name ?? ""
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
        transport: ListeningPlayerTransport
    ) -> ListeningRoomPlaybackMode {
        if isAuthorizing { return .connecting }
        // An established transport is the truth for what is playing now. Access
        // changes describe whether a future transport may be prepared; they must not
        // relabel an already-running preview or a full-catalog session whose access
        // check merely became temporarily inconclusive.
        if transport.source == .preview {
            return .preview
        }
        if transport.source == .fullCatalog {
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
        currentTrack: ListeningDiscTrack?,
        trackPresentation: ListeningTrackPresentation?,
        transport: ListeningPlayerTransport,
        playbackError: String?
    ) -> ListeningPlayerPresentation {
        guard loadedDisc != nil, currentTrack != nil, let trackPresentation else {
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
            establishedSource: transport.source
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

        if let failure = playbackError ?? (transport.phase == .failed ? ListeningCopy.text("暂时无法播放") : nil) {
            return ListeningPlayerPresentation(
                phase: .failed,
                source: transport.source,
                previewRemaining: previewRemaining(from: transport),
                playPauseAction: .disabled,
                blockingReason: failure,
                recoveryAction: .retryPlayback,
                errorText: failure,
                noDiscMessage: nil
            )
        }

        return ListeningPlayerPresentation(
            phase: transport.phase,
            source: transport.source,
            previewRemaining: previewRemaining(from: transport),
            // Pending commands give immediate feedback while preparing or buffering.
            // Interrupted playback offers Play; automatic resumption is not guaranteed.
            playPauseAction: transport.phase.isPlaybackActive ? .pause : .play,
            blockingReason: nil,
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

    private static func previewRemaining(from transport: ListeningPlayerTransport) -> TimeInterval? {
        guard transport.source == .preview, let duration = transport.duration else { return nil }
        switch transport.phase {
        case .waiting, .playing, .seeking, .paused, .interrupted, .stopped:
            return max(0, duration - transport.time)
        case .noDisc, .preparing, .failed:
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
            loadedDisc: loadedDisc,
            currentTrack: track,
            transport: ListeningPlayerTransport(
                phase: deck.phase,
                source: deck.source,
                time: deck.time,
                duration: deck.duration
            ),
            playbackError: playbackError,
            browsingArtist: browsingArtist,
            isCatalogEnriching: isCatalogEnriching,
            unmatchedArtist: browseArtists.first { !$0.isConnected }
        )
    }

    var hasLoadedDisc: Bool { loadedDisc != nil }

    func disc(id: String) -> ListeningDisc? {
        if loadedDisc?.id == id { return loadedDisc }
        return discs.first { $0.id == id }
    }

    var atmospherePhase: ListeningAtmospherePhase {
        ListeningAtmospherePhase(isPlaying: display.player.isPlaybackActive)
    }

    /// The song Next/Previous would reach, in play order.
    func adjacentLoadedTrack(delta: Int) -> ListeningDiscTrack? {
        guard loadedDisc != nil, let songID = deck.adjacentSongID(delta) else { return nil }
        return deck.tracks.first { $0.id == songID }
    }

    func discPresentation(for disc: ListeningDisc) -> ListeningDiscPresentation {
        ListeningDisplayProjector.discPresentation(for: disc, access: access)
    }

    func trackPresentation(for track: ListeningDiscTrack) -> ListeningTrackPresentation {
        if playbackSource(for: track) == .fullCatalog {
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
        guard let targetSongID else { return }
        playbackError = nil
        loadDisc(disc, songID: targetSongID)
    }

    func performListeningRecovery(_ action: ListeningRecoveryAction) {
        switch action {
        case .authorize:
            Task { await authorize() }
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
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
