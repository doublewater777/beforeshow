import XCTest
@testable import BeforeShow

final class FootprintNumberSongTests: XCTestCase {
    func testEveryCountFromOneToFiftyHasARecord() {
        XCTAssertEqual(FootprintNumberSongs.song(for: 7), FootprintNumberSong(number: 7, title: "七里香", artist: "周杰伦", trackID: 536115195))
        XCTAssertEqual(FootprintNumberSongs.song(for: 36)?.title, "36 Degrees")
        XCTAssertTrue((1...50).allSatisfy { FootprintNumberSongs.song(for: $0) != nil })
        XCTAssertEqual(Set((1...50).compactMap { FootprintNumberSongs.song(for: $0)?.trackID }).count, 50, "no two records share a track")
        XCTAssertNil(FootprintNumberSongs.song(for: 0))
        XCTAssertNil(FootprintNumberSongs.song(for: 51))
    }

    func testShelfShowsUnlockedNewestFirstAndTheNextSealedRecord() {
        let shelf = FootprintNumberSongs.shelf(showCount: 36)

        XCTAssertEqual(shelf.unlocked.first?.number, 36)
        XCTAssertEqual(shelf.unlocked.last?.number, 1)
        XCTAssertEqual(shelf.unlocked.count, 36)
        XCTAssertEqual(shelf.next?.number, 37, "every new show unlocks the next record")
        XCTAssertEqual(shelf.remaining, 1)
        XCTAssertEqual(shelf.total, 50)

        let fresh = FootprintNumberSongs.shelf(showCount: 0)
        XCTAssertTrue(fresh.unlocked.isEmpty)
        XCTAssertEqual(fresh.next?.number, 1)
        XCTAssertEqual(fresh.remaining, 1)
    }

    func testStoreResultBecomesAPreviewWithLargeCoverAndDetails() throws {
        var result = SongPreviewLookup.Result(trackId: 961067971, trackName: "36 Degrees", artistName: "Placebo")
        result.collectionName = "Placebo"
        result.releaseDate = "1996-06-17T07:00:00Z"
        result.primaryGenreName = "Alternative"
        result.trackTimeMillis = 214_000
        result.previewUrl = "https://example.invalid/36.m4a"
        result.artworkUrl100 = "https://example.invalid/art/100x100bb.jpg"

        let preview = try XCTUnwrap(SongPreviewLookup.preview(from: result))

        XCTAssertEqual(preview.album, "Placebo")
        XCTAssertEqual(preview.releaseYear, 1996)
        XCTAssertEqual(preview.genre, "Alternative")
        XCTAssertEqual(preview.duration, 214)
        XCTAssertEqual(preview.artworkURL?.absoluteString, "https://example.invalid/art/600x600bb.jpg")
    }

    func testAResultWithoutAPreviewIsLeftOut() {
        XCTAssertNil(SongPreviewLookup.preview(from: SongPreviewLookup.Result(trackId: 1, trackName: "x", artistName: "y")))
    }

    func testFirstRecordArtistLocalizedAcrossLanguages() {
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-Hans")?.artist, "孙燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-Hant")?.artist, "孫燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "en")?.artist, "Stefanie Sun")

        // First record title remains original Chinese across all languages
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-Hans")?.title, "第一天")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-Hant")?.title, "第一天")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "en")?.title, "第一天")

        // TrackID and song identity preserved
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "en")?.trackID, 255921455)
    }

    func testDialectAndRegionIdentifiersNormalized() {
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-CN")?.artist, "孙燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh_CN")?.artist, "孙燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-TW")?.artist, "孫燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh_TW")?.artist, "孫燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "zh-HK")?.artist, "孫燕姿")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "en-US")?.artist, "Stefanie Sun")
        XCTAssertEqual(FootprintNumberSongs.song(for: 1, language: "en_GB")?.artist, "Stefanie Sun")
    }

    func testUnconfiguredRecordsPreserveOriginalMetadataAcrossLanguages() {
        for lang in ["zh-Hans", "zh-Hant", "en", "ja"] {
            XCTAssertEqual(FootprintNumberSongs.song(for: 2, language: lang)?.artist, "The Beatles")
            XCTAssertEqual(FootprintNumberSongs.song(for: 2, language: lang)?.title, "Two of Us")
            XCTAssertEqual(FootprintNumberSongs.song(for: 7, language: lang)?.artist, "周杰伦")
            XCTAssertEqual(FootprintNumberSongs.song(for: 7, language: lang)?.title, "七里香")
            XCTAssertEqual(FootprintNumberSongs.song(for: 36, language: lang)?.artist, "Placebo")
            XCTAssertEqual(FootprintNumberSongs.song(for: 36, language: lang)?.title, "36 Degrees")
        }
    }

    func testShelfProvidesLocalizedSongs() {
        let shelfEN = FootprintNumberSongs.shelf(showCount: 1, language: "en")
        XCTAssertEqual(shelfEN.unlocked.first?.artist, "Stefanie Sun")

        let shelfHant = FootprintNumberSongs.shelf(showCount: 1, language: "zh-Hant")
        XCTAssertEqual(shelfHant.unlocked.first?.artist, "孫燕姿")

        let shelfHans = FootprintNumberSongs.shelf(showCount: 1, language: "zh-Hans")
        XCTAssertEqual(shelfHans.unlocked.first?.artist, "孙燕姿")
    }

    func testDynamicLanguageSwitchingOnSongInstance() {
        let englishSong = FootprintNumberSongs.song(for: 1, language: "en")!
        XCTAssertEqual(englishSong.artist, "Stefanie Sun")

        let switchedToHans = englishSong.localized(for: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(switchedToHans.artist, "孙燕姿")

        let switchedToHant = englishSong.localized(for: Locale(identifier: "zh-Hant"))
        XCTAssertEqual(switchedToHant.artist, "孫燕姿")
    }

    @MainActor
    func testCachedEnglishMetadataDoesNotOverrideLocalizedDisplayInDisc() {
        let song = FootprintNumberSongs.song(for: 1, language: "zh-Hans")!
        let preview = SongPreview(
            trackID: 255921455,
            title: "First Day",
            artist: "Stefanie Sun",
            album: "A Perfect Day",
            releaseYear: 2005,
            genre: "Mandopop",
            duration: 250,
            previewURL: URL(string: "https://example.com/preview.m4a")!,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            storeURL: URL(string: "https://music.apple.com/song/255921455")
        )

        let disc = FootprintNumberSongPlayer.disc(for: song, preview: preview)

        // Title and artist in ListeningDisc use BeforeShow's localized display names
        XCTAssertEqual(disc.title, "第一天")
        XCTAssertEqual(disc.artistNames, ["孙燕姿"])

        // Apple Music jump URL, artwork, track ID, duration, previewURL intact
        XCTAssertEqual(disc.appleMusicURL, preview.storeURL)
        XCTAssertEqual(disc.artworkURL, preview.artworkURL)
        XCTAssertEqual(disc.tracks.first?.duration, 250)
        XCTAssertEqual(disc.tracks.first?.previewURL, URL(string: "https://example.com/preview.m4a"))
        XCTAssertEqual(disc.tracks.first?.id, "255921455")

        // CatalogSong still carries original catalog metadata
        XCTAssertEqual(disc.tracks.first?.artistName, "Stefanie Sun")
    }
}
