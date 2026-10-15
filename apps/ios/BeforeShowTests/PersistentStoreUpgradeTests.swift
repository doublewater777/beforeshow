import Foundation
import SwiftData
import XCTest
@testable import BeforeShow

/// Shape of the retired 「想现场听」 model as shipped in 1.0.1–1.0.4 stores.
@Model
final class ShowWantsLiveSong {
    @Attribute(.unique) var uniqueKey: String
    var showID: UUID
    var songID: String
    var createdAt: Date

    init(showID: UUID, songID: String) {
        uniqueKey = "\(showID.uuidString)|\(songID)"
        self.showID = showID
        self.songID = songID
        createdAt = Date()
    }
}

@MainActor
final class PersistentStoreUpgradeTests: XCTestCase {
    func testStoreWithRetiredWantsLiveEntityOpensAndKeepsShows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("BeforeShow.store")
        let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)

        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let show = try Show(name: "Upgrade", date: start, startTime: start)
        let showID = show.id
        do {
            let legacy = try ModelContainer(
                for: Schema(ModelContainerFactory.models + [ShowWantsLiveSong.self]),
                configurations: configuration
            )
            legacy.mainContext.insert(show)
            legacy.mainContext.insert(ShowWantsLiveSong(showID: showID, songID: "song"))
            try legacy.mainContext.save()
        }

        let upgraded = try ModelContainerFactory.make(configuration: configuration)
        let shows = try upgraded.mainContext.fetch(FetchDescriptor<Show>())
        XCTAssertEqual(shows.map(\.id), [showID])
        XCTAssertEqual(shows.first?.name, "Upgrade")
        XCTAssertNil(upgraded.schema.entitiesByName["ShowWantsLiveSong"])
    }
}
