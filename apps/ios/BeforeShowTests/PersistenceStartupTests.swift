import SwiftData
import UIKit
import XCTest
@testable import BeforeShow

@MainActor
final class PersistenceStartupTests: XCTestCase {
    func testBackgroundLaunchWithoutExecutionTimeDoesNotOpenStore() throws {
        var opened = false
        let startup = makeStartup(
            background: true,
            begin: { _ in .invalid },
            end: { _ in XCTFail("Invalid task must not be ended") },
            load: {
                opened = true
                return try ModelContainerFactory.make(isStoredInMemoryOnly: true)
            },
            prepare: { _ in XCTFail("Must not prepare") }
        )

        try startup.start()

        XCTAssertFalse(opened)
        XCTAssertNil(startup.container)
        XCTAssertTrue(startup.needsRetry)
    }

    func testForegroundLaunchStillOpensWhenBackgroundTimeIsUnavailable() throws {
        var events: [String] = []
        let startup = makeStartup(
            background: false,
            begin: { _ in events.append("begin"); return .invalid },
            end: { _ in XCTFail("Invalid task must not be ended") },
            load: { events.append("open"); return try ModelContainerFactory.make(isStoredInMemoryOnly: true) },
            prepare: { _ in events.append("prepare") }
        )

        try startup.start()

        XCTAssertEqual(events, ["begin", "open", "prepare"])
        XCTAssertNotNil(startup.container)
        XCTAssertFalse(startup.needsRetry)
    }

    func testProtectedOpenCoversPreparationAndEndsOnce() throws {
        var events: [String] = []
        let startup = makeStartup(
            background: true,
            begin: { _ in events.append("begin"); return UIBackgroundTaskIdentifier(rawValue: 42) },
            end: { XCTAssertEqual($0.rawValue, 42); events.append("end") },
            load: { events.append("open"); return try ModelContainerFactory.make(isStoredInMemoryOnly: true) },
            prepare: { _ in events.append("prepare") }
        )

        try startup.start()
        try startup.start()

        XCTAssertEqual(events, ["begin", "open", "prepare", "end"])
        XCTAssertNotNil(startup.container)
    }

    func testOpenFailureEndsProtectionAndPreservesError() {
        enum Failure: Error { case open }
        var ended = 0
        let startup = makeStartup(
            background: true,
            begin: { _ in UIBackgroundTaskIdentifier(rawValue: 42) },
            end: { _ in ended += 1 },
            load: { throw Failure.open },
            prepare: { _ in XCTFail("Must not prepare a failed store") }
        )

        do {
            try startup.start()
            XCTFail("Must propagate the storage error")
        } catch {
            XCTAssertTrue(error is Failure)
        }
        XCTAssertEqual(ended, 1)
        XCTAssertNil(startup.container)
        XCTAssertFalse(startup.needsRetry)
    }

    func testSynchronousExpirationOnBackgroundLaunchDoesNotOpenAndEndsTask() throws {
        var opened = false
        var ended: [Int] = []
        let startup = makeStartup(
            background: true,
            begin: { expiration in
                expiration()
                return UIBackgroundTaskIdentifier(rawValue: 9)
            },
            end: { ended.append($0.rawValue) },
            load: {
                opened = true
                return try ModelContainerFactory.make(isStoredInMemoryOnly: true)
            },
            prepare: { _ in XCTFail("Must not prepare after expiration") }
        )

        try startup.start()

        XCTAssertFalse(opened)
        XCTAssertEqual(ended, [9])
        XCTAssertTrue(startup.needsRetry)
        XCTAssertNil(startup.container)
    }

    private func makeStartup(
        background: Bool,
        begin: @escaping (@escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier,
        end: @escaping (UIBackgroundTaskIdentifier) -> Void,
        load: @escaping () throws -> ModelContainer,
        prepare: @escaping (ModelContainer) -> Void
    ) -> PersistenceStartup {
        PersistenceStartup(
            isBackgroundLaunch: { background },
            begin: begin,
            end: end,
            load: load,
            prepare: prepare
        )
    }
}
