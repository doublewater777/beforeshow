import XCTest
@testable import BeforeShow

final class DispersalCeremonyTests: XCTestCase {
    // MARK: - Show.setClosingRitual

    func testSetClosingRitualValidatesAndPersists() throws {
        let show = try Self.makeShow()
        XCTAssertNil(show.rating)
        XCTAssertNil(show.closingNote)

        try show.setClosingRitual(rating: 5, note: "最后一首歌结束的时候，灯亮得特别慢。")

        XCTAssertEqual(show.rating, 5)
        XCTAssertEqual(show.closingNote, "最后一首歌结束的时候，灯亮得特别慢。")
    }

    func testSetClosingRitualRejectsOutOfRangeRating() throws {
        let show = try Self.makeShow()
        XCTAssertThrowsError(try show.setClosingRitual(rating: 0, note: nil)) { error in
            XCTAssertEqual(error as? ShowValidationError, .ratingOutOfRange)
        }
        XCTAssertThrowsError(try show.setClosingRitual(rating: 6, note: nil)) { error in
            XCTAssertEqual(error as? ShowValidationError, .ratingOutOfRange)
        }
        XCTAssertThrowsError(try show.setClosingRitual(rating: 999, note: nil)) { error in
            XCTAssertEqual(error as? ShowValidationError, .ratingOutOfRange)
        }
    }

    func testClosingNoteTrimmedEmpty() throws {
        let show = try Self.makeShow()
        try show.setClosingRitual(rating: 3, note: "   \n  \t  ")
        XCTAssertNil(show.closingNote)
    }

    func testClosingNoteReplacedCRLFAndTrimmed() throws {
        let show = try Self.makeShow()
        try show.setClosingRitual(rating: 4, note: "\r\n  现场太顶了\r\n  ")
        XCTAssertEqual(show.closingNote, "现场太顶了")
    }

    func testClosingNoteRejectsOver500Chars() throws {
        let show = try Self.makeShow()
        let tooLong = String(repeating: "现", count: 501)
        XCTAssertThrowsError(try show.setClosingRitual(rating: 5, note: tooLong)) { error in
            XCTAssertEqual(error as? ShowValidationError, .closingNoteTooLong)
        }
    }

    func testClosingNoteAcceptsExactly500Chars() throws {
        let show = try Self.makeShow()
        let exactly500 = String(repeating: "现", count: 500)
        try show.setClosingRitual(rating: 5, note: exactly500)
        XCTAssertEqual(show.closingNote?.count, 500)
    }

    func testSetClosingRitualIsIdempotentWhenValuesUnchanged() throws {
        let show = try Self.makeShow()
        try show.setClosingRitual(rating: 5, note: "顶")
        let updatedAtAfterFirst = show.updatedAt
        try show.setClosingRitual(rating: 5, note: "顶")
        XCTAssertEqual(show.updatedAt, updatedAtAfterFirst)
    }

    func testSetClosingRitualTouchesUpdatedAtWhenValueChanges() throws {
        let show = try Self.makeShow()
        try show.setClosingRitual(rating: 3, note: nil)
        let updatedAtAfterFirst = show.updatedAt
        try show.setClosingRitual(rating: 5, note: "棒")
        XCTAssertGreaterThan(show.updatedAt, updatedAtAfterFirst)
    }

    func testSetClosingRitualAllowsClearingExistingValues() throws {
        let show = try Self.makeShow()
        try show.setClosingRitual(rating: 5, note: "顶")
        try show.setClosingRitual(rating: nil, note: nil)
        XCTAssertNil(show.rating)
        XCTAssertNil(show.closingNote)
    }

    // MARK: - DispersalCeremonyPolicy

    func testPolicyClampRatingBounds() {
        XCTAssertNil(DispersalCeremonyPolicy.clampRating(0))
        XCTAssertNil(DispersalCeremonyPolicy.clampRating(6))
        XCTAssertEqual(DispersalCeremonyPolicy.clampRating(1), 1)
        XCTAssertEqual(DispersalCeremonyPolicy.clampRating(3), 3)
        XCTAssertEqual(DispersalCeremonyPolicy.clampRating(5), 5)
    }

    func testPolicySnapRoundsAndClamps() {
        XCTAssertEqual(DispersalCeremonyPolicy.snap(0.4), 1)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(1.6), 2)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(2.5), 3)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(3.4), 3)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(4.7), 5)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(-1.0), 1)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(99.0), 5)
    }

    func testPolicyLightsOutDurationMatchesMotionEmphasis() {
        // 2.8s 与 V2 原型 3 光束淡入淡出节奏对齐。reduceMotion 时跳过。
        XCTAssertEqual(DispersalCeremonyPolicy.lightsOutDuration, 2.8, accuracy: 0.001)
    }

    func testPolicyMaximumNoteLengthMatchesShowValidation() {
        XCTAssertEqual(DispersalCeremonyPolicy.maximumNoteLength, 500)
    }

    // MARK: - DispersalRating metadata

    func testRatingHasConsistentEmojiAndLabel() {
        for rating in DispersalRating.allCases {
            XCTAssertFalse(rating.emoji.isEmpty, "emoji missing for \(rating)")
            XCTAssertFalse(rating.label.isEmpty, "label missing for \(rating)")
            XCTAssertTrue(rating.accessibilityLabel.contains(rating.label))
        }
    }

    func testRatingHasSubtitleForEveryTier() {
        for rating in DispersalRating.allCases {
            XCTAssertFalse(rating.sub.isEmpty, "sub missing for \(rating)")
        }
        // 5 档必须各不相同,否则"卡档"读起来像同义反复。
        XCTAssertEqual(
            Set(DispersalRating.allCases.map(\.sub)).count,
            DispersalRating.allCases.count
        )
    }

    func testRatingRoundTripsThroughRawValue() {
        for rating in DispersalRating.allCases {
            XCTAssertEqual(DispersalRating.from(rawValue: rating.rawValue), rating)
        }
        XCTAssertNil(DispersalRating.from(rawValue: 0))
        XCTAssertNil(DispersalRating.from(rawValue: 6))
    }

    // MARK: - DispersalCeremonySheet navigation seam

    func testSheetNextStepAdvances() {
        // 评级+文字 同页(V2 同款),所以 combined → share 是单步跨越。
        XCTAssertEqual(DispersalCeremonySheet.nextStep(after: .combined), .share)
        XCTAssertEqual(DispersalCeremonySheet.nextStep(after: .share), .share)
    }

    // MARK: - DispersalCeremonyPolicy.quickFillPresets

    func testQuickFillPresetsExposeThreeDistinctOptions() {
        let presets = DispersalCeremonyPolicy.quickFillPresets
        XCTAssertEqual(presets.count, 3)
        // 3 个预设文案必须各不相同,否则 chip 之间没有意义。
        XCTAssertEqual(Set(presets.map(\.text)).count, presets.count)
        // 每个 preset 必须有 label 文本。
        for preset in presets {
            XCTAssertFalse(preset.label.isEmpty, "preset label missing")
            XCTAssertFalse(preset.text.isEmpty, "preset text missing for \(preset.label)")
        }
    }

    func testQuickFillPresetsRespectNoteLengthLimit() {
        for preset in DispersalCeremonyPolicy.quickFillPresets {
            XCTAssertLessThanOrEqual(
                preset.text.count,
                DispersalCeremonyPolicy.maximumNoteLength,
                "preset '\(preset.label)' overflows the 500-char limit"
            )
        }
    }

    // MARK: - DispersalCeremonyCardCopy

    func testCardEventLinesSplitsArtistPrefix() {
        XCTAssertEqual(
            DispersalCeremonyCardCopy.eventLines(
                name: "草东没有派对 · 散场仪式 DEMO",
                artistNames: ["草东没有派对"]
            ),
            ["草东没有派对", "散场仪式 DEMO"]
        )
    }

    func testCardEventLinesKeepsBareName() {
        XCTAssertEqual(
            DispersalCeremonyCardCopy.eventLines(name: "陈绮贞", artistNames: []),
            ["陈绮贞"]
        )
        XCTAssertEqual(
            DispersalCeremonyCardCopy.eventLines(name: "陈绮贞", artistNames: ["陈绮贞"]),
            ["陈绮贞"]
        )
    }

    func testCardEventLinesStacksArtistWhenTitleIsIndependent() {
        XCTAssertEqual(
            DispersalCeremonyCardCopy.eventLines(
                name: "漫漫长夜 Cheer20",
                artistNames: ["陈绮贞"]
            ),
            ["陈绮贞", "漫漫长夜 Cheer20"]
        )
    }

    func testCardFooterPrefersCompanionOverOrdinal() {
        let withCompanion = FootprintDetailIdentity(
            showOrdinal: 12,
            cityOrdinal: 3,
            companionName: "林嘉",
            companionOrdinal: 2
        )
        XCTAssertEqual(
            DispersalCeremonyCardCopy.footerLeading(identity: withCompanion),
            "与林嘉第 2 次见面"
        )

        let solo = FootprintDetailIdentity(
            showOrdinal: 12,
            cityOrdinal: 3,
            companionName: nil,
            companionOrdinal: nil
        )
        XCTAssertEqual(
            DispersalCeremonyCardCopy.footerLeading(identity: solo),
            "我的第 12 场现场"
        )
    }

    func testCardRatingTitleJoinsEmojiAndLabel() {
        XCTAssertEqual(
            DispersalCeremonyCardCopy.ratingTitle(.fire),
            "🔥 夯爆了"
        )
    }

    // MARK: - Fixtures

    private static func makeShow() throws -> Show {
        let now = Date()
        return try Show(
            name: "陈绮贞",
            date: now,
            startTime: now.addingTimeInterval(-3_600)
        )
    }
}
