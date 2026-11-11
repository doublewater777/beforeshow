import XCTest
@testable import BeforeShow

@MainActor
final class MediaBackupInclusionTests: XCTestCase {
    func testPicturesKeptOutOfBackupsBeforeAreLetBackInOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaBackup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("show/ticket/a.jpg")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)
        for var url in [root, file] {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MediaBackupInclusionTests-\(UUID().uuidString)"))

        await MediaBackupInclusion.includeIfNeeded(defaults: defaults, roots: [root, root.appendingPathComponent("missing")])

        for url in [root, file] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
        }
        XCTAssertTrue(defaults.bool(forKey: MediaBackupInclusion.completedKey))
    }
}
