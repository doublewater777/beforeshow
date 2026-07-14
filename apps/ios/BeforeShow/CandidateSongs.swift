import Foundation
import SwiftData

enum CandidateSongValidationError: Error, Equatable {
    case emptySongName
    case emptyArtist
    case emptyUncertaintyNote
    case replacementNeedsConfirmation
    case invalidGenerationPayload
}

enum CandidateSongGenerationError: Error, Equatable {
    case networkFailure
    case invalidResponse
    case backendRejected(String)
}

@Model
final class CandidateSong {
    var id: UUID
    var groupID: UUID
    var songName: String
    var artist: String
    var order: Int
    var isUserAdded: Bool

    init(id: UUID = UUID(), groupID: UUID, songName: String, artist: String, order: Int, isUserAdded: Bool = false) throws {
        let trimmedSongName = songName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSongName.isEmpty else {
            throw CandidateSongValidationError.emptySongName
        }
        guard !trimmedArtist.isEmpty else {
            throw CandidateSongValidationError.emptyArtist
        }

        self.id = id
        self.groupID = groupID
        self.songName = trimmedSongName
        self.artist = trimmedArtist
        self.order = order
        self.isUserAdded = isUserAdded
    }
}

@Model
final class CandidateSongGroup {
    var id: UUID
    var showID: UUID
    var artistInterestID: UUID?
    var artistName: String?
    var uncertaintyNote: String
    var isUserCurated: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        showID: UUID,
        artistInterestID: UUID? = nil,
        artistName: String? = nil,
        uncertaintyNote: String,
        isUserCurated: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let trimmedNote = uncertaintyNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else {
            throw CandidateSongValidationError.emptyUncertaintyNote
        }

        self.id = id
        self.showID = showID
        self.artistInterestID = artistInterestID
        self.artistName = artistName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.uncertaintyNote = trimmedNote
        self.isUserCurated = isUserCurated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ArtistInterestStatus: String, CaseIterable, Codable, Equatable {
    case wantToSee
    case undecided
    case notInterested
}

@Model
final class ArtistInterestItem {
    var id: UUID
    var showID: UUID
    var artistName: String
    var order: Int

    private var statusRawValue: String

    var status: ArtistInterestStatus {
        get { ArtistInterestStatus(rawValue: statusRawValue) ?? .undecided }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        showID: UUID,
        artistName: String,
        status: ArtistInterestStatus,
        order: Int
    ) throws {
        let trimmedArtistName = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtistName.isEmpty else {
            throw CandidateSongValidationError.emptyArtist
        }

        self.id = id
        self.showID = showID
        self.artistName = trimmedArtistName
        self.statusRawValue = status.rawValue
        self.order = order
    }
}

struct CandidateSongInput: Equatable {
    let songName: String
    let artist: String
}

struct CandidateSongSnapshot: Equatable {
    let songName: String
    let artist: String
    let order: Int
}

struct CandidateSongGenerationResponse: Decodable, Equatable {
    let items: [CandidateSongInput]

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case items
    }

    private enum ItemCodingKeys: String, CodingKey, CaseIterable {
        case songName
        case artist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try Self.rejectExtraKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.stringValue))
        )

        let type = try container.decode(String.self, forKey: .type)
        guard type == "candidateSongs" else {
            throw CandidateSongValidationError.invalidGenerationPayload
        }

        var itemsContainer = try container.nestedUnkeyedContainer(forKey: .items)
        var decodedItems: [CandidateSongInput] = []

        while !itemsContainer.isAtEnd {
            let itemDecoder = try itemsContainer.superDecoder()
            let itemContainer = try itemDecoder.container(keyedBy: ItemCodingKeys.self)
            try Self.rejectExtraKeys(
                in: itemDecoder,
                allowed: Set(ItemCodingKeys.allCases.map(\.stringValue))
            )

            let songName = try itemContainer.decode(String.self, forKey: .songName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = try itemContainer.decode(String.self, forKey: .artist)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !songName.isEmpty else {
                throw CandidateSongValidationError.emptySongName
            }
            guard !artist.isEmpty else {
                throw CandidateSongValidationError.emptyArtist
            }

            decodedItems.append(CandidateSongInput(songName: songName, artist: artist))
        }

        guard !decodedItems.isEmpty else {
            throw CandidateSongValidationError.invalidGenerationPayload
        }

        self.items = decodedItems
    }

    private static func rejectExtraKeys(
        in decoder: Decoder,
        allowed: Set<String>
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let unknownKeys = container.allKeys
            .map(\.stringValue)
            .filter { !allowed.contains($0) }

        if !unknownKeys.isEmpty {
            throw CandidateSongValidationError.invalidGenerationPayload
        }
    }
}

struct CandidateSongGenerationRequest {
    let showID: UUID
    let showName: String
    let showType: ShowType
    let artists: [String]
    let excludedArtists: [String]

    static func requests(
        for show: Show,
        artistInterests: [ArtistInterestItem]
    ) -> [CandidateSongGenerationRequest] {
        let excluded = excludedArtists(from: artistInterests)

        if show.type == .musicFestival {
            let includedArtists = artistInterests
                .filter { $0.status != .notInterested }
                .sorted { first, second in
                    if first.status == second.status {
                        return first.order < second.order
                    }
                    return first.status.priority < second.status.priority
                }
                .map(\.artistName)

            guard !includedArtists.isEmpty else {
                return []
            }

            return [
                CandidateSongGenerationRequest(
                    showID: show.id,
                    showName: show.name,
                    showType: show.type,
                    artists: includedArtists,
                    excludedArtists: excluded
                )
            ]
        }

        return [
            CandidateSongGenerationRequest(
                showID: show.id,
                showName: show.name,
                showType: show.type,
                artists: showArtists(show),
                excludedArtists: excluded
            )
        ]
    }

    private static func showArtists(_ show: Show) -> [String] {
        let artist = show.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? [] : [artist]
    }

    private static func excludedArtists(from artistInterests: [ArtistInterestItem]) -> [String] {
        artistInterests
            .filter { $0.status == .notInterested }
            .sorted { $0.order < $1.order }
            .map(\.artistName)
    }
}

@MainActor
protocol CandidateSongGenerating: Sendable {
    func generate(for show: Show, artistInterests: [ArtistInterestItem]) async throws -> [CandidateSongInput]
}

struct RemoteCandidateSongGenerationService: CandidateSongGenerating {
    var client: BeforeShowCloudClient
    var calendar: Calendar

    init(
        client: BeforeShowCloudClient,
        calendar: Calendar = .current
    ) {
        self.client = client
        self.calendar = calendar
    }

    func generate(for show: Show, artistInterests: [ArtistInterestItem] = []) async throws -> [CandidateSongInput] {
        let requests = CandidateSongGenerationRequest.requests(for: show, artistInterests: artistInterests)
        guard let generationRequest = requests.first else {
            throw CandidateSongGenerationError.invalidResponse
        }

        let data: Data
        do {
            data = try await client.postJSON(
                path: "generate",
                body: RequestBody(
                    appInstanceId: client.credentials.appInstanceId,
                    appSignature: client.credentials.appSignature,
                    type: "candidateSongs",
                    requestId: UUID().uuidString,
                    locale: "zh-CN",
                    show: ShowPayload(
                        name: generationRequest.showName,
                        date: Self.dateFormatter.string(from: show.effectiveDate),
                        city: trimmedOptional(show.city),
                        venueName: trimmedOptional(show.venueName),
                        type: generationRequest.showType.rawValue,
                        artists: generationRequest.artists.isEmpty ? nil : generationRequest.artists
                    ),
                    limits: Limits(maxSongs: 12)
                )
            )
        } catch {
            throw CandidateSongGenerationError.networkFailure
        }

        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: data)
        guard decoded.ok else {
            throw CandidateSongGenerationError.backendRejected(decoded.error?.message ?? "生成失败")
        }

        guard let generation = decoded.response else {
            throw CandidateSongGenerationError.invalidResponse
        }

        return generation.items
    }

    private func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct RequestBody: Encodable {
        let appInstanceId: String
        let appSignature: String
        let type: String
        let requestId: String
        let locale: String
        let show: ShowPayload
        let limits: Limits
    }

    private struct ShowPayload: Encodable {
        let name: String
        let date: String
        let city: String?
        let venueName: String?
        let type: String
        let artists: [String]?
    }

    private struct Limits: Encodable {
        let maxSongs: Int
    }

    private struct GenerationResponse: Decodable {
        let ok: Bool
        let response: CandidateSongGenerationResponse?
        let error: ErrorInfo?
    }

    private struct ErrorInfo: Decodable {
        let code: String?
        let message: String
    }
}

private extension ArtistInterestStatus {
    var priority: Int {
        switch self {
        case .wantToSee:
            return 0
        case .undecided:
            return 1
        case .notInterested:
            return 2
        }
    }
}

struct CandidateSongEditingService {
    func snapshots(for songs: [CandidateSong]) -> [CandidateSongSnapshot] {
        songs
            .sorted { $0.order < $1.order }
            .map {
                CandidateSongSnapshot(
                    songName: $0.songName,
                    artist: $0.artist,
                    order: $0.order
                )
            }
    }

    func makeSongs(groupID: UUID, inputs: [CandidateSongInput]) throws -> [CandidateSong] {
        try inputs.enumerated().map { index, input in
            try CandidateSong(
                groupID: groupID,
                songName: input.songName,
                artist: input.artist,
                order: index
            )
        }
    }

    /// Groups generated inputs by their `artist`, preserving the order in which each artist
    /// first appears in `inputs`. Matches `artistInterestID` by artist name so festival groups
    /// stay linked to the artist interest that produced them.
    func groupedInputsByArtist(
        inputs: [CandidateSongInput],
        artistInterests: [ArtistInterestItem]
    ) -> [(artistName: String, artistInterestID: UUID?, songs: [CandidateSongInput])] {
        let interestIDByName = Dictionary(
            uniqueKeysWithValues: artistInterests.map { ($0.artistName, $0.id) }
        )
        let grouped = Dictionary(grouping: inputs, by: \.artist)

        var seenArtists = Set<String>()
        var orderedArtists: [String] = []
        for input in inputs where !seenArtists.contains(input.artist) {
            seenArtists.insert(input.artist)
            orderedArtists.append(input.artist)
        }

        return orderedArtists.map { artist in
            (
                artistName: artist,
                artistInterestID: interestIDByName[artist],
                songs: grouped[artist] ?? []
            )
        }
    }

    func addSong(to songs: [CandidateSong], groupID: UUID, songName: String, artist: String) throws -> CandidateSong {
        try CandidateSong(
            groupID: groupID,
            songName: songName,
            artist: artist,
            order: songs.count
        )
    }

    func remove(songID: UUID, from songs: [CandidateSong]) -> [CandidateSong] {
        let ordered = songs.sorted { $0.order < $1.order }
        return renumber(ordered.filter { $0.id != songID })
    }

    func moveSong(in songs: [CandidateSong], from sourceIndex: Int, to destinationIndex: Int) -> [CandidateSong] {
        var ordered = songs.sorted { $0.order < $1.order }
        guard ordered.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex <= ordered.count else {
            return ordered
        }

        let moving = ordered.remove(at: sourceIndex)
        ordered.insert(moving, at: min(destinationIndex, ordered.count))
        return renumber(ordered)
    }

    func plainText(for songs: [CandidateSong]) -> String {
        songs
            .sorted { $0.order < $1.order }
            .map { "\($0.order + 1). \($0.songName) - \($0.artist)" }
            .joined(separator: "\n")
    }

    func replacementPlan(
        existingSongs: [CandidateSong],
        generatedInputs: [CandidateSongInput],
        userConfirmedReplacement: Bool
    ) throws -> [CandidateSongInput] {
        if !existingSongs.isEmpty && !userConfirmedReplacement {
            throw CandidateSongValidationError.replacementNeedsConfirmation
        }

        return generatedInputs
    }

    private func renumber(_ songs: [CandidateSong]) -> [CandidateSong] {
        for (index, song) in songs.enumerated() {
            song.order = index
        }
        return songs
    }
}

