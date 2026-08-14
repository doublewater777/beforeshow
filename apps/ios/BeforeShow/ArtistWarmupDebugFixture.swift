import Foundation

struct ArtistWarmupDebugFixture: Equatable {
    enum State: String, CaseIterable, Equatable {
        case noCurrentShow = "no-current-show"
        case canceledShow = "canceled-show"
        case postponedUndated = "postponed-undated"
        case matchingUnconnected = "matching-unconnected"
        case authorizationDenied = "authorization-denied"
        case noSubscription = "no-subscription"
        case preShowSingle = "pre-show-single"
        case preShowMulti = "pre-show-multi"
        case catalogLoading = "catalog-loading"
        case catalogComplete = "catalog-complete"
        case nowPlaying = "now-playing"
        case postShowRecall = "post-show-recall"

        static func parseLaunchArguments(_ arguments: [String]) -> State? {
            guard let flagIndex = arguments.firstIndex(of: "--artist-warmup-fixture") else {
                return nil
            }

            let valueIndex = arguments.index(after: flagIndex)
            guard arguments.indices.contains(valueIndex) else {
                return nil
            }

            return State(rawValue: arguments[valueIndex])
        }
    }

    let state: State
    let presentation: ArtistWarmupPresentationState

    static var requestedState: State? {
        #if DEBUG
        State.parseLaunchArguments(ProcessInfo.processInfo.arguments)
        #else
        nil
        #endif
    }

    static func make(_ state: State) -> ArtistWarmupDebugFixture {
        ArtistWarmupDebugFixture(
            state: state,
            presentation: presentation(for: state)
        )
    }

    private static func presentation(for state: State) -> ArtistWarmupPresentationState {
        switch state {
        case .noCurrentShow:
            ArtistWarmupPresentationState(
                screen: .noCurrentShow,
                showTitle: "还没有当前现场",
                showSubtitle: "放进一场想去的现场，再开始艺人预热。",
                lifecycle: makeLifecycle(.noCurrentShow)
            )
        case .canceledShow:
            ArtistWarmupPresentationState(
                screen: .unavailable,
                showTitle: "这场已取消",
                showSubtitle: "取消后不会主动生成预热队列。",
                lifecycle: makeLifecycle(.unavailable),
                artists: [jay()]
            )
        case .postponedUndated:
            home(
                title: "时间待定的现场",
                subtitle: "改期未定，可以继续听歌，但不开启倒计时提醒。",
                lifecycle: ArtistWarmupLifecycle.resolve(
                    show: .undatedPostponed,
                    music: .connected,
                    artistMatch: .matched,
                    now: fixtureNow,
                    calendar: fixtureCalendar
                ),
                artists: [jay()]
            )
        case .matchingUnconnected:
            ArtistWarmupPresentationState(
                screen: .candidateConnection,
                showTitle: "Super Dome",
                showSubtitle: "先确认艺人，再单独连接 Apple Music。",
                lifecycle: makeLifecycle(.matchingOrUnconnected),
                artists: [jay(connected: false)]
            )
        case .authorizationDenied:
            ArtistWarmupPresentationState(
                screen: .authorizationDenied,
                showTitle: "Super Dome",
                showSubtitle: "艺人已确认，但音乐访问未开启。",
                lifecycle: makeLifecycle(.warmup),
                artists: [jay()],
                songs: sampleSongs
            )
        case .noSubscription:
            ArtistWarmupPresentationState(
                screen: .noSubscription,
                showTitle: "Super Dome",
                showSubtitle: "仍可浏览曲库、写印象、手动补记听过。",
                lifecycle: makeLifecycle(.warmup),
                artists: [jay()],
                songs: sampleSongs
            )
        case .preShowSingle:
            home(
                title: "Super Dome",
                subtitle: "57 天后开场",
                lifecycle: preShowLifecycle(),
                artists: [jay()],
                songs: sampleSongs
            )
        case .preShowMulti:
            home(
                title: "大港开唱",
                subtitle: "多艺人预热",
                lifecycle: preShowLifecycle(),
                artists: [
                    jay(),
                    mayday(),
                    cheer()
                ],
                songs: sampleSongs
            )
        case .catalogLoading:
            home(
                screen: .catalogLoading,
                title: "周杰伦的曲库",
                subtitle: "正在整理 Apple Music 音频曲库。",
                lifecycle: preShowLifecycle(),
                artists: [jay(catalogComplete: false)],
                songs: []
            )
        case .catalogComplete:
            home(
                screen: .catalog,
                title: "周杰伦的曲库",
                subtitle: "完整去重音频曲库",
                lifecycle: preShowLifecycle(),
                artists: [jay()],
                songs: sampleSongs
            )
        case .nowPlaying:
            home(
                screen: .player,
                title: "Super Dome",
                subtitle: "预热队列",
                lifecycle: preShowLifecycle(),
                artists: [jay()],
                songs: sampleSongs,
                nowPlayingSongID: "jay-mojito"
            )
        case .postShowRecall:
            ArtistWarmupPresentationState(
                screen: .postShowRecall,
                showTitle: "Super Dome",
                showSubtitle: "昨晚已散场",
                lifecycle: ArtistWarmupLifecycle.resolve(
                    show: .scheduled(startsAt: fixtureNow.addingTimeInterval(-18 * 60 * 60)),
                    music: .connected,
                    artistMatch: .matched,
                    now: fixtureNow,
                    calendar: fixtureCalendar
                ),
                artists: [jay(), mayday(), cheer()],
                songs: sampleSongs,
                recallSongIDs: ["jay-sunny"]
            )
        }
    }

    private static func home(
        screen: ArtistWarmupPresentationScreen = .home,
        title: String,
        subtitle: String,
        lifecycle: ArtistWarmupLifecycleState,
        artists: [ArtistWarmupPresentedArtist],
        songs: [ArtistWarmupPresentedSong] = [],
        nowPlayingSongID: String? = nil
    ) -> ArtistWarmupPresentationState {
        ArtistWarmupPresentationState(
            screen: screen,
            showTitle: title,
            showSubtitle: subtitle,
            lifecycle: lifecycle,
            artists: artists,
            songs: songs,
            nowPlayingSongID: nowPlayingSongID
        )
    }

    private static func preShowLifecycle() -> ArtistWarmupLifecycleState {
        ArtistWarmupLifecycle.resolve(
            show: .scheduled(startsAt: fixtureNow.addingTimeInterval(57 * 24 * 60 * 60)),
            music: .connected,
            artistMatch: .matched,
            now: fixtureNow,
            calendar: fixtureCalendar
        )
    }

    private static let fixtureNow = Date(timeIntervalSince1970: 1_783_468_800)

    private static var fixtureCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    private static func jay(connected: Bool = true, catalogComplete: Bool = true) -> ArtistWarmupPresentedArtist {
        ArtistWarmupPresentedArtist(
            id: "artist-jay",
            displayName: "周杰伦",
            providerName: connected ? "周杰伦" : nil,
            artworkURL: nil,
            interest: .wanted,
            isConnected: connected,
            familiarity: .init(
                heardSongCount: catalogComplete ? 12 : 0,
                catalogSongCount: catalogComplete ? 48 : 0,
                hasCompleteCatalog: catalogComplete
            )
        )
    }

    private static func mayday() -> ArtistWarmupPresentedArtist {
        ArtistWarmupPresentedArtist(
            id: "artist-mayday",
            displayName: "五月天",
            providerName: "五月天",
            artworkURL: nil,
            interest: .maybe,
            isConnected: true,
            familiarity: .init(heardSongCount: 4, catalogSongCount: 32, hasCompleteCatalog: true)
        )
    }

    private static func cheer() -> ArtistWarmupPresentedArtist {
        ArtistWarmupPresentedArtist(
            id: "artist-cheer",
            displayName: "陈绮贞",
            providerName: "陈绮贞",
            artworkURL: nil,
            interest: .notInterested,
            isConnected: true,
            familiarity: .init(heardSongCount: 22, catalogSongCount: 22, hasCompleteCatalog: true)
        )
    }

    private static let sampleSongs: [ArtistWarmupPresentedSong] = [
        ArtistWarmupPresentedSong(
            id: "jay-mojito",
            artistID: "artist-jay",
            title: "Mojito",
            albumTitle: "最伟大的作品",
            artistName: "周杰伦",
            isHeard: false,
            wantsLive: true,
            hasImpression: false
        ),
        ArtistWarmupPresentedSong(
            id: "jay-sunny",
            artistID: "artist-jay",
            title: "晴天",
            albumTitle: "叶惠美",
            artistName: "周杰伦",
            isHeard: false,
            wantsLive: false,
            hasImpression: false
        ),
        ArtistWarmupPresentedSong(
            id: "jay-longtitle",
            artistID: "artist-jay",
            title: "我是如此相信（电影《天火》主题曲）",
            albumTitle: "我是如此相信 - Single",
            artistName: "周杰伦",
            isHeard: true,
            wantsLive: false,
            hasImpression: true,
            category: .single
        )
    ]
}

enum ArtistWarmupPresentationScreen: Equatable {
    case noCurrentShow
    case unavailable
    case candidateConnection
    case authorizationDenied
    case noSubscription
    case home
    case catalogLoading
    case catalog
    case player
    case postShowRecall

    var hidesFloatingTab: Bool {
        switch self {
        case .catalogLoading, .catalog, .player:
            true
        case .noCurrentShow,
             .unavailable,
             .candidateConnection,
             .authorizationDenied,
             .noSubscription,
             .home,
             .postShowRecall:
            false
        }
    }
}

struct ArtistWarmupPresentationState: Equatable {
    var screen: ArtistWarmupPresentationScreen
    var showTitle: String
    var showSubtitle: String?
    var lifecycle: ArtistWarmupLifecycleState
    var artists: [ArtistWarmupPresentedArtist] = []
    var songs: [ArtistWarmupPresentedSong] = []
    var impressions: [String: ArtistWarmupPresentedImpression] = [:]
    var recallSongIDs: [String] = []
    var nowPlayingSongID: String?
    var hasEmptyWarmupQueue: Bool = false

    static var empty: ArtistWarmupPresentationState {
        ArtistWarmupPresentationState(
            screen: .noCurrentShow,
            showTitle: "还没有当前现场",
            showSubtitle: "放进一场想去的现场，再开始艺人预热。",
            lifecycle: makeLifecycle(.noCurrentShow)
        )
    }

    func savingImpression(
        songID: String,
        wantsLive: Bool,
        hasFeeling: Bool,
        note: String?
    ) -> ArtistWarmupPresentationState {
        var copy = self
        copy.impressions[songID] = ArtistWarmupPresentedImpression(
            songID: songID,
            wantsLive: wantsLive,
            hasFeeling: hasFeeling,
            note: note
        )
        copy.songs = copy.songs.map { song in
            guard song.id == songID else { return song }
            var changed = song
            changed.wantsLive = wantsLive
            changed.hasImpression = hasFeeling || !(note?.isEmpty ?? true)
            return changed
        }
        return copy
    }
}

private func makeLifecycle(_ route: ArtistWarmupRoute) -> ArtistWarmupLifecycleState {
    ArtistWarmupLifecycleState(
        route: route,
        isOpeningSnapshotEligible: false,
        isDateReminderEligible: false
    )
}

struct ArtistWarmupPresentedArtist: Identifiable, Equatable {
    var id: String
    var displayName: String
    var providerName: String?
    var artworkURL: String?
    var interest: ArtistInterest
    var isConnected: Bool
    var familiarity: ArtistWarmupPresentedFamiliarity

    var resolvedName: String {
        providerName ?? displayName
    }
}

struct ArtistWarmupPresentedFamiliarity: Equatable {
    var heardSongCount: Int
    var catalogSongCount: Int
    var hasCompleteCatalog: Bool = false

    var percent: Int {
        guard hasCompleteCatalog, catalogSongCount > 0 else { return 0 }
        return min(100, Int((Double(heardSongCount) / Double(catalogSongCount) * 100).rounded(.down)))
    }

    var tierLabel: String {
        ArtistFamiliarityTier.label(forPercent: percent)
    }
}

struct ArtistWarmupPresentedSong: Identifiable, Equatable {
    let id: String
    var artistID: String
    var title: String
    var albumTitle: String?
    var artistName: String
    var isHeard: Bool
    var wantsLive: Bool
    var hasImpression: Bool
    var category: CatalogSongCategory = .album
}

struct ArtistWarmupPresentedImpression: Equatable {
    var songID: String
    var wantsLive: Bool
    var hasFeeling: Bool
    var note: String?
}

enum ArtistWarmupLivePresentationBuilder {
    static func make(
        shows: [Show],
        selections: [CurrentShowSelection],
        showArtists: [ShowArtist],
        catalogSnapshots: [ArtistCatalogSnapshot],
        catalogSongs: [CatalogSong],
        familiarityRecords: [SongFamiliarityRecord],
        impressions: [ShowSongImpression],
        recallRecords: [ShowSetlistMemory],
        now: Date = Date(),
        calendar: Calendar = .current,
        authorizationStatus: ArtistWarmupAuthorizationStatus = .notDetermined,
        subscriptionCapability: ArtistWarmupSubscriptionCapability? = nil
    ) -> ArtistWarmupPresentationState {
        let session = CurrentShowSession(calendar: calendar)
        guard let snapshot = session.resolve(
            shows: shows,
            manualSelection: selections.first,
            now: now
        ) else {
            return .empty
        }

        let show = snapshot.show
        let artists = artistsForShow(show, showArtists: showArtists)
        let music: ArtistWarmupMusicConnection = artists.allSatisfy(\.isConnected) && !artists.isEmpty
            ? .connected
            : .unconnected
        let match: ArtistWarmupArtistMatch = music == .connected ? .matched : .matching
        let lifecycle = ArtistWarmupLifecycle.resolve(
            show: warmupShow(from: show, snapshot: snapshot),
            music: music,
            artistMatch: match,
            now: now,
            calendar: calendar
        )

        if lifecycle.route == .unavailable {
            return ArtistWarmupPresentationState(
                screen: .unavailable,
                showTitle: show.name,
                showSubtitle: "这场已取消，预热已停止。",
                lifecycle: lifecycle,
                artists: artists
            )
        }

        if lifecycle.route == .matchingOrUnconnected {
            return ArtistWarmupPresentationState(
                screen: .candidateConnection,
                showTitle: show.name,
                showSubtitle: "先确认艺人，再单独连接 Apple Music。",
                lifecycle: lifecycle,
                artists: artists
            )
        }

        let songs = presentedSongs(
            artists: artists,
            catalogSongs: catalogSongs,
            familiarityRecords: familiarityRecords,
            impressions: impressions,
            showID: show.id
        )
        let presentedArtists = artists.map {
            artistWithFamiliarity(
                $0,
                catalogSnapshots: catalogSnapshots,
                familiarityRecords: familiarityRecords
            )
        }
        let emptyQueue = !presentedArtists.isEmpty && presentedArtists.allSatisfy { $0.interest == .notInterested }
        let screen: ArtistWarmupPresentationScreen
        if lifecycle.route == .postShowRecall {
            screen = .postShowRecall
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            screen = .authorizationDenied
        } else if authorizationStatus == .authorized,
                  subscriptionCapability?.canPlayCatalogContent == false {
            screen = .noSubscription
        } else {
            screen = .home
        }

        return ArtistWarmupPresentationState(
            screen: screen,
            showTitle: show.name,
            showSubtitle: ShowDisplayFormatter(calendar: calendar).dateText(for: show),
            lifecycle: lifecycle,
            artists: presentedArtists,
            songs: songs,
            impressions: Dictionary(uniqueKeysWithValues: impressions
                .filter { $0.showID == show.id }
                .map {
                    (
                        $0.songID,
                        ArtistWarmupPresentedImpression(
                            songID: $0.songID,
                            wantsLive: $0.wantsLive,
                            hasFeeling: $0.hasFeeling,
                            note: $0.note
                        )
                    )
                }),
            recallSongIDs: recallRecords
                .filter { $0.showID == show.id }
                .compactMap(\.catalogSongID),
            hasEmptyWarmupQueue: emptyQueue
        )
    }

    private static func artistsForShow(
        _ show: Show,
        showArtists: [ShowArtist]
    ) -> [ArtistWarmupPresentedArtist] {
        let stored = showArtists
            .filter { $0.showID == show.id }
            .sorted { $0.originalOrder < $1.originalOrder }
            .map {
                ArtistWarmupPresentedArtist(
                    id: $0.appleMusicArtistID ?? $0.id.uuidString,
                    displayName: $0.originalArtistLabel,
                    providerName: $0.appleMusicArtistName,
                    artworkURL: $0.appleMusicArtworkURL,
                    interest: $0.interest,
                    isConnected: $0.isConnectedToAppleMusic,
                    familiarity: .init(heardSongCount: 0, catalogSongCount: 0)
                )
            }

        if !stored.isEmpty {
            return stored
        }

        return artistLabels(from: show.artist).enumerated().map { index, label in
            ArtistWarmupPresentedArtist(
                id: "candidate-\(show.id.uuidString)-\(index)",
                displayName: label,
                providerName: nil,
                artworkURL: nil,
                interest: .maybe,
                isConnected: false,
                familiarity: .init(heardSongCount: 0, catalogSongCount: 0)
            )
        }
    }

    private static func warmupShow(
        from show: Show,
        snapshot: CurrentShowSnapshot
    ) -> ArtistWarmupShow {
        if show.changeStatus == .canceled {
            return .canceled
        }
        if snapshot.phase.kind == .postponed && show.postponedDate == nil {
            return .undatedPostponed
        }
        return .scheduled(startsAt: snapshot.phase.effectiveStartTime ?? show.effectiveDate)
    }

    private static func artistLabels(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }
        let separators = CharacterSet(charactersIn: ",，、/&＋+|")
        return rawValue
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func artistWithFamiliarity(
        _ artist: ArtistWarmupPresentedArtist,
        catalogSnapshots: [ArtistCatalogSnapshot],
        familiarityRecords: [SongFamiliarityRecord]
    ) -> ArtistWarmupPresentedArtist {
        guard let catalog = catalogSnapshots.first(where: { $0.artistID == artist.id }),
              catalog.state == .complete else {
            return artist
        }

        var copy = artist
        let heardIDs = Set(familiarityRecords.map(\.songID))
        copy.familiarity = .init(
            heardSongCount: catalog.uniqueSongIDs.filter { heardIDs.contains($0) }.count,
            catalogSongCount: catalog.uniqueSongIDs.count,
            hasCompleteCatalog: true
        )
        return copy
    }

    private static func presentedSongs(
        artists: [ArtistWarmupPresentedArtist],
        catalogSongs: [CatalogSong],
        familiarityRecords: [SongFamiliarityRecord],
        impressions: [ShowSongImpression],
        showID: UUID
    ) -> [ArtistWarmupPresentedSong] {
        let connectedArtistIDs = Set(artists.map(\.id))
        let heardIDs = Set(familiarityRecords.map(\.songID))
        let impressionBySong = Dictionary(uniqueKeysWithValues: impressions
            .filter { $0.showID == showID }
            .map { ($0.songID, $0) })

        return catalogSongs
            .filter { song in
                !connectedArtistIDs.isDisjoint(with: song.performingArtistIDs)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { song in
                let ownerID = song.performingArtistIDs.first(where: { connectedArtistIDs.contains($0) })
                    ?? song.performingArtistIDs.first
                    ?? "unknown"
                let impression = impressionBySong[song.appleMusicSongID]
                return ArtistWarmupPresentedSong(
                    id: song.appleMusicSongID,
                    artistID: ownerID,
                    title: song.title,
                    albumTitle: song.albumTitle,
                    artistName: song.performingArtistNames.first ?? "",
                    isHeard: heardIDs.contains(song.appleMusicSongID),
                    wantsLive: impression?.wantsLive ?? false,
                    hasImpression: impression.map { $0.hasFeeling || $0.note != nil } ?? false,
                    category: song.category
                )
            }
    }
}
