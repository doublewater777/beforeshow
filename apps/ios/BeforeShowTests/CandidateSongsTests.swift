import SwiftData
import XCTest
@testable import BeforeShow

final class CandidateSongsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    @MainActor
    func testCandidateSongsStoreOnlySongArtistOrderAndGroupUncertainty() throws {
        let show = try Show(name: "草莓音乐节", date: Date(), startTime: Date(), type: .musicFestival)
        let group = try CandidateSongGroup(
            showID: show.id,
            uncertaintyNote: "候选曲目来自公开信息推测，不代表官方歌单。"
        )
        let song = try CandidateSong(
            groupID: group.id,
            songName: "夜空中最亮的星",
            artist: "逃跑计划",
            order: 0
        )

        let container = try ModelContainer(
            for: Show.self, CandidateSongGroup.self, CandidateSong.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(show)
        container.mainContext.insert(group)
        container.mainContext.insert(song)
        try container.mainContext.save()

        let songs = try container.mainContext.fetch(FetchDescriptor<CandidateSong>())
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].songName, "夜空中最亮的星")
        XCTAssertEqual(songs[0].artist, "逃跑计划")
        XCTAssertEqual(songs[0].order, 0)

        let groups = try container.mainContext.fetch(FetchDescriptor<CandidateSongGroup>())
        XCTAssertEqual(groups[0].uncertaintyNote, "候选曲目来自公开信息推测，不代表官方歌单。")
    }

    @MainActor
    func testCandidateSongAndGroupDefaultUserFlagsAreFalse() throws {
        let song = try CandidateSong(groupID: UUID(), songName: "歌", artist: "艺人", order: 0)
        let group = try CandidateSongGroup(showID: UUID(), uncertaintyNote: "仅供参考")

        XCTAssertFalse(song.isUserAdded)
        XCTAssertFalse(group.isUserCurated)
    }

    @MainActor
    func testMakeSongsProducesGeneratedSongsNotFlaggedAsUserAdded() throws {
        let service = CandidateSongEditingService()
        let groupID = UUID()
        let songs = try service.makeSongs(
            groupID: groupID,
            inputs: [
                CandidateSongInput(songName: "S1", artist: "A"),
                CandidateSongInput(songName: "S2", artist: "A")
            ]
        )

        XCTAssertEqual(songs.count, 2)
        XCTAssertTrue(songs.allSatisfy { !$0.isUserAdded })
    }

    func testGenerationResponseRejectsLyricsConfidenceReasonsAndPlatformMetadata() {
        let payloads = [
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","lyrics":"x"}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","confidence":0.9}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","recommendationReason":"hot"}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","platformId":"123"}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","coverUrl":"https://example.com/a.jpg"}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","audioUrl":"https://example.com/a.mp3"}]}"#
        ]

        for payload in payloads {
            XCTAssertThrowsError(
                try JSONDecoder().decode(CandidateSongGenerationResponse.self, from: Data(payload.utf8))
            )
        }
    }

    func testGenerationResponseAcceptsOrderedSongNameAndArtistOnly() throws {
        let payload = """
        {
          "type": "candidateSongs",
          "items": [
            { "songName": "Song A", "artist": "Artist A" },
            { "songName": "Song B", "artist": "Artist B" }
          ]
        }
        """

        let response = try JSONDecoder().decode(
            CandidateSongGenerationResponse.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(
            response.items,
            [
                CandidateSongInput(songName: "Song A", artist: "Artist A"),
                CandidateSongInput(songName: "Song B", artist: "Artist B")
            ]
        )
    }

    func testManualEditingCanAddRemoveReorderAndCopyPlainText() throws {
        let service = CandidateSongEditingService()
        let groupID = UUID()
        let first = try CandidateSong(groupID: groupID, songName: "First", artist: "Artist", order: 0)
        let second = try CandidateSong(groupID: groupID, songName: "Second", artist: "Artist", order: 1)
        let added = try service.addSong(to: [first, second], groupID: groupID, songName: "Third", artist: "Artist")

        XCTAssertEqual(added.order, 2)

        let moved = service.moveSong(in: [first, second, added], from: 2, to: 0)
        XCTAssertEqual(service.snapshots(for: moved).map(\.songName), ["Third", "First", "Second"])
        XCTAssertEqual(service.snapshots(for: moved).map(\.order), [0, 1, 2])

        let removed = service.remove(songID: first.id, from: moved)
        XCTAssertEqual(service.snapshots(for: removed).map(\.songName), ["Third", "Second"])
        XCTAssertEqual(service.plainText(for: removed), "1. Third - Artist\n2. Second - Artist")
    }

    func testRegenerationRequiresReplacementConfirmationWhenSongsExist() throws {
        let service = CandidateSongEditingService()
        let existing = [
            try CandidateSong(groupID: UUID(), songName: "Old", artist: "Artist", order: 0)
        ]
        let generated = [CandidateSongInput(songName: "New", artist: "Artist")]

        XCTAssertThrowsError(
            try service.replacementPlan(
                existingSongs: existing,
                generatedInputs: generated,
                userConfirmedReplacement: false
            )
        ) { error in
            XCTAssertEqual(error as? CandidateSongValidationError, .replacementNeedsConfirmation)
        }

        XCTAssertEqual(
            try service.replacementPlan(
                existingSongs: existing,
                generatedInputs: generated,
                userConfirmedReplacement: true
            ),
            generated
        )
    }

    func testFestivalSingleRequestIncludesWantToSeeAndUndecidedExcludesNotInterested() throws {
        let show = try Show(name: "音乐节", date: Date(), startTime: Date(), type: .musicFestival)
        let want = try ArtistInterestItem(showID: show.id, artistName: "想看艺人", status: .wantToSee, order: 1)
        let undecided = try ArtistInterestItem(showID: show.id, artistName: "待定艺人", status: .undecided, order: 0)
        let no = try ArtistInterestItem(showID: show.id, artistName: "不看艺人", status: .notInterested, order: 2)

        let requests = CandidateSongGenerationRequest.requests(
            for: show,
            artistInterests: [undecided, no, want]
        )

        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.artists, ["想看艺人", "待定艺人"])
        XCTAssertEqual(request.excludedArtists, ["不看艺人"])
    }

    func testFestivalReturnsNoRequestWhenNoInterestedArtist() throws {
        let show = try Show(name: "音乐节", date: Date(), startTime: Date(), type: .musicFestival)
        let no = try ArtistInterestItem(showID: show.id, artistName: "不看艺人", status: .notInterested, order: 0)

        let requests = CandidateSongGenerationRequest.requests(
            for: show,
            artistInterests: [no]
        )

        XCTAssertTrue(requests.isEmpty)
    }

    func testNonFestivalRequestUsesShowArtist() throws {
        let show = try Show(
            name: "专场",
            date: Date(),
            startTime: Date(),
            artist: "主艺人",
            type: .concert
        )

        let requests = CandidateSongGenerationRequest.requests(
            for: show,
            artistInterests: []
        )

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.artists, ["主艺人"])
        XCTAssertTrue(request.excludedArtists.isEmpty)
    }

    func testGroupedInputsByArtistPreservesOrderAndMatchesArtistInterestID() throws {
        let service = CandidateSongEditingService()
        let showID = UUID()
        let want = try ArtistInterestItem(showID: showID, artistName: "想看艺人", status: .wantToSee, order: 0)

        let inputs = [
            CandidateSongInput(songName: "S1", artist: "想看艺人"),
            CandidateSongInput(songName: "S2", artist: "其他艺人"),
            CandidateSongInput(songName: "S3", artist: "想看艺人")
        ]

        let grouped = service.groupedInputsByArtist(inputs: inputs, artistInterests: [want])

        XCTAssertEqual(grouped.map(\.artistName), ["想看艺人", "其他艺人"])
        XCTAssertEqual(grouped[0].artistInterestID, want.id)
        XCTAssertNil(grouped[1].artistInterestID)
        XCTAssertEqual(grouped[0].songs.map(\.songName), ["S1", "S3"])
        XCTAssertEqual(grouped[1].songs.map(\.songName), ["S2"])
    }

    func testMusicPlatformSearchURLsAreSearchHandoffsOnly() {
        let song = CandidateSongSnapshot(songName: "Song", artist: "Artist", order: 0)

        let urls = MusicPlatform.allCases.map { $0.searchURL(for: song).absoluteString }

        XCTAssertTrue(urls[0].hasPrefix("music://music.apple.com/search"))
        XCTAssertTrue(urls[1].hasPrefix("orpheus://search/"))
        XCTAssertTrue(urls[2].hasPrefix("qqmusic://qq.com/ui/search"))
        XCTAssertTrue(urls[3].hasPrefix("spotify:search:"))
        XCTAssertFalse(urls.joined().contains("playlist"))
    }

    @MainActor
    func testRemoteCandidateSongGenerationMapsBackendEnvelopeAndSendsMinimalShowFields() async throws {
        let json = """
        {
          "ok": true,
          "response": {
            "type": "candidateSongs",
            "items": [
              { "songName": "Song A", "artist": "Artist A" },
              { "songName": "Song B", "artist": "Artist B" }
            ]
          }
        }
        """
        let session = CapturingURLSession(
            data: json.data(using: .utf8)!,
            statusCode: 200
        )
        let show = try Show(
            name: "测试现场",
            date: makeDate(year: 2026, month: 7, day: 15),
            startTime: makeDate(year: 2026, month: 7, day: 15),
            city: "上海",
            venueName: "测试场馆",
            artist: "测试艺人",
            type: .concert
        )
        let service = RemoteCandidateSongGenerationService(
            baseURL: URL(string: "https://example.com/generate")!,
            appInstanceId: "test-instance",
            appSignature: "test-signature",
            session: session,
            calendar: calendar
        )

        let inputs = try await service.generate(for: show)

        XCTAssertEqual(inputs, [
            CandidateSongInput(songName: "Song A", artist: "Artist A"),
            CandidateSongInput(songName: "Song B", artist: "Artist B")
        ])

        let capturedRequestBodyString = await session.requestBodyString()
        let requestBodyString = try XCTUnwrap(capturedRequestBodyString)
        let bodyData = try XCTUnwrap(requestBodyString.data(using: .utf8))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["type"] as? String, "candidateSongs")
        XCTAssertEqual(body["appInstanceId"] as? String, "test-instance")
        let encodedBody = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8) ?? ""
        XCTAssertFalse(encodedBody.contains("lyrics"))
        XCTAssertFalse(encodedBody.contains("coverUrl"))
        XCTAssertFalse(encodedBody.contains("videoUrl"))
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ).date!
    }
}

private actor CapturingURLSession: URLSessionProtocol {
    var data: Data
    var statusCode: Int
    private var requestBody: Data?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestBody = request.httpBody
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func requestBodyString() -> String? {
        guard let requestBody else { return nil }
        return String(data: requestBody, encoding: .utf8)
    }
}
