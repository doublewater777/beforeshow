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

    func testPolicySnapRoundsAndClamps() {
        XCTAssertEqual(DispersalCeremonyPolicy.snap(0.4), 1)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(1.6), 2)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(2.5), 3)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(3.4), 3)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(4.7), 5)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(-1.0), 1)
        XCTAssertEqual(DispersalCeremonyPolicy.snap(99.0), 5)
    }

    func testSnapSliderTrackEndsOnFirstAndLastNodeCenters() {
        let width: CGFloat = 320
        let inset = DispersalSnapSliderLayout.trackInset(width: width, nodeCount: 5)
        XCTAssertEqual(inset, 32, accuracy: 0.001)
        XCTAssertEqual(inset, width * 0.10, accuracy: 0.001)
        XCTAssertEqual(width - inset, width * 0.90, accuracy: 0.001)
        let fillAtMax = width - inset * 2
        XCTAssertEqual(inset + fillAtMax, width - inset, accuracy: 0.001)
    }

    func testPolicyLightsOutDurationMatchesMotionEmphasis() {
        // 「散场」至少停住 2 秒。2.8s 总长里标题满不透明只有 1.5s,会像闪一下。
        XCTAssertEqual(DispersalCeremonyPolicy.lightsOutDuration, 4.2, accuracy: 0.001)
    }

    func testLightsOutTitleHoldLastsThroughTheCeremonyBeat() {
        let duration = DispersalCeremonyPolicy.lightsOutDuration
        let holdStart = 0.25 * duration
        let holdEnd = 0.80 * duration
        XCTAssertGreaterThanOrEqual(holdEnd - holdStart, 2.0)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.25), 1, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.80), 1, accuracy: 0.0001)
    }

    func testLightsOutProgressClampsToUnitInterval() {
        XCTAssertEqual(DispersalLightsOutMotion.progress(elapsed: -1, duration: 2.8), 0)
        XCTAssertEqual(DispersalLightsOutMotion.progress(elapsed: 0, duration: 2.8), 0)
        XCTAssertEqual(DispersalLightsOutMotion.progress(elapsed: 1.4, duration: 2.8), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.progress(elapsed: 2.8, duration: 2.8), 1)
        XCTAssertEqual(DispersalLightsOutMotion.progress(elapsed: 9, duration: 2.8), 1)
        XCTAssertEqual(DispersalLightsOutMotion.progress(elapsed: 1, duration: 0), 1)
    }

    func testLightsOutTitleOpacityFollowsKeyframeEnvelope() {
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.125), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.25), 1, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.80), 1, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 0.90), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.titleOpacity(progress: 1), 0, accuracy: 0.0001)
    }

    func testLightsOutBeamOpacityPeaksThenFades() {
        XCTAssertEqual(DispersalLightsOutMotion.beamOpacity(progress: 0, peak: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.beamOpacity(progress: 0.25, peak: 1), 1, accuracy: 0.0001)
        let mid = DispersalLightsOutMotion.beamOpacity(progress: 0.55, peak: 1)
        XCTAssertGreaterThan(mid, 0.35)
        XCTAssertLessThan(mid, 1)
        XCTAssertEqual(DispersalLightsOutMotion.beamOpacity(progress: 0.85, peak: 1), 0.35, accuracy: 0.0001)
        XCTAssertEqual(DispersalLightsOutMotion.beamOpacity(progress: 1, peak: 1), 0, accuracy: 0.0001)
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
        XCTAssertEqual(DispersalCeremonySheet.nextStep(after: .combined), .setlist)
        XCTAssertEqual(DispersalCeremonySheet.nextStep(after: .setlist), .share)
        XCTAssertEqual(DispersalCeremonySheet.nextStep(after: .share), .share)
    }

    func testSheetStaysOnCombinedWhenCommitFails() {
        XCTAssertEqual(
            DispersalCeremonySheet.nextStep(after: .combined, commitSucceeded: false),
            .combined
        )
        XCTAssertEqual(
            DispersalCeremonySheet.nextStep(after: .combined, commitSucceeded: true),
            .setlist
        )
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
            companions: [FootprintCompanionIdentity(name: "林嘉", ordinal: 2)]
        )
        XCTAssertEqual(
            DispersalCeremonyCardCopy.footerLeading(identity: withCompanion),
            "与林嘉第 2 次见面"
        )

        let withGroup = FootprintDetailIdentity(
            showOrdinal: 12,
            cityOrdinal: 3,
            companions: [
                FootprintCompanionIdentity(name: "林嘉", ordinal: 2),
                FootprintCompanionIdentity(name: "王宁", ordinal: 1)
            ]
        )
        XCTAssertEqual(
            DispersalCeremonyCardCopy.footerLeading(identity: withGroup),
            "与林嘉、王宁同行"
        )

        let solo = FootprintDetailIdentity(
            showOrdinal: 12,
            cityOrdinal: 3,
            companions: []
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
