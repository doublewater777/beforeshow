import Foundation
import SwiftData

/// Deep module for 候选曲目 transactions: generate/replace, add/remove/reorder.
///
/// Deletion test: removing this module forces replace-preserving-user-songs,
/// renumber, and generate orchestration back into CandidateSongsView (and any
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
            .map { "\($0.offset + 1). \($0.element.songName) - \($0.element.artist)" }
            .joined(separator: "\n")
    }

    func copyText(headline: String, scope: String, songs: [CandidateSong]) -> String {
        let body = playlistBody(for: songs)
        return "\(headline)\n猜歌单 · \(scope)（非官方）\n\n\(body)\n\n— 开场前 BeforeShow"
    }

    func shareText(headline: String, songs: [CandidateSong]) -> String {
        let body = playlistBody(for: songs)
        return "\(headline)\n猜歌单（非官方）\n\n\(body)\n\n— 开场前 BeforeShow"
    }

    // MARK: - Mutations

    /// Generate remote inputs and replace the show's catalog, preserving user-added songs.
    func generateAndReplace(
        artistInterests: [ArtistInterestItem],
        existingGroups: [CandidateSongGroup],
        existingSongs: [CandidateSong],
        in context: ModelContext
    ) async throws {
        let inputs = try await generationService.generate(for: show, artistInterests: artistInterests)
        try replaceGenerated(
            with: inputs,
            existingGroups: existingGroups,
            existingSongs: existingSongs,
            artistInterests: artistInterests,
            in: context
        )
    }

    /// Replace generated catalog; keep `isUserAdded` songs in a curated group at the end.
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

        let preservedInputs = oldSongs
            .filter(\.isUserAdded)
            .sorted { $0.order < $1.order }
            .map { CandidateSongInput(songName: $0.songName, artist: $0.artist) }

        let grouped = editingService.groupedInputsByArtist(
            inputs: inputs,
            artistInterests: artistInterests
        )

        var created: [CandidateSong] = []

        for entry in grouped {
            let group = try CandidateSongGroup(
                showID: show.id,
                artistInterestID: entry.artistInterestID,
                artistName: entry.artistName,
                uncertaintyNote: Self.defaultUncertaintyNote
            )
            context.insert(group)
            for song in try editingService.makeSongs(groupID: group.id, inputs: entry.songs) {
                context.insert(song)
                created.append(song)
            }
        }

        if !preservedInputs.isEmpty {
            let group = try CandidateSongGroup(
                showID: show.id,
                uncertaintyNote: Self.defaultUncertaintyNote,
                isUserCurated: true
            )
            context.insert(group)
            for song in try editingService.makeSongs(groupID: group.id, inputs: preservedInputs) {
                song.isUserAdded = true
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

        renumber(created)
        try context.save()
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

    func renumber(_ songs: [CandidateSong]) {
        for (index, song) in songs.enumerated() {
            song.order = index
        }
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

    private static let defaultUncertaintyNote = "候选曲目来自公开信息推测，不代表官方歌单。"

    static func makeDefaultGenerationService() -> RemoteCandidateSongGenerationService {
        RemoteCandidateSongGenerationService(client: .production())
    }
}
