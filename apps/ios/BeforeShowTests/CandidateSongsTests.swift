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

    func testFestivalGenerationTargetsTenSongsButAllowsSmallerRepertoires() {
        XCTAssertEqual(CandidateSongGenerationPolicy.maxSongs(for: .musicFestival), 10)
        XCTAssertEqual(CandidateSongGenerationPolicy.maxSongs(for: .concert), 12)
        XCTAssertEqual(CandidateSongGenerationPolicy.maximumSongs, 12)
    }

    @MainActor
    func testCandidateSongStoresFourTierHintAndMostWantedState() throws {
        let song = try CandidateSong(groupID: UUID(), songName: "歌", artist: "艺人", order: 0)
        let group = try CandidateSongGroup(showID: UUID(), uncertaintyNote: "仅供参考")

        XCTAssertFalse(song.isUserAdded)
        XCTAssertFalse(song.isStarred)
        XCTAssertFalse(song.isMostWanted)
        XCTAssertEqual(song.confidence, .mid)
        XCTAssertEqual(song.tier, .mid)
        XCTAssertNil(song.hint)
        XCTAssertFalse(group.isUserCurated)

        let marked = try CandidateSong(
            groupID: UUID(),
            songName: "安可",
            artist: "艺人",
            order: 0,
            isMostWanted: true,
            tier: .encore,
            hint: "安可位的老熟人"
        )
        XCTAssertTrue(marked.isMostWanted)
        XCTAssertTrue(marked.isStarred)
        XCTAssertEqual(marked.tier, .encore)
        XCTAssertEqual(marked.hint, "安可位的老熟人")
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

    @MainActor
    func testMakeSongsDeduplicatesSongArtistPairsKeepingFirstOccurrence() throws {
        let service = CandidateSongEditingService()
        let songs = try service.makeSongs(
            groupID: UUID(),
            inputs: [
                CandidateSongInput(songName: " 晴天 ", artist: "周杰伦", tier: .high),
                CandidateSongInput(songName: "晴天", artist: "周杰伦", tier: .encore),
                CandidateSongInput(songName: "晴天", artist: "另一位", tier: .mid)
            ]
        )

        XCTAssertEqual(songs.map(\.songName), ["晴天", "晴天"])
        XCTAssertEqual(songs.map(\.artist), ["周杰伦", "另一位"])
        XCTAssertEqual(songs.map(\.tier), [.high, .mid])
        XCTAssertEqual(songs.map(\.order), [0, 1])
    }

    func testGenerationResponseRejectsLyricsNumericConfidenceReasonsAndPlatformMetadata() {
        let payloads = [
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","lyrics":"x"}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","confidence":0.9}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","tier":0}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","tier":"low"}]}"#,
            #"{"type":"candidateSongs","items":[{"songName":"A","artist":"B","hint":4}]}"#,
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

    func testGenerationResponseAcceptsFourTiersHintsAndLegacyConfidence() throws {
        let payload = """
        {
          "type": "candidateSongs",
          "items": [
            { "songName": "Song A", "artist": "Artist A", "tier": "high", "hint": "这轮巡演主题曲" },
            { "songName": "Song B", "artist": "Artist B", "tier": "mid" },
            { "songName": "Song C", "artist": "Artist C", "tier": "guest", "hint": "给北京场的彩蛋" },
            { "songName": "Song D", "artist": "Artist D", "tier": "encore" },
            { "songName": "Song E", "artist": "Artist E" },
            { "songName": "Song F", "artist": "Artist F", "confidence": "high" }
          ]
        }
        """

        let response = try JSONDecoder().decode(
            CandidateSongGenerationResponse.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(response.items.map(\.tier), [.high, .mid, .guest, .encore, .mid, .high])
        XCTAssertEqual(response.items.map(\.hint), ["这轮巡演主题曲", nil, "给北京场的彩蛋", nil, nil, nil])
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
                CandidateSongInput(songName: "Song A", artist: "Artist A", confidence: .mid),
                CandidateSongInput(songName: "Song B", artist: "Artist B", confidence: .mid)
            ]
        )
    }

    @MainActor
    func testMakeSongsAppliesInputTierAndHint() throws {
        let service = CandidateSongEditingService()
        let songs = try service.makeSongs(
            groupID: UUID(),
            inputs: [
                CandidateSongInput(songName: "S1", artist: "A", tier: .guest, hint: "嘉宾合作"),
                CandidateSongInput(songName: "S2", artist: "A", tier: .encore)
            ]
        )
        XCTAssertEqual(songs.map(\.tier), [.guest, .encore])
        XCTAssertEqual(songs.map(\.hint), ["嘉宾合作", nil])
        XCTAssertTrue(songs.allSatisfy { !$0.isStarred })
    }

    func testEnrichMissingTierAndHintsFillsLegacySongOnlyPayload() {
        let raw = (0..<8).map { index in
            CandidateSongInput(songName: "S\(index)", artist: "A")
        }
        let enriched = CandidateSongEditingService.enrichMissingTierAndHints(raw)

        XCTAssertTrue(enriched.contains { $0.tier == .high })
        XCTAssertTrue(enriched.contains { $0.tier == .mid })
        XCTAssertTrue(enriched.contains { $0.tier == .encore })
        XCTAssertEqual(enriched.last?.tier, .encore)
        XCTAssertTrue(enriched.allSatisfy { ($0.hint?.isEmpty ?? true) == false })
        XCTAssertTrue(enriched.contains { $0.hint == "这轮巡演主题曲" || $0.hint == "近巡必唱" || $0.hint == "开场热身曲" })
    }

    func testEnrichMissingTiersAndHintsPreservesModelProvidedTiersAndHints() {
        let raw = [
            CandidateSongInput(songName: "A", artist: "X", tier: .high, hint: "这轮巡演主题曲"),
            CandidateSongInput(songName: "B", artist: "X", tier: .mid),
            CandidateSongInput(songName: "C", artist: "X", tier: .encore, hint: "安可位常客")
        ]
        let enriched = CandidateSongEditingService.enrichMissingTierAndHints(raw)

        XCTAssertEqual(enriched.map(\.tier), [.high, .mid, .encore])
        XCTAssertEqual(enriched[0].hint, "这轮巡演主题曲")
        XCTAssertEqual(enriched[2].hint, "安可位常客")
        // Mid without hint gets a short 因, but tier stays mid.
        XCTAssertEqual(enriched[1].tier, .mid)
        XCTAssertFalse(enriched[1].hint?.isEmpty ?? true)
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

    func testFestivalRequestIncludesFullSelectedLineup() throws {
        let show = try Show(name: "音乐节", date: Date(), startTime: Date(), type: .musicFestival)
        let interests = try (0..<11).map { index in
            try ArtistInterestItem(
                showID: show.id,
                artistName: "艺人\(index)",
                status: .wantToSee,
                order: index
            )
        }

        let requests = CandidateSongGenerationRequest.requests(
            for: show,
            artistInterests: interests
        )
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.artists.count, 11)
        XCTAssertEqual(request.artists, (0..<11).map { "艺人\($0)" })
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
        let capture = RequestBodyCapture()
        let stream: @Sendable (URLRequest) -> AsyncThrowingStream<BeforeShowSSEEvent, Error> = { request in
            capture.body = request.httpBody
            return AsyncThrowingStream { continuation in
                let done = #"{"ok":true,"response":{"type":"candidateSongs","items":[{"songName":"Song A","artist":"Artist A"},{"songName":"Song B","artist":"Artist B"}]}}"#
                    .data(using: .utf8)!
                continuation.yield(BeforeShowSSEEvent(event: "done", data: done))
                continuation.finish()
            }
        }
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
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: CapturingURLSession(data: Data(), statusCode: 200),
                eventStreamOverride: stream
            ),
            calendar: calendar
        )

        let inputs = try await service.generate(for: show)

        XCTAssertEqual(inputs, [
            CandidateSongInput(songName: "Song A", artist: "Artist A"),
            CandidateSongInput(songName: "Song B", artist: "Artist B")
        ])

        let bodyData = try XCTUnwrap(capture.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["type"] as? String, "candidateSongs")
        XCTAssertEqual(body["appInstanceId"] as? String, "test-instance")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let limits = try XCTUnwrap(body["limits"] as? [String: Any])
        XCTAssertEqual(limits["maxSongs"] as? Int, 12)
        XCTAssertNil(limits["targetSongs"])
        let encodedBody = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8) ?? ""
        XCTAssertFalse(encodedBody.contains("targetSongs"))
        XCTAssertFalse(encodedBody.contains("lyrics"))
        XCTAssertFalse(encodedBody.contains("coverUrl"))
        XCTAssertFalse(encodedBody.contains("videoUrl"))
    }

    @MainActor
    func testRemoteFestivalGenerationSendsMaxSongsWithoutTargetSongs() async throws {
        let capture = RequestBodyCapture()
        let stream: @Sendable (URLRequest) -> AsyncThrowingStream<BeforeShowSSEEvent, Error> = { request in
            capture.body = request.httpBody
            return AsyncThrowingStream { continuation in
                let done = #"{"ok":true,"response":{"type":"candidateSongs","items":[{"songName":"Song A","artist":"刘雨昕"},{"songName":"Song B","artist":"姚琛"}]}}"#
                    .data(using: .utf8)!
                continuation.yield(BeforeShowSSEEvent(event: "done", data: done))
                continuation.finish()
            }
        }
        let show = try Show(
            name: "绿洲音乐节",
            date: makeDate(year: 2026, month: 6, day: 27),
            startTime: makeDate(year: 2026, month: 6, day: 27),
            city: "湖州",
            venueName: "吴乐湾",
            artist: "刘雨昕, 姚琛",
            type: .musicFestival
        )
        let interestA = try ArtistInterestItem(
            showID: show.id,
            artistName: "刘雨昕",
            status: .wantToSee,
            order: 0
        )
        let interestB = try ArtistInterestItem(
            showID: show.id,
            artistName: "姚琛",
            status: .wantToSee,
            order: 1
        )
        let service = RemoteCandidateSongGenerationService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: CapturingURLSession(data: Data(), statusCode: 200),
                eventStreamOverride: stream
            ),
            calendar: calendar
        )

        _ = try await service.generate(for: show, artistInterests: [interestA, interestB])

        let bodyData = try XCTUnwrap(capture.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let limits = try XCTUnwrap(body["limits"] as? [String: Any])
        XCTAssertEqual(limits["maxSongs"] as? Int, 10)
        XCTAssertNil(limits["targetSongs"])
        XCTAssertEqual(body["stream"] as? Bool, true)
        let showPayload = try XCTUnwrap(body["show"] as? [String: Any])
        XCTAssertEqual(showPayload["artists"] as? [String], ["刘雨昕", "姚琛"])
    }

    @MainActor
    func testRemoteFestivalGenerationStreamsItemsAndSendsFullLineup() async throws {
        let show = try Show(
            name: "绿洲音乐节",
            date: makeDate(year: 2026, month: 6, day: 27),
            startTime: makeDate(year: 2026, month: 6, day: 27),
            type: .musicFestival
        )
        let interests = try (0..<11).map { index in
            try ArtistInterestItem(
                showID: show.id,
                artistName: "艺人\(index)",
                status: .wantToSee,
                order: index
            )
        }

        let capture = RequestBodyCapture()
        let stream: @Sendable (URLRequest) -> AsyncThrowingStream<BeforeShowSSEEvent, Error> = { request in
            capture.body = request.httpBody
            return AsyncThrowingStream { continuation in
                let item1 = #"{"item":{"songName":"歌1","artist":"艺人0","tier":"high","hint":"近巡必唱"}}"#
                    .data(using: .utf8)!
                let item2 = #"{"item":{"songName":"歌2","artist":"艺人5","tier":"mid","hint":"热歌候选"}}"#
                    .data(using: .utf8)!
                let done = #"{"ok":true,"response":{"type":"candidateSongs","items":[{"songName":"歌1","artist":"艺人0","tier":"high","hint":"近巡必唱"},{"songName":"歌2","artist":"艺人5","tier":"mid","hint":"热歌候选"}]}}"#
                    .data(using: .utf8)!
                continuation.yield(BeforeShowSSEEvent(event: "item", data: item1))
                continuation.yield(BeforeShowSSEEvent(event: "item", data: item2))
                continuation.yield(BeforeShowSSEEvent(event: "done", data: done))
                continuation.finish()
            }
        }

        let service = RemoteCandidateSongGenerationService(
            client: BeforeShowCloudClient(
                rootURL: URL(string: "https://example.com")!,
                credentials: BeforeShowAppCredentials(
                    appInstanceId: "test-instance",
                    appSignature: "test-signature"
                ),
                session: CapturingURLSession(data: Data(), statusCode: 200),
                eventStreamOverride: stream
            ),
            calendar: calendar
        )

        var snapshots: [CandidateSongGenerationSnapshot] = []
        for try await snapshot in service.generateCumulativeSnapshots(
            for: show,
            artistInterests: interests
        ) {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots.count, 3) // item, item, done
        XCTAssertEqual(snapshots[0], .progress([
            CandidateSongInput(songName: "歌1", artist: "艺人0", tier: .high, hint: "近巡必唱")
        ]))
        XCTAssertEqual(snapshots[1].items.map(\.songName), ["歌1", "歌2"])
        XCTAssertEqual(snapshots.last?.items.map(\.songName), ["歌1", "歌2"])
        guard case .final = snapshots.last else {
            return XCTFail("expected authoritative final snapshot")
        }

        let bodyData = try XCTUnwrap(capture.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        let showPayload = try XCTUnwrap(body["show"] as? [String: Any])
        XCTAssertEqual(showPayload["artists"] as? [String], (0..<11).map { "艺人\($0)" })
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

private final class RequestBodyCapture: @unchecked Sendable {
    var body: Data?
}

private actor CapturingURLSession: URLSessionProtocol {
    var data: Data
    var statusCode: Int
    private var requestBodies: [Data] = []

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let body = request.httpBody {
            requestBodies.append(body)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func requestBodyString() -> String? {
        guard let last = requestBodies.last else { return nil }
        return String(data: last, encoding: .utf8)
    }

    func requestBodyStrings() -> [String] {
        requestBodies.compactMap { String(data: $0, encoding: .utf8) }
    }
}
