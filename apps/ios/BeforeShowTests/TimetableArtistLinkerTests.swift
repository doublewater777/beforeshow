import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class TimetableArtistLinkerTests: XCTestCase {
    func testReuseAcrossLineupsAndTimetablesSkipsSearchAndLeavesAmbiguousNamesUnbound() async throws {
        let container = try ModelContainerFactory.make(isStoredInMemoryOnly: true)
        let context = container.mainContext
        let show = try Show(name: "Previous", date: date, startTime: date.addingTimeInterval(3600))
        show.artists = [
            ArtistSlot(name: "落日飞车", avatarURL: nil, appleMusicURL: "https://music.apple.com/artist/123"),
            ArtistSlot(name: "Same Name", avatarURL: nil, appleMusicArtistID: "456"),
            ArtistSlot(name: "Same Name", avatarURL: nil, appleMusicArtistID: "789"),
            ArtistSlot(name: "冲突", avatarURL: nil, appleMusicArtistID: "111"),
            ArtistSlot(name: "Conflict", avatarURL: nil, appleMusicArtistID: "222")
        ]
        context.insert(show)
        context.insert(try TimetablePerformance(artistName: "Cached Artist", startsAt: date,
                                               endsAt: date.addingTimeInterval(3600), appleMusicArtistID: "321"))
        try context.save()
        let search = RecordingSearch()
        let linker = TimetableArtistLinker(search: search)
        try linker.loadKnownArtists(in: context)
        var draft = TimetableDraft(timeZoneIdentifier: "Asia/Taipei", days: [
            TimetableDraftDay(date: date, stages: [TimetableDraftStage(name: "Main", performances: [
                performance("落日飞车 Sunset Rollercoaster"), performance("Cached Artist"),
                performance("Same Name"), performance("Unknown"), performance("冲突 Conflict")
            ])])
        ])
        linker.reuseKnownArtists(in: &draft)
        let rows = try draft.buildTimetable().orderedDays[0].orderedStages[0].performances
        XCTAssertEqual(rows[0].appleMusicArtistID, "123")
        XCTAssertEqual(rows[1].appleMusicArtistID, "321")
        XCTAssertNil(rows[2].appleMusicArtistID)
        XCTAssertNil(rows[3].appleMusicArtistID)
        XCTAssertNil(rows[4].appleMusicArtistID)
        let cached = try await linker.candidates(for: "Cached Artist")
        let ambiguous = try await linker.candidates(for: "Same Name")
        XCTAssertEqual(cached.map(\.id), ["321"])
        XCTAssertEqual(Set(ambiguous.map(\.id)), ["456", "789"])
        let requests = await search.queries
        XCTAssertTrue(requests.isEmpty)

        _ = try await linker.candidates(for: "Remote Artist")
        let reused = try await linker.candidates(for: "Remote Artist")
        XCTAssertEqual(reused.map(\.id), ["999"])
        let remoteRequests = await search.queries
        XCTAssertEqual(remoteRequests, ["Remote Artist"])
        draft.days[0].stages[0].performances.append(performance("Remote Artist"))
        linker.reuseKnownArtists(in: &draft)
        XCTAssertNil(draft.days[0].stages[0].performances.last?.appleMusicArtistID)
        linker.rememberConnectedArtist(try XCTUnwrap(reused.first))
        linker.reuseKnownArtists(in: &draft)
        XCTAssertEqual(draft.days[0].stages[0].performances.last?.appleMusicArtistID, "999")
    }

    func testEditingTimeKeepsIdentityWhileRenamingOrDisconnectingAllowsUnboundSave() throws {
        let artist = RecognizedArtist(id: "123", canonicalName: "Artist",
                                      avatarURL: URL(string: "https://example.com/avatar.jpg"), appleMusicURL: nil)
        var draft = performance("Artist")
        draft.connectArtist(artist)
        draft = TimetableDraftPerformance(from: try draft.buildPerformance())
        draft.endsAt = date.addingTimeInterval(7200)
        XCTAssertEqual(try draft.buildPerformance().appleMusicArtistID, "123")
        draft.artistName = "Other Artist"
        let renamed = try draft.buildPerformance()
        XCTAssertEqual(renamed.artistName, "Other Artist")
        XCTAssertNil(renamed.appleMusicArtistID)
        XCTAssertNil(renamed.artistAvatarURL)
        draft.connectArtist(artist)
        draft.disconnectArtist()
        let disconnected = try draft.buildPerformance()
        XCTAssertEqual(disconnected.artistName, "Artist")
        XCTAssertNil(disconnected.appleMusicArtistID)
        XCTAssertNil(disconnected.artistAvatarURL)
    }

    func testExpandedSearchOffersAlternativesToSavedIdentityAndDeduplicatesResults() async throws {
        let search = AlternativeSearch()
        let linker = TimetableArtistLinker(search: search)
        linker.rememberConnectedArtist(RecognizedArtist(id: "123", canonicalName: "Same Name", avatarURL: nil, appleMusicURL: nil))
        let saved = try await linker.candidates(for: "Same Name")
        XCTAssertEqual(saved.map(\.id), ["123"])
        let expanded = try await linker.candidates(for: "Same Name", includingRemote: true)
        XCTAssertEqual(expanded.map(\.id), ["123", "999"])
        let again = try await linker.candidates(for: "Same Name", includingRemote: true)
        XCTAssertEqual(again.map(\.id), ["123", "999"])
        let requests = await search.queries
        XCTAssertEqual(requests, ["Same Name"])
    }

    private var date: Date { Date(timeIntervalSince1970: 1790956800) }

    private func performance(_ name: String) -> TimetableDraftPerformance {
        TimetableDraftPerformance(artistName: name, startsAt: date, endsAt: date.addingTimeInterval(3600))
    }

    private actor RecordingSearch: ArtistSearchServicing {
        private(set) var queries: [String] = []

        func searchArtists(query: String) async throws -> [RecognizedArtist] {
            queries.append(query)
            return [RecognizedArtist(id: "999", canonicalName: query, avatarURL: nil, appleMusicURL: nil)]
        }
    }

    private actor AlternativeSearch: ArtistSearchServicing {
        private(set) var queries: [String] = []

        func searchArtists(query: String) async throws -> [RecognizedArtist] {
            queries.append(query)
            return ["123", "999", "999"].map {
                RecognizedArtist(id: $0, canonicalName: query, avatarURL: nil, appleMusicURL: nil)
            }
        }
    }
}
