import Foundation
import MusicKit
import Observation

// MARK: - 统一艺人头像
// 同一已确认 Apple Music Artist ID 在所有界面使用同一张艺人头像（docs/specs/artist-avatar-consistency.md）。
// 只有 Apple Music 艺人照片会被缓存为该 ID 的头像；记录里旧的 URL 来源不明，只在本条记录内兜底，
// 不会提升、也不会跨现场传播。

enum ArtistOfficialArtwork: Equatable {
    case photo(URL)
    /// Apple Music 确认该艺人没有艺人照片。
    case none
    /// 没有可用的 MusicKit 访问；不代表没有照片。
    case accessUnavailable
}

@MainActor
protocol ArtistOfficialArtworkLookup {
    func officialArtwork(artistID: String) async throws -> ArtistOfficialArtwork
}

@MainActor
@Observable
final class ArtistAvatarResolver {
    static let shared = ArtistAvatarResolver(lookup: MusicKitArtistArtworkLookup())

    static let revalidationInterval: TimeInterval = 7 * 86_400
    static let accessRetryInterval: TimeInterval = 3_600

    static func backoff(afterFailures failures: Int) -> TimeInterval {
        min(86_400, 3_600 * pow(2, Double(max(0, failures - 1))))
    }

    struct Entry: Codable, Equatable {
        var officialURL: URL?
        var checkedAt: Date?
        var failedAt: Date?
        var failureCount = 0
    }

    /// Bumps whenever a displayed avatar can change; widget / Live Activity sync keys on it.
    private(set) var revision = 0
    private var entries: [String: Entry]

    @ObservationIgnored private let lookup: any ArtistOfficialArtworkLookup
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let autoRefresh: Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var generations: [String: Int] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var accessRetryAt: [String: Date] = [:]

    init(
        lookup: any ArtistOfficialArtworkLookup,
        cacheURL: URL? = ArtistAvatarResolver.defaultCacheURL,
        autoRefresh: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.lookup = lookup
        self.cacheURL = cacheURL
        self.autoRefresh = autoRefresh
        self.now = now
        entries = cacheURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// 艺人头像的唯一展示入口。`stored` 是这条记录自己的旧 URL，只在该 ID 尚无结论时兜底。
    func displayURL(artistID: String?, stored: String?) -> URL? {
        let storedURL = Self.normalized(stored).flatMap(URL.init(string:))
        guard let id = Self.normalized(artistID) else { return storedURL }
        if autoRefresh {
            Task { await self.refreshIfDue(artistID: id) }
        }
        guard let entry = entries[id], entry.checkedAt != nil else { return storedURL }
        return entry.officialURL
    }

    /// 搜索 / 匹配得到的 Apple Music 艺人照片直接成为该 ID 的头像；其他来源不记录。
    func record(_ artist: RecognizedArtist) {
        guard artist.isOfficialArtistPhoto, let url = artist.avatarURL,
              let id = Self.normalized(artist.id) else { return }
        generations[id, default: 0] += 1
        commit(id, Entry(officialURL: url, checkedAt: now()))
    }

    func refreshIfDue(artistID: String) async {
        guard let id = Self.normalized(artistID), !inFlight.contains(id), isDue(id) else { return }
        await refresh(artistID: id)
    }

    func refresh(artistID: String) async {
        guard let id = Self.normalized(artistID) else { return }
        generations[id, default: 0] += 1
        let generation = generations[id]!
        inFlight.insert(id)
        defer { if generations[id] == generation { inFlight.remove(id) } }

        let previous = entries[id] ?? Entry()
        let result: Result<ArtistOfficialArtwork, Error>
        do { result = .success(try await lookup.officialArtwork(artistID: id)) } catch { result = .failure(error) }
        // A newer request (or a recorded search result) owns this ID now.
        guard generations[id] == generation else { return }

        switch result {
        case .success(.photo(let url)):
            commit(id, Entry(officialURL: url, checkedAt: now()))
        case .success(.none):
            commit(id, Entry(officialURL: nil, checkedAt: now()))
        case .success(.accessUnavailable):
            accessRetryAt[id] = now().addingTimeInterval(Self.accessRetryInterval)
        case .failure:
            var failed = previous
            failed.failedAt = now()
            failed.failureCount += 1
            commit(id, failed, bumpsDisplay: false)
        }
    }

    private func isDue(_ id: String) -> Bool {
        let current = now()
        if let retry = accessRetryAt[id], current < retry { return false }
        guard let entry = entries[id] else { return true }
        if let failedAt = entry.failedAt, entry.failureCount > 0,
           current.timeIntervalSince(failedAt) < Self.backoff(afterFailures: entry.failureCount) {
            return false
        }
        guard let checkedAt = entry.checkedAt else { return true }
        return current.timeIntervalSince(checkedAt) > Self.revalidationInterval
    }

    private func commit(_ id: String, _ entry: Entry, bumpsDisplay: Bool = true) {
        let changed = entries[id]?.officialURL != entry.officialURL || entries[id]?.checkedAt == nil
        entries[id] = entry
        if bumpsDisplay && changed { revision &+= 1 }
        persist()
    }

    private func persist() {
        guard let cacheURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private static func normalized(_ id: String?) -> String? {
        guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    nonisolated static var defaultCacheURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("artist-avatars.json")
    }
}

/// 只沿用现有授权状态，不为头像单独请求 MusicKit 授权。
@MainActor
struct MusicKitArtistArtworkLookup: ArtistOfficialArtworkLookup {
    func officialArtwork(artistID: String) async throws -> ArtistOfficialArtwork {
        guard MusicAuthorization.currentStatus == .authorized else { return .accessUnavailable }
        let request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(artistID))
        guard let artist = try await request.response().items.first else { return .none }
        return artist.artwork?.url(width: 240, height: 240).map(ArtistOfficialArtwork.photo) ?? .none
    }
}

// MARK: - 模型入口

extension ArtistAvatarResolver {
    func displayURL(for performance: TimetablePerformance) -> URL? {
        displayURL(artistID: performance.appleMusicArtistID, stored: performance.artistAvatarURL)
    }

    func displayURL(for slot: ArtistSlot) -> URL? {
        displayURL(artistID: slot.appleMusicArtistID, stored: slot.avatarURL)
    }

    /// 时刻表外的展示（现场模式快照）：已关联的演出用统一头像，未关联沿用按艺名匹配的结果。
    func displayURL(performanceID: UUID, in timetable: Timetable, unlinked: @autoclosure () -> URL?) -> URL? {
        guard let performance = timetable.orderedDays.lazy.flatMap(\.performances).first(where: { $0.id == performanceID }),
              performance.appleMusicArtistID != nil else { return unlinked() }
        return displayURL(for: performance)
    }
}
