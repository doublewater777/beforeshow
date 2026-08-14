import Foundation

public enum ArtistInterest: Equatable {
    case wanted
    case maybe
    case notInterested

    public var label: String {
        switch self {
        case .wanted:
            "想看"
        case .maybe:
            "待定"
        case .notInterested:
            "不看"
        }
    }
}

public enum ArtistCatalogEnumeration: Equatable {
    case partial(songIDs: [String])
    case complete(songIDs: [String])

    fileprivate var completeSongIDs: [String]? {
        switch self {
        case .partial:
            nil
        case let .complete(songIDs):
            songIDs
        }
    }
}

public struct ArtistFamiliaritySummary: Equatable {
    public let heardSongCount: Int
    public let catalogSongCount: Int
    public let percent: Int

    public var tierLabel: String {
        ArtistFamiliarityTier.label(forPercent: percent)
    }
}

public enum ArtistFamiliarityTier {
    public static func label(forPercent percent: Int) -> String {
        switch percent {
        case 0:
            "初见听众"
        case 1...24:
            "新晋听众"
        case 25...49:
            "入坑乐迷"
        case 50...74:
            "熟悉乐迷"
        case 75...99:
            "深度乐迷"
        default:
            "全曲库知己"
        }
    }
}

public enum ArtistFamiliarity {
    public static func summary(
        catalogEnumeration: ArtistCatalogEnumeration,
        heardSongIDs: [String]
    ) -> ArtistFamiliaritySummary? {
        guard let catalogSongIDs = catalogEnumeration.completeSongIDs else {
            return nil
        }

        let catalogIDs = Set(catalogSongIDs)
        guard !catalogIDs.isEmpty else {
            return nil
        }

        let heardInCatalog = Set(heardSongIDs).intersection(catalogIDs)
        let percent = Int((Double(heardInCatalog.count) / Double(catalogIDs.count) * 100).rounded(.down))

        return ArtistFamiliaritySummary(
            heardSongCount: heardInCatalog.count,
            catalogSongCount: catalogIDs.count,
            percent: percent
        )
    }
}

public struct ArtistWarmupImpressionLedger: Equatable {
    public let impressedSongIDs: [String]

    public init(impressedSongIDs: [String]) {
        self.impressedSongIDs = impressedSongIDs
    }

    public var uniqueImpressedSongCount: Int {
        Set(impressedSongIDs).count
    }
}

public enum ArtistWarmupShow: Equatable {
    case scheduled(startsAt: Date)
    case canceled
    case undatedPostponed
}

public enum ArtistWarmupMusicConnection: Equatable {
    case connected
    case unconnected
}

public enum ArtistWarmupArtistMatch: Equatable {
    case matched
    case matching
}

public enum ArtistWarmupRoute: Equatable {
    case noCurrentShow
    case matchingOrUnconnected
    case warmup
    case postShowRecall
    case unavailable
}

public struct ArtistWarmupLifecycleState: Equatable {
    public let route: ArtistWarmupRoute
    public let isOpeningSnapshotEligible: Bool
    public let isDateReminderEligible: Bool
}

public enum ArtistWarmupLifecycle {
    private static let recallRetentionDays = 3

    public static func resolve(
        show: ArtistWarmupShow?,
        music: ArtistWarmupMusicConnection,
        artistMatch: ArtistWarmupArtistMatch,
        now: Date,
        calendar: Calendar
    ) -> ArtistWarmupLifecycleState {
        guard let show else {
            return state(route: .noCurrentShow)
        }

        if show == .canceled {
            return state(route: .unavailable)
        }

        guard music == .connected, artistMatch == .matched else {
            return state(route: .matchingOrUnconnected)
        }

        switch show {
        case .canceled:
            return state(route: .unavailable)
        case .undatedPostponed:
            return state(route: .warmup)
        case let .scheduled(startsAt):
            if startsAt > now {
                return state(
                    route: .warmup,
                    isOpeningSnapshotEligible: true,
                    isDateReminderEligible: true
                )
            }

            let retentionEnd = calendar.date(
                byAdding: .day,
                value: recallRetentionDays,
                to: startsAt
            ) ?? startsAt

            if now <= retentionEnd {
                return state(route: .postShowRecall)
            }

            return state(route: .noCurrentShow)
        }
    }

    private static func state(
        route: ArtistWarmupRoute,
        isOpeningSnapshotEligible: Bool = false,
        isDateReminderEligible: Bool = false
    ) -> ArtistWarmupLifecycleState {
        ArtistWarmupLifecycleState(
            route: route,
            isOpeningSnapshotEligible: isOpeningSnapshotEligible,
            isDateReminderEligible: isDateReminderEligible
        )
    }
}

public struct ArtistWarmupTrack: Equatable {
    public let id: String
    public let artistID: String
    public let interest: ArtistInterest

    public init(id: String, artistID: String, interest: ArtistInterest) {
        self.id = id
        self.artistID = artistID
        self.interest = interest
    }
}

public enum ArtistWarmupQueueScope: Equatable {
    case allArtists
    case artistOnly(String)
}

public enum CatalogSongPresentationGroup: String, CaseIterable, Equatable {
    case albums = "专辑"
    case singles = "单曲"
    case collaborations = "合作作品"
}

public enum CatalogSongPresentationGrouping {
    static func group(_ songs: [CatalogSong]) -> [CatalogSongPresentationGroup: [CatalogSong]] {
        Dictionary(grouping: songs) { group(for: $0) }
    }

    static func group(for song: CatalogSong) -> CatalogSongPresentationGroup {
        switch song.category {
        case .single:
            .singles
        case .collaboration:
            .collaborations
        case .album:
            .albums
        }
    }
}

public enum ShowArtistLabelSplitter {
    public static func labels(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }

        var normalized = rawValue
        let wordSeparators = [" feat. ", " feat ", " ft. ", " ft ", " featuring ", " x ", " X ", " vs. ", " vs "]
        for separator in wordSeparators {
            normalized = normalized.replacingOccurrences(of: separator, with: "、")
        }

        let separators = CharacterSet(charactersIn: ",，、/&＋+|·;；")
        var seen = Set<String>()
        return normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

public enum ArtistWarmupQueueBuilder {
    public static func build(
        from tracks: [ArtistWarmupTrack],
        scope: ArtistWarmupQueueScope
    ) -> [ArtistWarmupTrack] {
        tracks
            .enumerated()
            .filter { _, track in
                track.interest != .notInterested && scope.includes(track)
            }
            .sorted { lhs, rhs in
                let leftPriority = priority(for: lhs.element.interest)
                let rightPriority = priority(for: rhs.element.interest)

                if leftPriority == rightPriority {
                    return lhs.offset < rhs.offset
                }

                return leftPriority < rightPriority
            }
            .map(\.element)
    }

    private static func priority(for interest: ArtistInterest) -> Int {
        switch interest {
        case .wanted:
            0
        case .maybe:
            1
        case .notInterested:
            2
        }
    }
}

private extension ArtistWarmupQueueScope {
    func includes(_ track: ArtistWarmupTrack) -> Bool {
        switch self {
        case .allArtists:
            true
        case let .artistOnly(artistID):
            track.artistID == artistID
        }
    }
}
