import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class TimetableManagementCoordinator: ObservableObject {
    @Published var isRecognizing = false
    @Published var recognitionError: String?
    @Published var draft: TimetableDraft?
    @Published var isSaving = false
    @Published var toast: BSToastPayload?

    private let recognizer: TimetableImageRecognizer

    init(timeZoneIdentifier: String = "Asia/Shanghai") {
        self.recognizer = TimetableImageRecognizer(timeZoneIdentifier: timeZoneIdentifier)
    }

    func recognize(images: [UIImage], show: Show) async {
        draft = nil
        guard !images.isEmpty else { return }
        isRecognizing = true
        recognitionError = nil

        do {
            let parsedDraft = try await recognizer.recognize(
                images: images,
                defaultYear: Calendar.current.component(.year, from: show.date),
                defaultDate: show.date
            )
            self.draft = parsedDraft
            self.isRecognizing = false
        } catch let err as TimetableRecognitionError {
            self.isRecognizing = false
            switch err {
            case .missingImageData:
                self.recognitionError = BSLocalization.text("未读取到有效图片")
            case .noTimetableFound, .recognitionFailed:
                self.recognitionError = BSLocalization.text("未在图片中识别到演出时刻表，请确保图片清晰或手动重试")
            }
        } catch {
            self.isRecognizing = false
            self.recognitionError = BSLocalization.text("识别时刻表失败，原图已保留")
        }
    }

    func recognizeFromExistingAssets(assets: [ShowAsset], show: Show) async {
        draft = nil
        let timetableAssets = assets.filter { $0.kind == .timetable }
        guard !timetableAssets.isEmpty else { return }
        isRecognizing = true
        recognitionError = nil

        var loadedImages: [UIImage] = []
        for asset in timetableAssets {
            if let url = try? await ShowAssetMediaStore.shared.absoluteURL(
                for: asset.relativePath,
                showID: show.id,
                kind: .timetable
            ), let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                loadedImages.append(img)
            }
        }

        guard !loadedImages.isEmpty else {
            isRecognizing = false
            recognitionError = BSLocalization.text("未能读取已保存的原图")
            return
        }

        await recognize(images: loadedImages, show: show)
    }

    func commit(
        draft: TimetableDraft,
        newImagesData: [Data],
        show: Show,
        modelContext: ModelContext
    ) async -> Bool {
        isSaving = true
        await ShowAssetMediaStore.shared.acquireCommitGate()
        var newAssets: [(id: UUID, path: String)] = []
        do {
            let newTimetable = try draft.buildTimetable()

            // Stage every new image before touching the saved timetable or originals.
            for data in newImagesData {
                let assetID = UUID()
                let path = try await ShowAssetMediaStore.shared.saveImage(
                    data: data,
                    showID: show.id,
                    kind: .timetable,
                    assetID: assetID
                )
                newAssets.append((assetID, path))
            }
            let oldAssets = newImagesData.isEmpty ? [] : show.assets.filter { $0.kind == .timetable }
            let oldPaths = oldAssets.map(\.relativePath)

            if let oldTimetable = show.timetable {
                modelContext.delete(oldTimetable)
                show.timetable = nil
            }

            show.timetable = newTimetable
            modelContext.insert(newTimetable)

            for old in oldAssets {
                modelContext.delete(old)
            }
            for candidate in newAssets {
                let asset = ShowAsset(
                    id: candidate.id,
                    showID: show.id,
                    kind: .timetable,
                    relativePath: candidate.path
                )
                asset.show = show
                modelContext.insert(asset)
            }

            try modelContext.save()
            await deleteImages(oldPaths, showID: show.id)
            await ShowAssetMediaStore.shared.releaseCommitGate()
            self.draft = nil
            self.isSaving = false
            presentToast(.success, message: BSLocalization.text("时刻表已保存"))
            return true
        } catch {
            modelContext.rollback()
            await deleteImages(newAssets.map(\.path), showID: show.id)
            await ShowAssetMediaStore.shared.releaseCommitGate()
            self.isSaving = false
            presentToast(.failure, message: BSLocalization.text("时刻表保存失败，请重试"))
            return false
        }
    }

    func deleteTimetable(show: Show, modelContext: ModelContext) async {
        await ShowAssetMediaStore.shared.acquireCommitGate()
        do {
            if let tt = show.timetable {
                modelContext.delete(tt)
                show.timetable = nil
            }
            let oldAssets = show.assets.filter { $0.kind == .timetable }
            let oldPaths = oldAssets.map(\.relativePath)
            for old in oldAssets {
                modelContext.delete(old)
            }
            try modelContext.save()
            await deleteImages(oldPaths, showID: show.id)
            await ShowAssetMediaStore.shared.releaseCommitGate()
            presentToast(.success, message: BSLocalization.text("时刻表已删除"))
        } catch {
            modelContext.rollback()
            await ShowAssetMediaStore.shared.releaseCommitGate()
            presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
        }
    }

    private func deleteImages(_ paths: [String], showID: UUID) async {
        for path in paths {
            do {
                try await ShowAssetMediaStore.shared.delete(relativePath: path, showID: showID, kind: .timetable)
            } catch {
                ShowAssetCleanupRetry.markAssetCleanupPending(showID: showID, kind: .timetable, relativePath: path)
            }
        }
    }

    func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        self.toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self.toast == payload {
                self.toast = nil
            }
        }
    }
}
