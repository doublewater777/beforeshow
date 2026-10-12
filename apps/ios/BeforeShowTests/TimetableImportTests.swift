import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class TimetableImportTests: XCTestCase {

    // MARK: - Parser Tests

    func testParser_bareJSONDecodesSuccessfully() throws {
        let json = """
        {"version":1,"timeZone":"Asia/Shanghai","days":[{"date":"2026-10-17","stages":[{"name":"Main","performances":[{"artist":"Artist A","start":"18:00","end":"19:00"}]}]}]}
        """
        let doc = try TimetableImportParser.document(from: json)
        XCTAssertEqual(doc.version, 1)
        XCTAssertEqual(doc.timeZone, "Asia/Shanghai")
        XCTAssertEqual(doc.days.count, 1)
        XCTAssertEqual(doc.days[0].stages.count, 1)
        XCTAssertEqual(doc.days[0].stages[0].performances.count, 1)
    }

    func testParser_jsonInsideCodeFencesWithSurroundingTextDecodesSuccessfully() throws {
        let text = """
        Here is the parsed timetable:
        ```json
        {
          "version": 1,
          "timeZone": null,
          "days": []
        }
        ```
        Hope this works well!
        """
        let doc = try TimetableImportParser.document(from: text)
        XCTAssertEqual(doc.version, 1)
        XCTAssertNil(doc.timeZone)
        XCTAssertTrue(doc.days.isEmpty)
    }

    func testParser_emptyOrWhitespaceThrowsEmpty() {
        XCTAssertThrowsError(try TimetableImportParser.document(from: "")) { error in
            XCTAssertEqual(error as? TimetableImportError, .empty)
        }
        XCTAssertThrowsError(try TimetableImportParser.document(from: "   \n\t  ")) { error in
            XCTAssertEqual(error as? TimetableImportError, .empty)
        }
    }

    func testParser_noBracesThrowsNoData() {
        XCTAssertThrowsError(try TimetableImportParser.document(from: "Plain text without any braces")) { error in
            XCTAssertEqual(error as? TimetableImportError, .noData)
        }
        XCTAssertThrowsError(try TimetableImportParser.document(from: "} opening after closing {")) { error in
            XCTAssertEqual(error as? TimetableImportError, .noData)
        }
    }

    func testParser_malformedJSONThrowsInvalidFormat() {
        XCTAssertThrowsError(try TimetableImportParser.document(from: "{ not valid json : }")) { error in
            XCTAssertEqual(error as? TimetableImportError, .invalidFormat)
        }
        XCTAssertThrowsError(try TimetableImportParser.document(from: "prefix {\"version\": 1, \"days\": broken} suffix")) { error in
            XCTAssertEqual(error as? TimetableImportError, .invalidFormat)
        }
    }

    func testParser_missingVersionThrowsInvalidFormat() {
        let json = "{\"timeZone\":\"Asia/Shanghai\",\"days\":[]}"
        XCTAssertThrowsError(try TimetableImportParser.document(from: json)) { error in
            XCTAssertEqual(error as? TimetableImportError, .invalidFormat)
        }
    }

    func testParser_versionTwoThrowsUnsupportedVersion() {
        let json = "{\"version\":2,\"days\":[]}"
        XCTAssertThrowsError(try TimetableImportParser.document(from: json)) { error in
            XCTAssertEqual(error as? TimetableImportError, .unsupportedVersion)
        }
    }

    func testParser_wrongFieldTypeThrowsInvalidFormat() {
        let json = """
        {"version":1,"days":[{"date":"2026-10-17","stages":[{"name":"Main","performances":[{"artist":"Artist A","start":1800,"end":"19:00"}]}]}]}
        """
        XCTAssertThrowsError(try TimetableImportParser.document(from: json)) { error in
            XCTAssertEqual(error as? TimetableImportError, .invalidFormat)
        }
    }

    func testParser_textOverMaxCharactersThrowsTooLarge() {
        let huge = "{" + String(repeating: " ", count: TimetableImportParser.maxCharacters + 10) + "}"
        XCTAssertThrowsError(try TimetableImportParser.document(from: huge)) { error in
            XCTAssertEqual(error as? TimetableImportError, .tooLarge)
        }
    }

    // MARK: - Mapper Tests

    func testMapper_singleDaySingleStage() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(
                    date: "2026-10-17",
                    stages: [
                        .init(
                            name: "Main Stage",
                            performances: [
                                .init(artist: "Artist A", start: "14:00", end: "15:00"),
                                .init(artist: "Artist B", start: "16:00", end: "17:00")
                            ]
                        )
                    ]
                )
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.draft.days.count, 1)
        let day = result.draft.days[0]
        XCTAssertEqual(day.date, makeDate(year: 2026, month: 10, day: 17))
        XCTAssertEqual(day.stages.count, 1)
        let stage = day.stages[0]
        XCTAssertEqual(stage.name, "Main Stage")
        XCTAssertEqual(stage.sortOrder, 0)
        XCTAssertEqual(stage.performances.count, 2)
        XCTAssertEqual(stage.performances[0].artistName, "Artist A")
        XCTAssertEqual(stage.performances[0].startsAt, makeDate(year: 2026, month: 10, day: 17, hour: 14, minute: 0))
        XCTAssertEqual(stage.performances[0].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 15, minute: 0))
        XCTAssertEqual(stage.performances[1].artistName, "Artist B")
        XCTAssertEqual(stage.performances[1].startsAt, makeDate(year: 2026, month: 10, day: 17, hour: 16, minute: 0))
        XCTAssertEqual(stage.performances[1].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 17, minute: 0))
    }

    func testMapper_singleDayThreeStagesPreservesStageOrder() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(
                    date: "2026-10-17",
                    stages: [
                        .init(name: "Stage Alpha", performances: [.init(artist: "A1", start: "14:00", end: "15:00")]),
                        .init(name: "Stage Beta", performances: [.init(artist: "B1", start: "15:00", end: "16:00")]),
                        .init(name: "Stage Gamma", performances: [.init(artist: "G1", start: "16:00", end: "17:00")])
                    ]
                )
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days[0].stages.map(\.name), ["Stage Alpha", "Stage Beta", "Stage Gamma"])
        XCTAssertEqual(result.draft.days[0].stages.map(\.sortOrder), [0, 1, 2])
    }

    func testMapper_multiDayMultiStage() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(
                    date: "2026-10-17",
                    stages: [
                        .init(name: "Stage 1", performances: [.init(artist: "A", start: "14:00", end: "15:00")]),
                        .init(name: "Stage 2", performances: [.init(artist: "B", start: "15:00", end: "16:00")])
                    ]
                ),
                .init(
                    date: "2026-10-18",
                    stages: [
                        .init(name: "Stage 1", performances: [.init(artist: "C", start: "14:00", end: "15:00")]),
                        .init(name: "Stage 2", performances: [.init(artist: "D", start: "15:00", end: "16:00")])
                    ]
                )
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days.count, 2)
        XCTAssertEqual(result.draft.days[0].date, makeDate(year: 2026, month: 10, day: 17))
        XCTAssertEqual(result.draft.days[1].date, makeDate(year: 2026, month: 10, day: 18))
        XCTAssertEqual(result.draft.days[0].stages.count, 2)
        XCTAssertEqual(result.draft.days[1].stages.count, 2)
    }

    func testMapper_sameArtistOnTwoDifferentDaysStaysTwoSets() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [.init(name: "Main", performances: [.init(artist: "Headliner", start: "20:00", end: "21:00")])]),
                .init(date: "2026-10-18", stages: [.init(name: "Main", performances: [.init(artist: "Headliner", start: "20:00", end: "21:00")])])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days.count, 2)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.map(\.artistName), ["Headliner"])
        XCTAssertEqual(result.draft.days[1].stages[0].performances.map(\.artistName), ["Headliner"])
    }

    func testMapper_sameArtistTwiceSameDayDifferentTimesStaysTwo() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Busy Band", start: "14:00", end: "15:00"),
                        .init(artist: "Busy Band", start: "19:00", end: "20:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 2)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.map(\.artistName), ["Busy Band", "Busy Band"])
    }

    func testMapper_exactDuplicateIsDropped() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Band", start: "18:00", end: "19:00"),
                        .init(artist: "Band", start: "18:00", end: "19:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
    }

    func testMapper_overnightPerformanceEndsNextCalendarDayAndBelongsToSameDay() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Night Stage", performances: [
                        .init(artist: "Late Band", start: "23:30", end: "00:30")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days.count, 1)
        XCTAssertEqual(result.draft.days[0].date, makeDate(year: 2026, month: 10, day: 17))
        let perf = result.draft.days[0].stages[0].performances[0]
        XCTAssertEqual(perf.startsAt, makeDate(year: 2026, month: 10, day: 17, hour: 23, minute: 30))
        XCTAssertEqual(perf.endsAt, makeDate(year: 2026, month: 10, day: 18, hour: 0, minute: 30))
    }

    func testMapper_midnightStartWithDaytimeSetsMovesToAfterMidnight() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Evening Star", start: "20:00", end: "21:00"),
                        .init(artist: "After Midnight", start: "00:30", end: "01:30")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        let perfs = result.draft.days[0].stages[0].performances
        XCTAssertEqual(perfs.count, 2)
        XCTAssertEqual(perfs[0].artistName, "Evening Star")
        XCTAssertEqual(perfs[0].startsAt, makeDate(year: 2026, month: 10, day: 17, hour: 20, minute: 0))
        XCTAssertEqual(perfs[1].artistName, "After Midnight")
        XCTAssertEqual(perfs[1].startsAt, makeDate(year: 2026, month: 10, day: 18, hour: 0, minute: 30))
        XCTAssertEqual(perfs[1].endsAt, makeDate(year: 2026, month: 10, day: 18, hour: 1, minute: 30))
    }

    func testMapper_twentyFourHourThirtyNotation() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Evening Act", start: "20:00", end: "21:00"),
                        .init(artist: "Late Act", start: "24:30", end: "25:30")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        let perfs = result.draft.days[0].stages[0].performances
        XCTAssertEqual(perfs.count, 2)
        XCTAssertEqual(perfs[1].artistName, "Late Act")
        XCTAssertEqual(perfs[1].startsAt, makeDate(year: 2026, month: 10, day: 18, hour: 0, minute: 30))
        XCTAssertEqual(perfs[1].endsAt, makeDate(year: 2026, month: 10, day: 18, hour: 1, minute: 30))
    }

    func testMapper_nullEndInfersNextSetStartWithinThreeHoursOrAddsFortyFiveMinutes() throws {
        let docGapWithinThreeHours = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Band 1", start: "14:00", end: nil),
                        .init(artist: "Band 2", start: "16:00", end: "17:00")
                    ])
                ])
            ]
        )
        let result1 = try mapDocument(docGapWithinThreeHours)
        XCTAssertEqual(result1.draft.days[0].stages[0].performances[0].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 16, minute: 0))

        let docGapOverThreeHours = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Band 1", start: "14:00", end: nil),
                        .init(artist: "Band 2", start: "18:00", end: "19:00")
                    ])
                ])
            ]
        )
        let result2 = try mapDocument(docGapOverThreeHours)
        XCTAssertEqual(result2.draft.days[0].stages[0].performances[0].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 14, minute: 45))
    }

    func testMapper_lastSetOnStageWithNullEndAddsFortyFiveMinutes() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Solo Act", start: "20:00", end: nil)
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days[0].stages[0].performances[0].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 20, minute: 45))
    }

    func testMapper_endEarlierThanStartByMoreThanSixHoursTreatedAsMissingEnd() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Typo End", start: "20:00", end: "19:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days[0].stages[0].performances[0].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 20, minute: 45))
    }

    func testMapper_nullArtistIsSkippedAndCounted() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: nil, start: "14:00", end: "15:00"),
                        .init(artist: "Valid", start: "16:00", end: "17:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
        XCTAssertEqual(result.draft.days[0].stages[0].performances[0].artistName, "Valid")
    }

    func testMapper_nullStartIsSkippedAndCounted() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "No Start", start: nil, end: "15:00"),
                        .init(artist: "Valid", start: "16:00", end: "17:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
    }

    func testMapper_fullyBlankPerformanceIsIgnoredAndNotCounted() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: nil, start: nil, end: nil),
                        .init(artist: "   ", start: nil, end: nil),
                        .init(artist: "Valid", start: "16:00", end: "17:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
    }

    func testMapper_invalidDateThrowsInvalidDate() {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-02-30", stages: [
                    .init(name: "Main", performances: [.init(artist: "A", start: "14:00", end: "15:00")])
                ])
            ]
        )
        XCTAssertThrowsError(try mapDocument(doc)) { error in
            XCTAssertEqual(error as? TimetableImportError, .invalidDate)
        }
    }

    func testMapper_invalidStartSkippedAndCounted() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Bad Start", start: "25:99", end: "15:00"),
                        .init(artist: "Valid", start: "16:00", end: "17:00")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
    }

    func testMapper_invalidEndInfersEnd() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "Bad End", start: "14:00", end: "25:99")
                    ])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
        XCTAssertEqual(result.draft.days[0].stages[0].performances[0].endsAt, makeDate(year: 2026, month: 10, day: 17, hour: 14, minute: 45))
    }

    func testMapper_invalidTimeZoneThrowsInvalidTimeZone() {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Mars/Base",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [.init(artist: "A", start: "14:00", end: "15:00")])
                ])
            ]
        )
        XCTAssertThrowsError(try mapDocument(doc)) { error in
            XCTAssertEqual(error as? TimetableImportError, .invalidTimeZone)
        }
    }

    func testMapper_validDocumentTimeZoneIsUsed() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "America/New_York",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [.init(artist: "A", start: "14:00", end: "15:00")])
                ])
            ]
        )
        let result = try mapDocument(doc, defaultTimeZone: "Asia/Shanghai")
        XCTAssertEqual(result.draft.timeZoneIdentifier, "America/New_York")
    }

    func testMapper_nullDateSingleDayFallsBackToFallbackDateDay() throws {
        let fallback = makeDate(year: 2026, month: 11, day: 5, hour: 18, minute: 30)
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: nil, stages: [
                    .init(name: "Main", performances: [.init(artist: "A", start: "14:00", end: "15:00")])
                ])
            ]
        )
        let result = try mapDocument(doc, fallbackDate: fallback)
        XCTAssertEqual(result.draft.days.count, 1)
        XCTAssertEqual(result.draft.days[0].date, makeDate(year: 2026, month: 11, day: 5))
    }

    func testMapper_nullDateTwoDaysThrowsMissingDate() {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [.init(name: "Main", performances: [.init(artist: "A", start: "14:00", end: "15:00")])]),
                .init(date: nil, stages: [.init(name: "Main", performances: [.init(artist: "B", start: "14:00", end: "15:00")])])
            ]
        )
        XCTAssertThrowsError(try mapDocument(doc)) { error in
            XCTAssertEqual(error as? TimetableImportError, .missingDate)
        }
    }

    func testMapper_monthDayDateUsesFallbackDateYear() throws {
        let fallback = makeDate(year: 2026, month: 1, day: 1)
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "10-17", stages: [
                    .init(name: "Main", performances: [.init(artist: "A", start: "14:00", end: "15:00")])
                ])
            ]
        )
        let result = try mapDocument(doc, fallbackDate: fallback)
        XCTAssertEqual(result.draft.days[0].date, makeDate(year: 2026, month: 10, day: 17))
    }

    func testMapper_emptyStageNameUsesUnnamedStageName() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: nil, performances: [.init(artist: "A", start: "14:00", end: "15:00")]),
                    .init(name: "  ", performances: [.init(artist: "B", start: "15:00", end: "16:00")])
                ])
            ]
        )
        let result = try mapDocument(doc)
        XCTAssertEqual(result.draft.days[0].stages.map(\.name), ["舞台 1", "舞台 2"])
    }

    func testMapper_allPerformancesMissingTimesThrowsNoSchedule() {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "A", start: nil, end: nil),
                        .init(artist: "B", start: "25:99", end: "15:00")
                    ])
                ])
            ]
        )
        XCTAssertThrowsError(try mapDocument(doc)) { error in
            XCTAssertEqual(error as? TimetableImportError, .noSchedule)
        }
    }

    func testMapper_previousDayEndingAfterNextDayFirstStartThrowsConflictingDays() {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(date: "2026-10-17", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "A", start: "23:00", end: "01:30")
                    ])
                ]),
                .init(date: "2026-10-18", stages: [
                    .init(name: "Main", performances: [
                        .init(artist: "B", start: "01:00", end: "02:00")
                    ])
                ])
            ]
        )
        XCTAssertThrowsError(try mapDocument(doc)) { error in
            XCTAssertEqual(error as? TimetableImportError, .conflictingDays)
        }
    }

    func testMapper_tooManyDaysThrowsTooLarge() {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: (1...32).map { day in
                .init(date: String(format: "2026-10-%02d", min(day, 31)), stages: [])
            }
        )
        XCTAssertThrowsError(try mapDocument(doc)) { error in
            XCTAssertEqual(error as? TimetableImportError, .tooLarge)
        }
    }

    // MARK: - Carryover Tests

    func testCarryover_uniqueExactMatchPreservesInterestAndAppleMusicLink() {
        let date = makeDate(year: 2026, month: 10, day: 17)
        var oldPerf = TimetableDraftPerformance(
            artistName: "Match Artist",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: true
        )
        oldPerf.connectArtist(RecognizedArtist(id: "am-123", canonicalName: "Match Artist", avatarURL: URL(string: "https://example.com/avatar.jpg"), appleMusicURL: nil))
        let previous = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [oldPerf])
            ])
        ])

        var current = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [
                    TimetableDraftPerformance(
                        artistName: "Match Artist",
                        startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
                        endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 30),
                        isInterested: false
                    )
                ])
            ])
        ])

        TimetableReimportCarryover.apply(from: previous, to: &current)
        let carried = current.days[0].stages[0].performances[0]
        XCTAssertTrue(carried.isInterested)
        XCTAssertEqual(carried.appleMusicArtistID, "am-123")
        XCTAssertEqual(carried.artistAvatarURL, "https://example.com/avatar.jpg")
    }

    func testCarryover_differsByStartTimeNotCarried() {
        let date = makeDate(year: 2026, month: 10, day: 17)
        var oldPerf = TimetableDraftPerformance(
            artistName: "Match Artist",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: true
        )
        oldPerf.connectArtist(RecognizedArtist(id: "am-123", canonicalName: "Match Artist", avatarURL: nil, appleMusicURL: nil))
        let previous = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [oldPerf])
            ])
        ])

        var current = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [
                    TimetableDraftPerformance(
                        artistName: "Match Artist",
                        startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 30),
                        endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 30),
                        isInterested: false
                    )
                ])
            ])
        ])

        TimetableReimportCarryover.apply(from: previous, to: &current)
        let carried = current.days[0].stages[0].performances[0]
        XCTAssertFalse(carried.isInterested)
        XCTAssertNil(carried.appleMusicArtistID)
    }

    func testCarryover_sameArtistOnAnotherStageNotCarried() {
        let date = makeDate(year: 2026, month: 10, day: 17)
        var oldPerf = TimetableDraftPerformance(
            artistName: "Match Artist",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: true
        )
        oldPerf.connectArtist(RecognizedArtist(id: "am-123", canonicalName: "Match Artist", avatarURL: nil, appleMusicURL: nil))
        let previous = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Stage Alpha", performances: [oldPerf])
            ])
        ])

        var current = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Stage Beta", performances: [
                    TimetableDraftPerformance(
                        artistName: "Match Artist",
                        startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
                        endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
                        isInterested: false
                    )
                ])
            ])
        ])

        TimetableReimportCarryover.apply(from: previous, to: &current)
        let carried = current.days[0].stages[0].performances[0]
        XCTAssertFalse(carried.isInterested)
        XCTAssertNil(carried.appleMusicArtistID)
    }

    func testCarryover_ambiguousDuplicateKeysInOldNotCarried() {
        let date = makeDate(year: 2026, month: 10, day: 17)
        var oldPerf = TimetableDraftPerformance(
            artistName: "Match Artist",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: true
        )
        oldPerf.connectArtist(RecognizedArtist(id: "am-123", canonicalName: "Match Artist", avatarURL: nil, appleMusicURL: nil))
        let ambiguousOld = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [oldPerf, oldPerf])
            ])
        ])

        var current = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [
                    TimetableDraftPerformance(
                        artistName: "Match Artist",
                        startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
                        endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
                        isInterested: false
                    )
                ])
            ])
        ])

        TimetableReimportCarryover.apply(from: ambiguousOld, to: &current)
        let carried = current.days[0].stages[0].performances[0]
        XCTAssertFalse(carried.isInterested)
        XCTAssertNil(carried.appleMusicArtistID)
    }

    func testCarryover_existingLinkInNewDraftNeverCleared() {
        let date = makeDate(year: 2026, month: 10, day: 17)
        let oldNoLink = TimetableDraftPerformance(
            artistName: "Match Artist",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: true
        )
        let previous = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [oldNoLink])
            ])
        ])

        var currentWithLink = TimetableDraftPerformance(
            artistName: "Match Artist",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: false
        )
        currentWithLink.connectArtist(RecognizedArtist(id: "current-am-id", canonicalName: "Match Artist", avatarURL: nil, appleMusicURL: nil))

        var current = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: date, stages: [
                TimetableDraftStage(name: "Main", performances: [currentWithLink])
            ])
        ])

        TimetableReimportCarryover.apply(from: previous, to: &current)
        let carried = current.days[0].stages[0].performances[0]
        XCTAssertTrue(carried.isInterested)
        XCTAssertEqual(carried.appleMusicArtistID, "current-am-id")
    }

    // MARK: - Round Trip Tests

    func testRoundTrip_timetableToDraftToTimetablePreservesAllFields() throws {
        var p1 = TimetableDraftPerformance(
            artistName: "Band 1",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 18, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 19, minute: 0),
            isInterested: true
        )
        p1.connectArtist(RecognizedArtist(id: "am-1", canonicalName: "Band 1", avatarURL: URL(string: "https://example.com/avatar.jpg"), appleMusicURL: nil))
        let p2 = TimetableDraftPerformance(
            artistName: "Band 2",
            startsAt: makeDate(year: 2026, month: 10, day: 17, hour: 20, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 17, hour: 21, minute: 0),
            isInterested: false
        )
        let p3 = TimetableDraftPerformance(
            artistName: "Band 3",
            startsAt: makeDate(year: 2026, month: 10, day: 18, hour: 19, minute: 0),
            endsAt: makeDate(year: 2026, month: 10, day: 18, hour: 20, minute: 0),
            isInterested: false
        )

        let initialDraft = TimetableDraft(timeZoneIdentifier: "Asia/Shanghai", days: [
            TimetableDraftDay(date: makeDate(year: 2026, month: 10, day: 17), stages: [
                TimetableDraftStage(name: "Main", sortOrder: 0, performances: [p1, p2])
            ]),
            TimetableDraftDay(date: makeDate(year: 2026, month: 10, day: 18), stages: [
                TimetableDraftStage(name: "Second", sortOrder: 0, performances: [p3])
            ])
        ])

        let timetable = try initialDraft.buildTimetable()
        let reconstructedDraft = TimetableDraft(from: timetable)
        let reconstructedTimetable = try reconstructedDraft.buildTimetable()

        XCTAssertEqual(reconstructedTimetable.timeZoneIdentifier, timetable.timeZoneIdentifier)
        XCTAssertEqual(reconstructedTimetable.orderedDays.count, timetable.orderedDays.count)
        for (dayA, dayB) in zip(timetable.orderedDays, reconstructedTimetable.orderedDays) {
            XCTAssertEqual(dayA.date, dayB.date)
            XCTAssertEqual(dayA.orderedStages.count, dayB.orderedStages.count)
            for (stageA, stageB) in zip(dayA.orderedStages, dayB.orderedStages) {
                XCTAssertEqual(stageA.name, stageB.name)
                XCTAssertEqual(stageA.sortOrder, stageB.sortOrder)
                XCTAssertEqual(stageA.orderedPerformances.count, stageB.orderedPerformances.count)
                for (perfA, perfB) in zip(stageA.orderedPerformances, stageB.orderedPerformances) {
                    XCTAssertEqual(perfA.artistName, perfB.artistName)
                    XCTAssertEqual(perfA.startsAt, perfB.startsAt)
                    XCTAssertEqual(perfA.endsAt, perfB.endsAt)
                    XCTAssertEqual(perfA.isInterested, perfB.isInterested)
                    XCTAssertEqual(perfA.appleMusicArtistID, perfB.appleMusicArtistID)
                    XCTAssertEqual(perfA.artistAvatarURL, perfB.artistAvatarURL)
                }
            }
        }
    }

    // MARK: - Prompt Localization & Embedded Example Tests

    func testPrompt_localizedStringsContainRequiredFieldsAndExampleJSONParses() throws {
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let promptText = loadPrompt(for: locale)
            XCTAssertFalse(promptText.isEmpty, "Missing prompt for \(locale)")
            XCTAssertTrue(promptText.contains("\"version\":1"), "Prompt for \(locale) missing \"version\":1")
            for field in ["days", "stages", "performances", "artist", "start", "end", "timeZone"] {
                XCTAssertTrue(promptText.contains(field), "Prompt for \(locale) missing field '\(field)'")
            }

            guard let json = TimetableImportParser.extractObject(from: promptText) else {
                XCTFail("Failed to extract JSON object from \(locale) prompt")
                continue
            }
            let doc = try TimetableImportParser.document(from: json)
            let result = try mapDocument(doc)
            XCTAssertEqual(result.draft.days.count, 1)
            XCTAssertEqual(result.draft.days[0].stages.count, 1)
            XCTAssertEqual(result.draft.days[0].stages[0].performances.count, 1)
            XCTAssertEqual(result.skippedCount, 0)
        }
    }

    // MARK: - Session Review Tests

    func testSession_reviewedDraftRemovesEmptyStagesAndPreservesOrder() throws {
        let doc = TimetableExchangeDocument(
            version: 1,
            timeZone: "Asia/Shanghai",
            days: [
                .init(
                    date: "2026-10-17",
                    stages: [
                        .init(name: "Stage 1", performances: [.init(artist: "A", start: "14:00", end: "15:00")]),
                        .init(name: "Stage 2", performances: [.init(artist: "B", start: "16:00", end: "17:00")])
                    ]
                )
            ]
        )
        let result = try mapDocument(doc)
        let session = try TimetableImportSession(result: result, imagesData: [])
        XCTAssertEqual(session.timetable.orderedDays.count, 1)

        let reviewed = session.reviewedDraft()
        XCTAssertEqual(reviewed.days.count, 1)
        XCTAssertEqual(reviewed.days[0].stages.count, 2)
        XCTAssertEqual(reviewed.days[0].stages.map(\.sortOrder), [0, 1])
    }

    // MARK: - Helpers

    private func makeDate(
        year: Int = 2026,
        month: Int = 10,
        day: Int = 17,
        hour: Int = 0,
        minute: Int = 0,
        timeZone: String = "Asia/Shanghai"
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func mapDocument(
        _ document: TimetableExchangeDocument,
        defaultTimeZone: String = "Asia/Shanghai",
        fallbackDate: Date? = nil
    ) throws -> TimetableImportResult {
        let fallback = fallbackDate ?? makeDate(year: 2026, month: 10, day: 17, hour: 12, minute: 0)
        return try TimetableImportMapper.result(
            from: document,
            defaultTimeZoneIdentifier: defaultTimeZone,
            fallbackDate: fallback,
            unnamedStage: { "舞台 \($0)" }
        )
    }

    private func loadPrompt(for locale: String) -> String {
        if let path = Bundle(for: Timetable.self).path(forResource: locale, ofType: "lproj"),
           let tablePath = Bundle(path: path)?.path(forResource: "TimetableImport", ofType: "strings"),
           let table = NSDictionary(contentsOfFile: tablePath) as? [String: String],
           let text = table["recognitionPrompt"] {
            return text
        }
        if let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
           let tablePath = Bundle(path: path)?.path(forResource: "TimetableImport", ofType: "strings"),
           let table = NSDictionary(contentsOfFile: tablePath) as? [String: String],
           let text = table["recognitionPrompt"] {
            return text
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BeforeShow")
        let fileURL = root.appendingPathComponent("Resources/\(locale).lproj/TimetableImport.strings")
        if let data = try? Data(contentsOf: fileURL),
           let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String],
           let text = table["recognitionPrompt"] {
            return text
        }
        XCTFail("Could not load prompt for \(locale)")
        return ""
    }
}
