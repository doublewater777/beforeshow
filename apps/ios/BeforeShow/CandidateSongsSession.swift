import Foundation
import SwiftData

/// Deep module for 歌单猜想 transactions: generate/replace, add/remove/reorder, star preserve.
///
/// Deletion test: removing this module forces replace-preserving-user-songs-and-stars,
/// renumber, and generate orchestration back into the setlist sheet (and any
/// other call site). The view is a thin adapter over this interface.
@MainActor
struct CandidateSongsSession {
    let show: Show
    private let editingService: CandidateSongEditingService
    private let generationService: any CandidateSongGenerating

    init(
        show: Show,
        editingService: CandidateSongEditingService = CandidateSongEditingService(),
        generationService: (any CandidateSongGenerating)? = nil
    ) {
        self.show = show
        self.editingService = editingService
        self.generationService = generationService ?? Self.makeDefaultGenerationService()
    }

    // MARK: - Queries

    func orderedSongs(groups: [CandidateSongGroup], songs: [CandidateSong]) -> [CandidateSong] {
        let groupIDs = Set(groups.map(\.id))
        return songs
            .filter { groupIDs.contains($0.groupID) }
            .sorted { $0.order < $1.order }
    }

    func artistNames(in songs: [CandidateSong]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for song in songs {
            let name = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }

    func fallbackArtistName(showArtist: String?, songArtists: [String]) -> String {
        let artist = showArtist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !artist.isEmpty { return artist }
        if let first = songArtists.first { return first }
        return show.name
    }

    func shareHeadline(showName: String, artistFilter: String?) -> String {
        let base = showName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let artistFilter {
            return "\(base) · \(artistFilter)"
        }
        return base
    }

    /// Plain-text playlist body used by copy/share (1-based lines).
    func playlistBody(for songs: [CandidateSong]) -> String {
        songs.enumerated()
            .map { index, song in
                var line = "\(index + 1). \(song.songName) - \(song.artist)"
                if song.isMostWanted {
                    line += "（最想看）"
                }
                return line
            }
            .joined(separator: "\n")
    }

    func copyText(headline: String, scope: String, songs: [CandidateSong]) -> String {
        let body = playlistBody(for: songs)
        return "\(headline)\n歌单猜想 · \(scope)（非官方）\n\n\(body)\n\n— 开场前 BeforeShow"
    }

    // MARK: - Mutations

    /// Generate remote inputs and replace the show's catalog, preserving user-added and starred songs.
    func generateAndReplace(
        artistInterests: [ArtistInterestItem],
        existingGroups: [CandidateSongGroup],
        existingSongs: [CandidateSong],
        in context: ModelContext
    ) async throws {
        let raw = try await generationService.generate(for: show, artistInterests: artistInterests)
        let inputs = CandidateSongEditingService.enrichMissingTierAndHints(raw)
        try replaceGenerated(
            with: inputs,
            existingGroups: existingGroups,
            existingSongs: existingSongs,
            artistInterests: artistInterests,
            in: context
        )
    }

    /// One-shot repair for catalogs that look like legacy songName+artist-only generations
    /// (every generated row is mid with no short hint). Safe to call on sheet appear.
    func repairLegacyTiersAndHintsIfNeeded(
        songs: [CandidateSong],
        in context: ModelContext
    ) throws {
        let generated = songs
            .filter { !$0.isUserAdded }
            .sorted { $0.order < $1.order }
        guard generated.count >= 2 else { return }
        guard generated.allSatisfy({ $0.tier == .mid && ($0.hint?.isEmpty ?? true) }) else { return }

        let enriched = CandidateSongEditingService.enrichMissingTierAndHints(
            generated.map {
                CandidateSongInput(
                    songName: $0.songName,
                    artist: $0.artist,
                    tier: $0.tier,
                    hint: $0.hint
                )
            }
        )
        for (song, input) in zip(generated, enriched) {
            song.tier = input.tier
            song.shortHint = input.hint
        }
        try context.save()
    }

    func deduplicateSongs(
        songs: [CandidateSong],
        groups: [CandidateSongGroup],
        in context: ModelContext
    ) throws {
        let groupIDs = Set(
            groups
                .filter { $0.showID == show.id }
                .map(\.id)
        )
        let ordered = songs.filter { groupIDs.contains($0.groupID) }
        var retained: [CandidateSong] = []
        var retainedIndexByIdentity: [String: Int] = [:]

        for song in ordered {
            let identity = CandidateSongEditingService.songIdentity(for: song)
            guard let retainedIndex = retainedIndexByIdentity[identity] else {
                retainedIndexByIdentity[identity] = retained.count
                retained.append(song)
                continue
            }

            let existing = retained[retainedIndex]
            if song.isUserAdded && !existing.isUserAdded {
                song.isMostWanted = song.isMostWanted || existing.isMostWanted
                context.delete(existing)
                retained.remove(at: retainedIndex)
                retained.append(song)
                retainedIndexByIdentity = Dictionary(
                    uniqueKeysWithValues: retained.enumerated().map { index, retainedSong in
                        (CandidateSongEditingService.songIdentity(for: retainedSong), index)
                    }
                )
            } else {
                existing.isMostWanted = existing.isMostWanted || song.isMostWanted
                context.delete(song)
            }
        }

        renumber(retained)
        try context.save()
    }

    /// Replace generated catalog.
    /// Keeps `isUserAdded` songs (curated group at end) and **最想看曲目** (re-applied on match or re-inserted).
    func replaceGenerated(
        with inputs: [CandidateSongInput],
        existingGroups: [CandidateSongGroup],
        existingSongs: [CandidateSong],
        artistInterests: [ArtistInterestItem],
        in context: ModelContext
    ) throws {
        let showGroupIDs = Set(existingGroups.map(\.id))
        let oldSongs = existingSongs.filter { showGroupIDs.contains($0.groupID) }
        let oldGroups = existingGroups

        let mostWantedIdentitySet = Set(
            oldSongs
                .filter(\.isMostWanted)
                .map { CandidateSongEditingService.songIdentity(for: $0) }
        )

        let preservedUserSongs = oldSongs
            .filter(\.isUserAdded)
            .sorted { $0.order < $1.order }

        let grouped = editingService.groupedInputsByArtist(
            inputs: CandidateSongEditingService.deduplicatedInputs(inputs),
            artistInterests: artistInterests
        )

        var created: [CandidateSong] = []
        var createdGroups: [CandidateSongGroup] = []
        var coveredMostWantedIdentities = Set<String>()

        for entry in grouped {
            let group = try CandidateSongGroup(
                showID: show.id,
                artistInterestID: entry.artistInterestID,
                artistName: entry.artistName,
                uncertaintyNote: Self.defaultUncertaintyNote
            )
            context.insert(group)
            createdGroups.append(group)
            for song in try editingService.makeSongs(groupID: group.id, inputs: entry.songs) {
                let identity = CandidateSongEditingService.songIdentity(for: song)
                if mostWantedIdentitySet.contains(identity) {
                    song.isMostWanted = true
                    coveredMostWantedIdentities.insert(identity)
                }
                context.insert(song)
                created.append(song)
            }
        }

        // Starred generated songs not in the new list: re-insert with prior confidence.
        let missingStarred = oldSongs
            .filter { song in
                song.isMostWanted
                    && !song.isUserAdded
                    && !coveredMostWantedIdentities.contains(CandidateSongEditingService.songIdentity(for: song))
            }
            .sorted { $0.order < $1.order }

        if !missingStarred.isEmpty {
            let reinsertInputs = missingStarred.map {
                CandidateSongInput(
                    songName: $0.songName,
                    artist: $0.artist,
                    tier: $0.tier,
                    hint: $0.hint
                )
            }
            let reinsertGrouped = editingService.groupedInputsByArtist(
                inputs: CandidateSongEditingService.deduplicatedInputs(reinsertInputs),
                artistInterests: artistInterests
            )
            for entry in reinsertGrouped {
                let group = try CandidateSongGroup(
                    showID: show.id,
                    artistInterestID: entry.artistInterestID,
                    artistName: entry.artistName,
                    uncertaintyNote: Self.defaultUncertaintyNote
                )
                context.insert(group)
                createdGroups.append(group)
                for song in try editingService.makeSongs(groupID: group.id, inputs: entry.songs) {
                    song.isMostWanted = true
                    context.insert(song)
                    created.append(song)
                    coveredMostWantedIdentities.insert(CandidateSongEditingService.songIdentity(for: song))
                }
            }
        }

        if !preservedUserSongs.isEmpty {
            let group = try CandidateSongGroup(
                showID: show.id,
                uncertaintyNote: Self.defaultUncertaintyNote,
                isUserCurated: true
            )
            context.insert(group)
            createdGroups.append(group)
            for old in preservedUserSongs {
                let song = try CandidateSong(
                    groupID: group.id,
                    songName: old.songName,
                    artist: old.artist,
                    order: created.count,
                    isUserAdded: true,
                    isMostWanted: old.isMostWanted,
                    tier: old.tier,
                    hint: old.hint
                )
                context.insert(song)
                created.append(song)
            }
        }

        for song in oldSongs {
            context.delete(song)
        }
        for group in oldGroups {
            context.delete(group)
        }

        try deduplicateSongs(songs: created, groups: createdGroups, in: context)
    }

    func addUserSong(
        name: String,
        artist: String,
        groups: [CandidateSongGroup],
        currentSongs: [CandidateSong],
        in context: ModelContext
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedArtist.isEmpty else { return }
        let identity = CandidateSongEditingService.songIdentity(
            songName: trimmedName,
            artist: trimmedArtist
        )
        guard !currentSongs.contains(where: {
            CandidateSongEditingService.songIdentity(for: $0) == identity
        }) else {
            throw CandidateSongValidationError.duplicateSong
        }

        let group = try userCuratedGroup(in: groups, context: context)
        let song = try CandidateSong(
            groupID: group.id,
            songName: trimmedName,
            artist: trimmedArtist,
            order: currentSongs.count,
            isUserAdded: true
        )
        context.insert(song)
        try context.save()
        renumber(currentSongs + [song])
        try context.save()
    }

    func remove(
        _ song: CandidateSong,
        previouslyOrdered: [CandidateSong],
        in context: ModelContext
    ) throws {
        context.delete(song)
        try context.save()
        let remaining = previouslyOrdered.filter { $0.id != song.id }
        renumber(remaining)
        try context.save()
    }

    func move(
        previouslyOrdered: [CandidateSong],
        from source: IndexSet,
        to destination: Int,
        in context: ModelContext
    ) throws {
        var songs = previouslyOrdered
        songs.move(fromOffsets: source, toOffset: destination)
        renumber(songs)
        try context.save()
    }

    /// Move one song up by one position (no-op at top).
    func moveUp(
        _ song: CandidateSong,
        previouslyOrdered: [CandidateSong],
        in context: ModelContext
    ) throws {
        guard let index = previouslyOrdered.firstIndex(where: { $0.id == song.id }), index > 0 else { return }
        var songs = previouslyOrdered
        songs.swapAt(index, index - 1)
        renumber(songs)
        try context.save()
    }

    /// Move one song down by one position (no-op at bottom).
    func moveDown(
        _ song: CandidateSong,
        previouslyOrdered: [CandidateSong],
        in context: ModelContext
    ) throws {
        guard let index = previouslyOrdered.firstIndex(where: { $0.id == song.id }),
              index < previouslyOrdered.count - 1 else { return }
        var songs = previouslyOrdered
        songs.swapAt(index, index + 1)
        renumber(songs)
        try context.save()
    }

    func setMostWanted(_ song: CandidateSong, isMostWanted: Bool, in context: ModelContext) throws {
        song.isMostWanted = isMostWanted
        try context.save()
    }

    func setStarred(_ song: CandidateSong, isStarred: Bool, in context: ModelContext) throws {
        try setMostWanted(song, isMostWanted: isStarred, in: context)
    }

    func renumber(_ songs: [CandidateSong]) {
        for (index, song) in songs.enumerated() {
            song.order = index
        }
    }

    // MARK: - Festival lineup seed

    /// Split `show.artist` into lineup names (、，,/| 等).
    static func parseLineupNames(from raw: String?) -> [String] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Damai/ShowStart join with ", "; OCR may use 、/换行/·/& 等.
        let normalized = trimmed
            .replacingOccurrences(of: "\r\n", with: "、")
            .replacingOccurrences(of: "\n", with: "、")
            .replacingOccurrences(of: "\r", with: "、")
            .replacingOccurrences(of: " / ", with: "、")
            .replacingOccurrences(of: " /", with: "、")
            .replacingOccurrences(of: "/ ", with: "、")
            .replacingOccurrences(of: " · ", with: "、")
            .replacingOccurrences(of: "·", with: "、")
            .replacingOccurrences(of: "｜", with: "、")
            .replacingOccurrences(of: "|", with: "、")
            .replacingOccurrences(of: "；", with: "、")
            .replacingOccurrences(of: ";", with: "、")
            .replacingOccurrences(of: "，", with: "、")
            .replacingOccurrences(of: ",", with: "、")
            .replacingOccurrences(of: "／", with: "、")
            .replacingOccurrences(of: "/", with: "、")
            .replacingOccurrences(of: "＆", with: "、")
            .replacingOccurrences(of: " & ", with: "、")
            .replacingOccurrences(of: "&", with: "、")
            .replacingOccurrences(of: " 和 ", with: "、")
            .replacingOccurrences(of: "、、", with: "、")

        let parts = normalized
            .components(separatedBy: "、")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Dedupe preserving order
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }
    }

    /// If festival has no 艺人关注项 yet, create them from `show.artist` lineup text.
    /// Returns the interests for this show after seeding (may still be empty).
    @discardableResult
    func seedFestivalInterestsIfNeeded(
        existing: [ArtistInterestItem],
        in context: ModelContext
    ) throws -> [ArtistInterestItem] {
        guard show.type == .musicFestival else { return existing }
        let forShow = existing.filter { $0.showID == show.id }
        if !forShow.isEmpty { return forShow.sorted { $0.order < $1.order } }

        let names = Self.parseLineupNames(from: show.artist)
        guard !names.isEmpty else { return [] }

        var created: [ArtistInterestItem] = []
        for (index, name) in names.enumerated() {
            let item = try ArtistInterestItem(
                showID: show.id,
                artistName: name,
                status: .wantToSee,
                order: index
            )
            context.insert(item)
            created.append(item)
        }
        try context.save()
        return created
    }

    /// Append one artist interest; returns the new item (or existing match).
    func addFestivalArtist(
        name: String,
        existing: [ArtistInterestItem],
        in context: ModelContext
    ) throws -> ArtistInterestItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CandidateSongValidationError.emptyArtist
        }
        if let found = existing.first(where: {
            $0.showID == show.id && $0.artistName == trimmed
        }) {
            return found
        }
        let order = (existing.map(\.order).max() ?? -1) + 1
        let item = try ArtistInterestItem(
            showID: show.id,
            artistName: trimmed,
            status: .wantToSee,
            order: order
        )
        context.insert(item)
        try context.save()
        return item
    }

    // MARK: - Internals

    private func userCuratedGroup(
        in groups: [CandidateSongGroup],
        context: ModelContext
    ) throws -> CandidateSongGroup {
        if let group = groups.first(where: { $0.isUserCurated }) {
            return group
        }
        let group = try CandidateSongGroup(
            showID: show.id,
            uncertaintyNote: Self.defaultUncertaintyNote,
            isUserCurated: true
        )
        context.insert(group)
        return group
    }

    private static let defaultUncertaintyNote = "歌单猜想来自公开信息推测，不代表官方歌单。"

    static func makeDefaultGenerationService() -> RemoteCandidateSongGenerationService {
        RemoteCandidateSongGenerationService(client: .production())
    }
}
