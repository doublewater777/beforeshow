import XCTest
@testable import BeforeShow

final class ShowDraftImportMergeTests: XCTestCase {
    func testReimportedFallbackDateDoesNotRetainPreviousRecognition() {
        let fallbackDate = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = ShowDraft(
            name: "Dated show",
            date: fallbackDate.addingTimeInterval(86400),
            source: .link,
            recognizedFields: [.name, .date]
        )
        let incoming = ShowDraft(
            name: "Undated screenshot",
            date: fallbackDate,
            source: .screenshotOCR,
            recognizedFields: [.name]
        )

        draft.mergeRespectingUserEdits(from: incoming, userEdited: [])

        XCTAssertEqual(draft.date, fallbackDate)
        XCTAssertFalse(draft.recognizedFields.contains(.date))
    }

    func testEmptyUserEditedBehavesLikeFullReplace() {
        let now = Date()
        var draft = ShowDraft(
            name: "旧现场",
            date: now,
            city: "上海",
            venueName: "旧场馆",
            artists: [ArtistSlot(name: "旧艺人")]
        )
        let incoming = ShowDraft(
            name: "新现场",
            date: now.addingTimeInterval(86400),
            city: "北京",
            venueName: "新场馆",
            artists: [ArtistSlot(name: "新艺人")],
            source: .screenshotOCR
        )

        draft.mergeRespectingUserEdits(from: incoming, userEdited: [])

        XCTAssertEqual(draft.name, "新现场")
        XCTAssertEqual(draft.city, "北京")
        XCTAssertEqual(draft.venueName, "新场馆")
        XCTAssertEqual(draft.artists, [ArtistSlot(name: "新艺人")])
        XCTAssertEqual(draft.date, now.addingTimeInterval(86400))
    }

    func testUserEditedFieldsAreProtectedFromImport() {
        let now = Date()
        var draft = ShowDraft(
            name: "用户改好的现场名",
            date: now,
            startTime: now,
            city: "用户选的城市",
            venueName: "用户填的场馆",
            artists: [ArtistSlot(name: "用户手输的艺人")]
        )
        let incoming = ShowDraft(
            name: "OCR 识别现场名",
            date: now,
            city: "OCR 城市",
            venueName: "OCR 场馆",
            artists: [ArtistSlot(name: "OCR 艺人")],
            source: .screenshotOCR
        )

        let userEdited: Set<ShowDraftField> = [.name, .city, .venueName, .artist]
        draft.mergeRespectingUserEdits(from: incoming, userEdited: userEdited)

        XCTAssertEqual(draft.name, "用户改好的现场名")
        XCTAssertEqual(draft.city, "用户选的城市")
        XCTAssertEqual(draft.venueName, "用户填的场馆")
        XCTAssertEqual(draft.artists, [ArtistSlot(name: "用户手输的艺人")])
    }

    func testRecognizedFieldsUnionMinusUserEdited() {
        let now = Date()
        var draft = ShowDraft(name: "手填", date: now)
        draft.recognizedFields = [.city]

        let incoming = ShowDraft(
            name: "识别",
            date: now,
            source: .screenshotOCR,
            recognizedFields: [.name, .city, .artist]
        )

        draft.mergeRespectingUserEdits(from: incoming, userEdited: [.city])

        // Union: {city, name, artist}; subtract {city} → {name, artist}.
        XCTAssertEqual(draft.recognizedFields, [.name, .artist])
    }

    func testArtistsOnlyUpdateWhenUserDidNotEditArtist() {
        let now = Date()
        var draft = ShowDraft(
            name: "手填",
            date: now,
            artists: [ArtistSlot(name: "旧艺人", avatarURL: "https://example.test/old.png")]
        )

        let incoming = ShowDraft(
            name: "识别",
            date: now,
            artists: [ArtistSlot(name: "新艺人", avatarURL: "https://example.test/new.png")]
        )

        // No user edit — import overwrites artists (avatar 跟着新 slot 进)。
        draft.mergeRespectingUserEdits(from: incoming, userEdited: [])
        XCTAssertEqual(draft.artists, [ArtistSlot(name: "新艺人", avatarURL: "https://example.test/new.png")])

        // User edit on artist — import must NOT touch artists;本地 slot (含 avatar) 保持。
        var second = ShowDraft(
            name: "手填",
            date: now,
            artists: [ArtistSlot(name: "用户改的艺人", avatarURL: "https://example.test/user.png")]
        )
        second.mergeRespectingUserEdits(
            from: ShowDraft(
                name: "识别",
                date: now,
                artists: [ArtistSlot(name: "导入的艺人", avatarURL: "https://example.test/import.png")]
            ),
            userEdited: [.artist]
        )
        XCTAssertEqual(second.artists, [ArtistSlot(name: "用户改的艺人", avatarURL: "https://example.test/user.png")])
    }

    func testSourceURLCarriesOverDuringMergeAndShowCreation() throws {
        let url = "https://m.damai.cn/shows/item.html?itemId=999"
        var draft = ShowDraft(name: "草莓", date: Date(), source: .manual)
        let incoming = ShowDraft(name: "草莓音乐节", date: Date(), sourceURL: url, source: .link)

        draft.mergeRespectingUserEdits(from: incoming, userEdited: [])
        XCTAssertEqual(draft.sourceURL, url)

        draft.startTime = Date()
        let show = try draft.makeShow()
        XCTAssertEqual(show.sourceURL, url)

        var editedDraft = ShowDraft(show: show)
        XCTAssertEqual(editedDraft.sourceURL, url)
        editedDraft.name = "草莓音乐节 2026"
        try show.apply(editedDraft)
        XCTAssertEqual(show.sourceURL, url)
    }

    func testEnrichArtistsOnlyPopulatesLineupAndPreservesShowDetails() {
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = ShowDraft(
            name: "分享的现场名称",
            date: originalDate,
            city: "杭州",
            venueName: "大莲花",
            coverImageURL: "https://example.com/shared-cover.jpg",
            sourceURL: "https://detail.damai.cn/sub/123",
            source: .link
        )
        let incoming = ShowDraft(
            name: "购票网站原始标题",
            date: originalDate.addingTimeInterval(86400 * 3),
            city: "其他城市",
            venueName: "其他场馆",
            artists: [ArtistSlot(name: "周杰伦", avatarURL: "https://example.com/jay.jpg")],
            coverImageURL: "https://example.com/ticket-thumbnail.jpg",
            sourceURL: "https://detail.damai.cn/sub/123",
            source: .link
        )

        draft.enrichArtists(from: incoming)

        // Artists enriched
        XCTAssertEqual(draft.artists, [ArtistSlot(name: "周杰伦", avatarURL: "https://example.com/jay.jpg")])
        // Existing show details MUST remain completely untouched
        XCTAssertEqual(draft.name, "分享的现场名称")
        XCTAssertEqual(draft.date, originalDate)
        XCTAssertEqual(draft.city, "杭州")
        XCTAssertEqual(draft.venueName, "大莲花")
        XCTAssertEqual(draft.coverImageURL, "https://example.com/shared-cover.jpg")
    }
}
