import AVFoundation
import SwiftData
import XCTest
@testable import BeforeShow

@MainActor
final class ShowFragmentTests: XCTestCase {
    func testFragmentBelongsToExactlyOneShowAndIsStoredInCreationOrder() throws {
        let show = try makeShow(name: "当前现场")
        let later = try ShowFragment(
            show: show,
            text: "散场后",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let earlier = try ShowFragment(
            show: show,
            text: "排队中",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let container = try makeContainer()
        container.mainContext.insert(show)
        container.mainContext.insert(later)
        container.mainContext.insert(earlier)
        try container.mainContext.save()

        let fragments = try container.mainContext.fetch(FetchDescriptor<ShowFragment>())

        XCTAssertEqual(ShowFragment.sortedByCreationTime(fragments).map(\.text), ["排队中", "散场后"])
        XCTAssertEqual(earlier.show.id, show.id)
        XCTAssertEqual(later.show.id, show.id)
    }

    func testFragmentCanReferenceMultipleGalleryAssetsWithoutCopyingOriginalMedia() throws {
        let show = try makeShow()
        let fragment = try ShowFragment(show: show, text: "朋友合照")

        let photo = fragment.addGalleryMediaReference(
            assetLocalIdentifier: "C9D9/photo",
            kind: .photo
        )
        let video = fragment.addGalleryMediaReference(
            assetLocalIdentifier: "A1B2/video",
            kind: .video
        )

        XCTAssertEqual(fragment.galleryMediaReferences.count, 2)
        XCTAssertEqual(photo.assetLocalIdentifier, "C9D9/photo")
        XCTAssertEqual(video.kind, .video)
        XCTAssertFalse(photo.assetLocalIdentifier.contains("/var/mobile/Containers"))
    }

    func testMissingGalleryOriginalsAreTrackedGracefully() throws {
        let show = try makeShow()
        let fragment = try ShowFragment(show: show)
        let available = fragment.addGalleryMediaReference(assetLocalIdentifier: "available", kind: .photo)
        let missing = fragment.addGalleryMediaReference(assetLocalIdentifier: "missing", kind: .video)
        let validator = ShowFragmentGalleryMediaReferenceValidator(
            resolver: StubGalleryResolver(availableIdentifiers: ["available"])
        )

        validator.validate([available, missing], now: Date(timeIntervalSince1970: 1_000))

        XCTAssertFalse(available.isMissing)
        XCTAssertTrue(missing.isMissing)
        XCTAssertEqual(missing.lastKnownMissingAt, Date(timeIntervalSince1970: 1_000))
    }

    func testFragmentCanHaveAtMostOneAppCreatedAudioReference() throws {
        let show = try makeShow()
        let fragment = try ShowFragment(show: show)

        let first = fragment.attachAudioReference(relativePath: "FragmentAudio/first.m4a")
        let second = fragment.attachAudioReference(relativePath: "FragmentAudio/second.m4a")

        XCTAssertEqual(fragment.audioReference?.id, second.id)
        XCTAssertNotEqual(fragment.audioReference?.id, first.id)
        XCTAssertEqual(fragment.audioReference?.relativePath, "FragmentAudio/second.m4a")
    }

    func testMovingFragmentChangesItsOnlyShowInsteadOfCopying() throws {
        let source = try makeShow(name: "原现场")
        let destination = try makeShow(name: "正确现场")
        let fragment = try ShowFragment(show: source, text: "挪到对的现场")

        try fragment.move(to: destination)

        XCTAssertEqual(fragment.show.id, destination.id)
        XCTAssertThrowsError(try fragment.move(to: destination)) { error in
            XCTAssertEqual(error as? ShowFragmentValidationError, .sameShowMove)
        }
    }

    func testDeletingFragmentRemovesAppCreatedAudioButLeavesGalleryReferenceOnly() throws {
        let show = try makeShow()
        let fragment = try ShowFragment(show: show)
        _ = fragment.addGalleryMediaReference(assetLocalIdentifier: "photo-local-id", kind: .photo)
        _ = fragment.attachAudioReference(relativePath: "FragmentAudio/audio.m4a")
        let deleter = RecordingAudioFileDeleter()
        let service = LocalAppDataDeletionService(
            audioStorage: ShowFragmentAudioStorage(rootDirectory: URL(fileURLWithPath: "/tmp/BeforeShowTests")),
            audioFileDeleter: deleter
        )
        let container = try makeContainer()
        container.mainContext.insert(show)
        container.mainContext.insert(fragment)

        try service.deleteFragment(fragment, in: container.mainContext)
        try container.mainContext.save()

        XCTAssertEqual(deleter.deletedURLs.map(\.lastPathComponent), ["audio.m4a"])
        let remainingFragments = try container.mainContext.fetch(FetchDescriptor<ShowFragment>())
        XCTAssertTrue(remainingFragments.isEmpty)
    }

    func testAudioWaveformSamplerReadsRealAudioIntoNormalizedBuckets() throws {
        let url = try makeSineWaveAudioFile()
        let samples = try AudioWaveformSampler().samples(from: url, bucketCount: 16)

        XCTAssertEqual(samples.count, 16)
        XCTAssertTrue(samples.allSatisfy { sample in sample >= 0 && sample <= 1 })
        XCTAssertGreaterThan(samples.max() ?? 0, 0.2)
        XCTAssertGreaterThan(Set(samples.map { Int(($0 * 100).rounded()) }).count, 1)
    }

    func testDeletingShowRemovesFragmentAudioForLocalDataClearSemantics() throws {
        let show = try makeShow()
        let first = try ShowFragment(show: show)
        _ = first.attachAudioReference(relativePath: "FragmentAudio/first.m4a")
        let second = try ShowFragment(show: show)
        _ = second.attachAudioReference(relativePath: "FragmentAudio/second.m4a")
        let deleter = RecordingAudioFileDeleter()
        let service = LocalAppDataDeletionService(
            audioStorage: ShowFragmentAudioStorage(rootDirectory: URL(fileURLWithPath: "/tmp/BeforeShowTests")),
            audioFileDeleter: deleter
        )
        let container = try makeContainer()
        container.mainContext.insert(show)
        container.mainContext.insert(first)
        container.mainContext.insert(second)

        try service.deleteShow(show, in: container.mainContext)
        try container.mainContext.save()

        XCTAssertEqual(Set(deleter.deletedURLs.map(\.lastPathComponent)), ["first.m4a", "second.m4a"])
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Show>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ShowFragment>()).isEmpty)
    }

    func testClearingLocalAppDataRemovesAppModelsAndAudioWithoutDeletingGalleryOriginals() throws {
        let show = try makeShow()
        let fragment = try ShowFragment(show: show)
        _ = fragment.addGalleryMediaReference(assetLocalIdentifier: "system-gallery-original", kind: .photo)
        _ = fragment.attachAudioReference(relativePath: "FragmentAudio/local-audio.m4a")
        let selection = CurrentShowSelection(selectedShowID: show.id)
        let roundTripPlan = RoundTripPlan(showID: show.id, outboundContent: "地铁")
        let preparationPlan = ShowPreparationPlan(showID: show.id, notes: "带耳塞")
        let candidateGroup = try CandidateSongGroup(showID: show.id, uncertaintyNote: "仅供参考")
        let candidateSong = try CandidateSong(
            groupID: candidateGroup.id,
            songName: "Song",
            artist: "Artist",
            order: 0
        )
        let artistInterest = try ArtistInterestItem(
            showID: show.id,
            artistName: "Artist",
            status: .wantToSee,
            order: 0
        )
        let deleter = RecordingAudioFileDeleter()
        let service = LocalAppDataDeletionService(
            audioStorage: ShowFragmentAudioStorage(rootDirectory: URL(fileURLWithPath: "/tmp/BeforeShowTests")),
            audioFileDeleter: deleter
        )
        let container = try makeContainer()
        container.mainContext.insert(show)
        container.mainContext.insert(fragment)
        container.mainContext.insert(selection)
        container.mainContext.insert(roundTripPlan)
        container.mainContext.insert(preparationPlan)
        container.mainContext.insert(candidateGroup)
        container.mainContext.insert(candidateSong)
        container.mainContext.insert(artistInterest)

        try service.clearLocalAppData(in: container.mainContext)
        try container.mainContext.save()

        XCTAssertEqual(deleter.deletedURLs.map(\.lastPathComponent), ["local-audio.m4a"])
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Show>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ShowFragment>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CurrentShowSelection>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<RoundTripPlan>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ShowPreparationPlan>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CandidateSongGroup>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CandidateSong>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<ArtistInterestItem>()).isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Show.self,
            ShowFragment.self,
            ShowFragmentGalleryMediaReference.self,
            ShowFragmentAudioReference.self,
            CurrentShowSelection.self,
            NotificationSchedulingState.self,
            ShowNotificationScheduleRecord.self,
            RoundTripPlan.self,
            ShowPreparationPlan.self,
            CandidateSongGroup.self,
            CandidateSong.self,
            ArtistInterestItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeShow(name: String = "测试现场") throws -> Show {
        try Show(name: name, date: Date(timeIntervalSince1970: 1_779_552_000), startTime: Date(), type: .concert)
    }

    private func makeSineWaveAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShowTests-\(UUID().uuidString).caf")
        let sampleRate: Double = 8_000
        let frameCount = AVAudioFrameCount(sampleRate * 0.2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let phase = Double(frame) / sampleRate * 440 * 2 * Double.pi
            channel[frame] = Float(sin(phase) * (Double(frame % 97) / 96.0))
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

private struct StubGalleryResolver: GalleryMediaAssetResolving {
    let availableIdentifiers: Set<String>

    func containsAsset(withLocalIdentifier localIdentifier: String) -> Bool {
        availableIdentifiers.contains(localIdentifier)
    }
}

private final class RecordingAudioFileDeleter: AudioFileDeleting {
    private(set) var deletedURLs: [URL] = []

    func deleteFileIfPresent(at url: URL) {
        deletedURLs.append(url)
    }
}
