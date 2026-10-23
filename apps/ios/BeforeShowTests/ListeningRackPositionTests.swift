import XCTest
import SwiftData
import SwiftUI
import UIKit
@testable import BeforeShow

@MainActor
final class ListeningRackPositionTests: XCTestCase {
    func testMountingRackRestoresExpandedArtistWithoutResettingSavedAlbum() async throws {
        let (container, show) = try ListenTestData.make()
        let context = container.mainContext
        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<ArtistCatalogSnapshot>())
            .first { $0.artistID == "a" })
        snapshot.albumIDs.append("second-album")
        context.insert(CatalogAlbum(
            appleMusicAlbumID: "second-album", title: "Second Album",
            artistIDs: ["a"], orderedTrackIDs: ["a1"]
        ))
        try context.save()
        let room = ListenTestData.room(context)
        await room.load(show: show)
        defer { room.stop(); room.mechanism.motion.stop() }
        let group = try XCTUnwrap(room.rackGroups.first { $0.scope == .artist("a") })
        XCTAssertGreaterThan(group.discs.count, 1)
        let saved = ListeningRackPosition(showID: show.id)
        saved.expandedGroupID = group.id
        saved.focusedID = "\(group.id)#1"
        defer {
            UserDefaults.standard.removeObject(forKey: "listening.rackPosition.\(show.id.uuidString)")
        }

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ListeningRackView(
            room: room, groups: room.rackGroups, scale: 1, onConnect: { _, _ in }
        ))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<20 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(room.browser.scope, .artist("a"))
        let restored = ListeningRackPosition(showID: show.id)
        XCTAssertEqual(restored.expandedGroupID, group.id)
        XCTAssertEqual(restored.focusedID, "\(group.id)#1")
    }

    func testShelfPositionSurvivesRecreationAndIsSeparateForEachShow() throws {
        let suite = "ListeningRackPositionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let showID = UUID()
        let position = ListeningRackPosition(showID: showID, defaults: defaults)
        XCTAssertNil(position.focusedID)
        XCTAssertNil(position.expandedGroupID)

        position.expandedGroupID = "artist-a"
        position.focusedID = "artist-a#3"

        let restored = ListeningRackPosition(
            showID: showID, defaults: try XCTUnwrap(UserDefaults(suiteName: suite))
        )
        XCTAssertEqual(restored.expandedGroupID, "artist-a")
        XCTAssertEqual(restored.focusedID, "artist-a#3")
        let otherShow = ListeningRackPosition(showID: UUID(), defaults: defaults)
        XCTAssertNil(otherShow.expandedGroupID)
        XCTAssertNil(otherShow.focusedID)

        restored.expandedGroupID = nil
        restored.focusedID = "artist-a#0"
        let collapsed = ListeningRackPosition(showID: showID, defaults: defaults)
        XCTAssertNil(collapsed.expandedGroupID)
        XCTAssertEqual(collapsed.focusedID, "artist-a#0")
    }
}
