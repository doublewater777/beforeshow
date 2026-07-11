import Foundation
import AVFoundation
import SwiftData

protocol GalleryMediaAssetResolving {
    func containsAsset(withLocalIdentifier localIdentifier: String) -> Bool
}

struct ShowFragmentGalleryMediaReferenceValidator {
    let resolver: GalleryMediaAssetResolving

    func validate(_ references: [ShowFragmentGalleryMediaReference], now: Date = Date()) {
        for reference in references {
            if resolver.containsAsset(withLocalIdentifier: reference.assetLocalIdentifier) {
                reference.markAvailable()
            } else {
                reference.markMissing(at: now)
            }
        }
    }
}

protocol AudioFileDeleting {
    func deleteFileIfPresent(at url: URL) throws
}

struct FileManagerAudioFileDeleter: AudioFileDeleting {
    var fileManager: FileManager = .default

    func deleteFileIfPresent(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

struct ShowFragmentAudioStorage {
    let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    func url(for reference: ShowFragmentAudioReference) -> URL {
        rootDirectory.appendingPathComponent(reference.relativePath, isDirectory: false)
    }

    func makeRelativePath(fragmentID: UUID, fileExtension: String = "m4a") -> String {
        "FragmentAudio/\(fragmentID.uuidString).\(fileExtension)"
    }

    static func applicationSupport(fileManager: FileManager = .default) -> ShowFragmentAudioStorage {
        let rootDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.temporaryDirectory
        return ShowFragmentAudioStorage(rootDirectory: rootDirectory)
    }
}

struct AudioWaveformSampler {
    func samples(from url: URL, bucketCount: Int = 24) throws -> [Double] {
        guard bucketCount > 0 else { return [] }

        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return Array(repeating: 0, count: bucketCount)
        }

        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return Array(repeating: 0, count: bucketCount)
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let framesPerBucket = max(1, Int(ceil(Double(frameCount) / Double(bucketCount))))
        var buckets = Array(repeating: 0.0, count: bucketCount)

        for bucketIndex in 0..<bucketCount {
            let startFrame = bucketIndex * framesPerBucket
            let endFrame = min(frameCount, startFrame + framesPerBucket)
            guard startFrame < endFrame else { continue }

            var total = 0.0
            var count = 0
            for frameIndex in startFrame..<endFrame {
                for channelIndex in 0..<channelCount {
                    total += Double(abs(channels[channelIndex][frameIndex]))
                    count += 1
                }
            }

            buckets[bucketIndex] = count > 0 ? total / Double(count) : 0
        }

        let peak = buckets.max() ?? 0
        guard peak > 0 else { return buckets }
        return buckets.map { min(1, $0 / peak) }
    }
}

@MainActor
struct LocalAppDataDeletionService {
    let audioStorage: ShowFragmentAudioStorage
    let audioFileDeleter: AudioFileDeleting

    init(
        audioStorage: ShowFragmentAudioStorage,
        audioFileDeleter: AudioFileDeleting = FileManagerAudioFileDeleter()
    ) {
        self.audioStorage = audioStorage
        self.audioFileDeleter = audioFileDeleter
    }

    func deleteFragment(_ fragment: ShowFragment, in context: ModelContext) throws {
        try deleteAudioIfNeeded(for: fragment)
        context.delete(fragment)
    }

    func deleteShow(_ show: Show, in context: ModelContext) throws {
        for fragment in show.fragments {
            try deleteAudioIfNeeded(for: fragment)
        }
        context.delete(show)
    }

    func clearLocalAppData(in context: ModelContext) throws {
        let fragments = try context.fetch(FetchDescriptor<ShowFragment>())
        for fragment in fragments {
            try deleteAudioIfNeeded(for: fragment)
            context.delete(fragment)
        }

        let shows = try context.fetch(FetchDescriptor<Show>())
        for show in shows {
            context.delete(show)
        }

        let selections = try context.fetch(FetchDescriptor<CurrentShowSelection>())
        for selection in selections {
            context.delete(selection)
        }

        let notificationStates = try context.fetch(FetchDescriptor<NotificationSchedulingState>())
        for notificationState in notificationStates {
            context.delete(notificationState)
        }

        let notificationRecords = try context.fetch(FetchDescriptor<ShowNotificationScheduleRecord>())
        for notificationRecord in notificationRecords {
            context.delete(notificationRecord)
        }

        let roundTripPlans = try context.fetch(FetchDescriptor<RoundTripPlan>())
        for roundTripPlan in roundTripPlans {
            context.delete(roundTripPlan)
        }

        let preparationPlans = try context.fetch(FetchDescriptor<ShowPreparationPlan>())
        for preparationPlan in preparationPlans {
            context.delete(preparationPlan)
        }

        let candidateSongGroups = try context.fetch(FetchDescriptor<CandidateSongGroup>())
        for candidateSongGroup in candidateSongGroups {
            context.delete(candidateSongGroup)
        }

        let candidateSongs = try context.fetch(FetchDescriptor<CandidateSong>())
        for candidateSong in candidateSongs {
            context.delete(candidateSong)
        }

        let artistInterests = try context.fetch(FetchDescriptor<ArtistInterestItem>())
        for artistInterest in artistInterests {
            context.delete(artistInterest)
        }

    }

    private func deleteAudioIfNeeded(for fragment: ShowFragment) throws {
        guard let audioReference = fragment.audioReference else { return }
        try audioFileDeleter.deleteFileIfPresent(at: audioStorage.url(for: audioReference))
    }
}
