import XCTest
import AVFoundation
import SwiftData
@testable import BeforeShow

final class DynamicCoverTests: XCTestCase {
    func testDynamicFaceStorePersistsPerShowAndClears() {
        let defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        let first = UUID()
        let second = UUID()

        DynamicCoverFaceStore.setDynamicFace(true, for: first, defaults: defaults)
        XCTAssertTrue(DynamicCoverFaceStore.isDynamicFace(for: first, defaults: defaults))
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: second, defaults: defaults))

        DynamicCoverFaceStore.clear(showID: first, defaults: defaults)
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: first, defaults: defaults))
        defaults.removePersistentDomain(forName: #file)
    }

    func testDynamicFaceStoreClearsAllShowPreferences() {
        let suiteName = #file + ".clear-all"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let first = UUID()
        let second = UUID()

        DynamicCoverFaceStore.setDynamicFace(true, for: first, defaults: defaults)
        DynamicCoverFaceStore.setDynamicFace(false, for: second, defaults: defaults)
        defaults.set(true, forKey: "unrelated-setting")

        DynamicCoverFaceStore.clearAll(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "dynamic-cover-face-v1-\(first.uuidString)"))
        XCTAssertNil(defaults.object(forKey: "dynamic-cover-face-v1-\(second.uuidString)"))
        XCTAssertTrue(defaults.bool(forKey: "unrelated-setting"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDynamicCoverAccessibilityOnlyExposesAddActionWhenAvailable() {
        XCTAssertTrue(
            DynamicCoverAccessibilityPolicy.shouldExposeAddVideoAction(
                hasDynamicCover: false,
                hasChooseVideoAction: true
            )
        )
        XCTAssertFalse(
            DynamicCoverAccessibilityPolicy.shouldExposeAddVideoAction(
                hasDynamicCover: true,
                hasChooseVideoAction: true
            )
        )
        XCTAssertFalse(
            DynamicCoverAccessibilityPolicy.shouldExposeAddVideoAction(
                hasDynamicCover: false,
                hasChooseVideoAction: false
            )
        )
    }

    func testDynamicCoverAccessibilityOnlyExposesFaceActionsWhenFlipIsAvailable() {
        XCTAssertTrue(DynamicCoverAccessibilityPolicy.shouldExposeFaceActions(canFlip: true))
        XCTAssertFalse(DynamicCoverAccessibilityPolicy.shouldExposeFaceActions(canFlip: false))
    }

    func testDynamicCoverHintDescribesDetailTapAndFlip() {
        XCTAssertEqual(
            DynamicCoverAccessibilityPolicy.hint(canFlip: true, opensDetail: true),
            "轻点查看现场详情，长按翻转动态封面"
        )
        XCTAssertEqual(
            DynamicCoverAccessibilityPolicy.hint(canFlip: false, opensDetail: true),
            "轻点查看现场详情"
        )
        XCTAssertEqual(
            DynamicCoverAccessibilityPolicy.hint(canFlip: true, opensDetail: false),
            "长按翻转动态封面，轻点返回静态封面"
        )
        XCTAssertEqual(
            DynamicCoverAccessibilityPolicy.hint(canFlip: false, opensDetail: false),
            "暂无动态封面"
        )
    }

    func testDynamicCoverErrorsUseActionablePickerMessages() {
        XCTAssertEqual(
            DynamicCoverErrorMessagePolicy.message(for: .invalidDuration),
            "视频不能超过 15 秒。"
        )
        XCTAssertEqual(
            DynamicCoverErrorMessagePolicy.message(for: .fileTooLarge),
            "视频太大，最多支持 100 MB。"
        )
        XCTAssertEqual(
            DynamicCoverErrorMessagePolicy.message(for: .unsupportedVideo),
            "这个文件不是可用的视频。"
        )
    }

    func testFootprintPlaybackPolicyStopsForAnyOverlayOrInactiveScene() {
        XCTAssertTrue(
            FootprintPlaybackPolicy.isActive(
                sceneIsActive: true,
                hasMemoryOverlay: false,
                hasAssetOverlay: false,
                hasShareOverlay: false
            )
        )
        XCTAssertFalse(
            FootprintPlaybackPolicy.isActive(
                sceneIsActive: false,
                hasMemoryOverlay: false,
                hasAssetOverlay: false,
                hasShareOverlay: false
            )
        )
        XCTAssertFalse(
            FootprintPlaybackPolicy.isActive(
                sceneIsActive: true,
                hasMemoryOverlay: true,
                hasAssetOverlay: false,
                hasShareOverlay: false
            )
        )
        XCTAssertFalse(
            FootprintPlaybackPolicy.isActive(
                sceneIsActive: true,
                hasMemoryOverlay: false,
                hasAssetOverlay: true,
                hasShareOverlay: false
            )
        )
        XCTAssertFalse(
            FootprintPlaybackPolicy.isActive(
                sceneIsActive: true,
                hasMemoryOverlay: false,
                hasAssetOverlay: false,
                hasShareOverlay: true
            )
        )
    }

    func testCurrentShowPlaybackPolicyRequiresForegroundWithoutOverlay() {
        XCTAssertTrue(
            CurrentShowPlaybackPolicy.isActive(
                baseIsActive: true,
                sceneIsActive: true,
                hasOverlay: false
            )
        )
        XCTAssertFalse(
            CurrentShowPlaybackPolicy.isActive(
                baseIsActive: false,
                sceneIsActive: true,
                hasOverlay: false
            )
        )
        XCTAssertFalse(
            CurrentShowPlaybackPolicy.isActive(
                baseIsActive: true,
                sceneIsActive: false,
                hasOverlay: false
            )
        )
        XCTAssertFalse(
            CurrentShowPlaybackPolicy.isActive(
                baseIsActive: true,
                sceneIsActive: true,
                hasOverlay: true
            )
        )
    }

    func testDynamicCoverPathStaysBoundToShowDirectory() {
        let showID = UUID()
        XCTAssertTrue(DynamicCover.isValidRelativePath("\(showID.uuidString)/video.mov", showID: showID))
        XCTAssertFalse(DynamicCover.isValidRelativePath("other/video.mov", showID: showID))
        XCTAssertFalse(DynamicCover.isValidRelativePath("\(showID.uuidString)/../video.mov", showID: showID))
    }

    func testDynamicCoverStagingCleanupRemovesOnlyExpiredDrafts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicCoverTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DynamicCoverMediaStore(location: DynamicCoverMediaLocation(rootDirectory: root))
        let staleDraft = root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        let freshDraft = root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staleDraft, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: freshDraft, withIntermediateDirectories: true)
        try Data([1]).write(to: staleDraft.appendingPathComponent("stale.mov"))
        try Data([1]).write(to: freshDraft.appendingPathComponent("fresh.mov"))
        let staleDate = Date().addingTimeInterval(-86_401)
        try FileManager.default.setAttributes(
            [.modificationDate: staleDate],
            ofItemAtPath: staleDraft.path
        )

        try await store.cleanupStaging(olderThan: Date().addingTimeInterval(-86_400))

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDraft.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshDraft.path))
    }

    @MainActor
    func testDynamicCoverScanKeepsMissingRootOutOfModelReconciliation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicCoverMissingRoot-\(UUID().uuidString)", isDirectory: true)
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let show = try Show(name: "动态封面", date: Date(), startTime: Date())
        let cover = DynamicCover(
            showID: show.id,
            relativePath: "\(show.id.uuidString)/clip.mov",
            contentTypeIdentifier: "public.movie",
            videoDuration: 1
        )
        cover.show = show
        show.dynamicCover = cover
        context.insert(show)
        context.insert(cover)
        try context.save()

        let store = DynamicCoverMediaStore(
            location: DynamicCoverMediaLocation(rootDirectory: root)
        )

        do {
            let existingPaths = try await store.verifiedExistingRelativePaths()
            _ = try reconcileDynamicCoverModelBoundary(
                in: context,
                existingRelativePaths: existingPaths
            )
            XCTFail("A missing media root must not be treated as an authoritative empty set")
        } catch {
            XCTAssertEqual(error as? DynamicCoverMediaStoreError, .storageUnavailable)
        }

        let fetchedCovers = try context.fetch(FetchDescriptor<DynamicCover>())
        XCTAssertEqual(fetchedCovers.count, 1)
        XCTAssertEqual(show.dynamicCover?.id, cover.id)
    }

    func testDynamicCoverRelativePathResolvesAliasedRoot() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicCoverAlias-\(UUID().uuidString)", isDirectory: true)
        let realRoot = parent.appendingPathComponent("real/DynamicCovers", isDirectory: true)
        let aliasedRoot = parent.appendingPathComponent("DynamicCoversAlias", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasedRoot, withDestinationURL: realRoot)

        let showID = UUID()
        let relativePath = "\(showID.uuidString)/clip.mov"
        let realFile = realRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: realFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01]).write(to: realFile)

        XCTAssertEqual(
            try DynamicCoverMediaStore.relativePath(for: realFile, under: aliasedRoot),
            relativePath
        )
    }

    @MainActor
    func testDynamicCoverPersistsAcrossDiskStoreRestart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicCoverRestart-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("dynamic-cover.store")
        let mediaRoot = root.appendingPathComponent("DynamicCovers", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let showID: UUID
        let expectedVideoPath: String
        let expectedPosterPath: String

        do {
            let container = try ModelContainer(
                for: Show.self, DynamicCover.self,
                configurations: ModelConfiguration(url: databaseURL, cloudKitDatabase: .none)
            )
            let context = container.mainContext
            let show = try Show(name: "重启动态封面", date: Date(), startTime: Date())
            showID = show.id
            context.insert(show)

            let store = DynamicCoverMediaStore(
                location: DynamicCoverMediaLocation(rootDirectory: mediaRoot)
            )
            let committed = try await Self.commitTestVideo(store: store, root: mediaRoot, showID: show.id)
            expectedVideoPath = committed.relativePath
            expectedPosterPath = try XCTUnwrap(committed.posterRelativePath)

            let cover = DynamicCover(
                id: committed.id,
                showID: show.id,
                relativePath: committed.relativePath,
                posterRelativePath: committed.posterRelativePath,
                contentTypeIdentifier: committed.contentTypeIdentifier,
                videoDuration: committed.videoDuration
            )
            cover.show = show
            show.dynamicCover = cover
            context.insert(cover)
            try context.save()
        }

        do {
            let container = try ModelContainer(
                for: Show.self, DynamicCover.self,
                configurations: ModelConfiguration(url: databaseURL, cloudKitDatabase: .none)
            )
            let context = container.mainContext
            let store = DynamicCoverMediaStore(
                location: DynamicCoverMediaLocation(rootDirectory: mediaRoot)
            )
            let existingPaths = try await store.verifiedExistingRelativePaths()
            XCTAssertEqual(existingPaths, Set([expectedVideoPath, expectedPosterPath]))

            let validPaths = try reconcileDynamicCoverModelBoundary(
                in: context,
                existingRelativePaths: existingPaths
            )
            XCTAssertEqual(validPaths, Set([expectedVideoPath, expectedPosterPath]))

            let shows = try context.fetch(FetchDescriptor<Show>())
            let covers = try context.fetch(FetchDescriptor<DynamicCover>())
            XCTAssertEqual(shows.map(\.id), [showID])
            XCTAssertEqual(covers.count, 1)
            XCTAssertEqual(covers.first?.relativePath, expectedVideoPath)
            XCTAssertEqual(shows.first?.dynamicCover?.relativePath, expectedVideoPath)
        }
    }

    @MainActor
    func testFullCleanupRetryKeepsMarkerUntilBothMediaStoresSucceed() async {
        ShowAssetCleanupRetry.clearFullCleanupPending()
        ShowAssetCleanupRetry.markFullCleanupPending()
        defer { ShowAssetCleanupRetry.clearFullCleanupPending() }

        var showAssetAttempts = 0
        var dynamicCoverAttempts = 0
        await retryPendingFullCleanup(
            deleteShowAssets: {
                showAssetAttempts += 1
            },
            deleteDynamicCovers: {
                dynamicCoverAttempts += 1
                throw DynamicCoverMediaStoreError.storageUnavailable
            }
        )

        XCTAssertEqual(showAssetAttempts, 1)
        XCTAssertEqual(dynamicCoverAttempts, 1)
        XCTAssertTrue(ShowAssetCleanupRetry.isFullCleanupPending)

        await retryPendingFullCleanup(
            deleteShowAssets: {
                showAssetAttempts += 1
            },
            deleteDynamicCovers: {
                dynamicCoverAttempts += 1
            }
        )

        XCTAssertEqual(showAssetAttempts, 2)
        XCTAssertEqual(dynamicCoverAttempts, 2)
        XCTAssertFalse(ShowAssetCleanupRetry.isFullCleanupPending)
    }

    @MainActor
    func testReconcileMissingCurrentCoverClearsFacePreference() throws {
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let show = try Show(name: "失效动态封面", date: Date(), startTime: Date())
        let cover = DynamicCover(
            showID: show.id,
            relativePath: "\(show.id.uuidString)/missing.mov",
            contentTypeIdentifier: "public.movie",
            videoDuration: 1
        )
        cover.show = show
        show.dynamicCover = cover
        container.mainContext.insert(show)
        container.mainContext.insert(cover)
        try container.mainContext.save()

        DynamicCoverFaceStore.setDynamicFace(true, for: show.id)
        _ = try reconcileDynamicCoverModelBoundary(
            in: container.mainContext,
            existingRelativePaths: []
        )

        XCTAssertNil(show.dynamicCover)
        XCTAssertFalse(DynamicCoverFaceStore.isDynamicFace(for: show.id))
    }

    func testReplaceVideoUpdatesPosterRelativePath() {
        let showID = UUID()
        let cover = DynamicCover(
            showID: showID,
            relativePath: "\(showID.uuidString)/a.mov",
            contentTypeIdentifier: "public.movie",
            videoDuration: 1
        )

        cover.replaceVideo(
            relativePath: "\(showID.uuidString)/b.mov",
            posterRelativePath: "\(showID.uuidString)/b-poster.jpg",
            contentTypeIdentifier: "public.movie",
            videoDuration: 2
        )

        XCTAssertEqual(cover.relativePath, "\(showID.uuidString)/b.mov")
        XCTAssertEqual(cover.posterRelativePath, "\(showID.uuidString)/b-poster.jpg")
    }

    func testCommitWritesPosterFrameNextToVideo() async throws {
        let (root, store) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let showID = UUID()

        let committed = try await Self.commitTestVideo(store: store, root: root, showID: showID)

        XCTAssertEqual(committed.relativePath, "\(showID.uuidString)/clip.mov")
        let posterPath = try XCTUnwrap(committed.posterRelativePath)
        XCTAssertEqual(posterPath, "\(showID.uuidString)/clip-poster.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed.relativePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(posterPath).path))
    }

    func testDeleteRemovesPosterAlongsideVideo() async throws {
        let (root, store) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let showID = UUID()
        let committed = try await Self.commitTestVideo(store: store, root: root, showID: showID)
        let posterPath = try XCTUnwrap(committed.posterRelativePath)

        try await store.delete(relativePath: committed.relativePath, showID: showID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed.relativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(posterPath).path))
    }

    func testRollbackRemovesPosterAlongsideVideo() async throws {
        let (root, store) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let showID = UUID()
        let committed = try await Self.commitTestVideo(store: store, root: root, showID: showID)
        let posterPath = try XCTUnwrap(committed.posterRelativePath)

        try await store.rollbackCommittedFile(relativePath: committed.relativePath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed.relativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(posterPath).path))
    }

    func testReconcileKeepsPosterInsideValidSet() async throws {
        let (root, store) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let showID = UUID()
        let committed = try await Self.commitTestVideo(store: store, root: root, showID: showID)
        let posterPath = try XCTUnwrap(committed.posterRelativePath)

        try await store.reconcile(validRelativePaths: [committed.relativePath, posterPath])

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(posterPath).path))

        try await store.reconcile(validRelativePaths: [committed.relativePath])

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(committed.relativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(posterPath).path))
    }

    @MainActor
    func testReconcileBoundaryCountsPosterAsValidPath() throws {
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let show = try Show(name: "带海报", date: Date(), startTime: Date())
        let videoPath = "\(show.id.uuidString)/clip.mov"
        let posterPath = "\(show.id.uuidString)/clip-poster.jpg"
        let cover = DynamicCover(
            showID: show.id,
            relativePath: videoPath,
            posterRelativePath: posterPath,
            contentTypeIdentifier: "public.movie",
            videoDuration: 1
        )
        cover.show = show
        show.dynamicCover = cover
        container.mainContext.insert(show)
        container.mainContext.insert(cover)
        try container.mainContext.save()

        let validPaths = try reconcileDynamicCoverModelBoundary(
            in: container.mainContext,
            existingRelativePaths: [videoPath, posterPath]
        )

        XCTAssertTrue(validPaths.contains(videoPath))
        XCTAssertTrue(validPaths.contains(posterPath))
        XCTAssertEqual(show.dynamicCover?.id, cover.id)
    }

    @MainActor
    func testReconcileClearsStalePosterPathWhenFileIsMissing() throws {
        let container = try ModelContainer(
            for: Show.self, DynamicCover.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let show = try Show(name: "海报已丢", date: Date(), startTime: Date())
        let videoPath = "\(show.id.uuidString)/clip.mov"
        let posterPath = "\(show.id.uuidString)/clip-poster.jpg"
        let cover = DynamicCover(
            showID: show.id,
            relativePath: videoPath,
            posterRelativePath: posterPath,
            contentTypeIdentifier: "public.movie",
            videoDuration: 1
        )
        cover.show = show
        show.dynamicCover = cover
        container.mainContext.insert(show)
        container.mainContext.insert(cover)
        try container.mainContext.save()

        let validPaths = try reconcileDynamicCoverModelBoundary(
            in: container.mainContext,
            existingRelativePaths: [videoPath]
        )

        XCTAssertTrue(validPaths.contains(videoPath))
        XCTAssertFalse(validPaths.contains(posterPath))
        XCTAssertNil(show.dynamicCover?.posterRelativePath)
    }

    private func makeTempStore() -> (URL, DynamicCoverMediaStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicCoverTests-\(UUID().uuidString)", isDirectory: true)
        return (root, DynamicCoverMediaStore(location: DynamicCoverMediaLocation(rootDirectory: root)))
    }

    nonisolated private static func commitTestVideo(
        store: DynamicCoverMediaStore,
        root: URL,
        showID: UUID
    ) async throws -> DynamicCoverMediaCommittedVideo {
        let draftID = UUID()
        let stagingDirectory = root.appendingPathComponent("Staging/\(draftID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try await makeTestVideo(at: stagingDirectory.appendingPathComponent("clip.mov"))
        let staged = DynamicCoverMediaStagedVideo(
            id: UUID(),
            stagedRelativePath: "Staging/\(draftID.uuidString)/clip.mov",
            contentTypeIdentifier: "public.movie",
            videoDuration: 0.5
        )
        return try await store.commit(draftID: draftID, showID: showID, video: staged)
    }

    nonisolated private static func makeTestVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer)
        let pixelBuffer = try XCTUnwrap(buffer)
        adaptor.append(pixelBuffer, withPresentationTime: .zero)
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: 0.5, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }
}
