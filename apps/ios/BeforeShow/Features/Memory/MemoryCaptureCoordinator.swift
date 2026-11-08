import AVFoundation
import Foundation
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI

/// Every photo, video or line is saved as its own memory the moment it is taken or picked.
@MainActor
enum MemoryCaptureCoordinator {
    static func saveCameraPhoto(_ data: Data, to show: Show, in context: ModelContext, now: Date = Date()) async throws {
        let draftID = UUID()
        do {
            let staged = try await MemoryFragmentMediaStore.shared.stageCameraPhoto(data, draftID: draftID)
            try await create(staged, draftID: draftID, show: show, context: context, at: now)
        } catch {
            try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
            throw error
        }
    }

    /// Returns how many items were saved; a picked photo keeps the time it was taken when that falls near the show.
    static func saveLibraryItems(_ items: [PhotosPickerItem], to show: Show, in context: ModelContext, now: Date = Date()) async -> Int {
        var saved = 0
        for (index, item) in items.enumerated() {
            let draftID = UUID()
            do {
                guard let imported = try await item.loadTransferable(type: MemoryImportedFile.self) else { continue }
                let staged = try await MemoryFragmentMediaStore.shared.stageTransferredFile(imported, draftID: draftID)
                let url = MemoryMediaLocation.applicationSupport().url(for: staged.stagedRelativePath)
                let taken = await MemoryCaptureDate.date(of: url, kind: staged.kind)
                let date = MemoryCaptureDate.accepted(taken, showStart: show.startTime, now: now) ?? now.addingTimeInterval(Double(index) * 0.001)
                try await create(staged, draftID: draftID, show: show, context: context, at: date)
                saved += 1
            } catch {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
            }
        }
        return saved
    }

    static func saveText(_ text: String, to show: Show, in context: ModelContext, now: Date = Date()) async throws {
        let fragment = try await MemoryFragmentCreationCoordinator.create(
            showID: show.id, draftID: UUID(), media: [], caption: text, modelContext: context, now: now
        )
        ProductAnalytics.capture(.memoryFragmentCreated(showID: show.id, mediaCount: 0, phase: fragment.phase))
    }

    private static func create(_ staged: MemoryDraftMedia, draftID: UUID, show: Show, context: ModelContext, at date: Date) async throws {
        let fragment = try await MemoryFragmentCreationCoordinator.create(
            showID: show.id, draftID: draftID, media: [staged], caption: "", modelContext: context, now: date
        )
        ProductAnalytics.capture(.memoryFragmentCreated(showID: show.id, mediaCount: 1, phase: fragment.phase))
    }
}

enum MemoryCaptureDate {
    /// The capture time is trusted only within three days of the show and never in the future.
    static func accepted(_ date: Date?, showStart: Date, now: Date) -> Date? {
        guard let date, date <= now, abs(date.timeIntervalSince(showStart)) <= 3 * 86_400 else { return nil }
        return date
    }

    static func date(of url: URL, kind: MemoryMediaKind) async -> Date? {
        switch kind {
        case .photo:
            return photoDate(url)
        case .video:
            return try? await AVURLAsset(url: url).load(.creationDate)?.load(.dateValue)
        }
    }

    static func photoDate(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return exifDate(original, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
    }

    static func exifDate(_ value: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXX"
            return formatter.date(from: value + offset)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: value)
    }
}
