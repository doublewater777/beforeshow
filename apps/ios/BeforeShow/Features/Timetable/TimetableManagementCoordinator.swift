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
    @Published var dayManagementError: String?
    @Published private(set) var importSession: TimetableImportSession?

    private let fallbackTimeZoneIdentifier: String

    init(timeZoneIdentifier: String = "Asia/Shanghai") {
        self.fallbackTimeZoneIdentifier = timeZoneIdentifier
    }

    /// The show's own zone when it has a valid one; times on a timetable are its local clock.
    private func timeZoneIdentifier(for show: Show) -> String {
        if let identifier = show.timeZoneIdentifier, TimeZone(identifier: identifier) != nil { return identifier }
        return fallbackTimeZoneIdentifier
    }

    func recognize(images: [UIImage], show: Show) async {
        draft = nil
        guard !images.isEmpty else { return }
        isRecognizing = true
        recognitionError = nil

        do {
            let recognizer = TimetableImageRecognizer(timeZoneIdentifier: timeZoneIdentifier(for: show))
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

    /// Saves original timetable photos locally without triggering recognition.
    func saveOriginalImages(
        imagesData: [Data],
        show: Show,
        modelContext: ModelContext
    ) async -> Bool {
        guard !imagesData.isEmpty else { return false }
        isSaving = true
        await ShowAssetMediaStore.shared.acquireCommitGate()
        var newAssets: [(id: UUID, path: String)] = []
        do {
            for data in imagesData {
                let assetID = UUID()
                let path = try await ShowAssetMediaStore.shared.saveImage(
                    data: data,
                    showID: show.id,
                    kind: .timetable,
                    assetID: assetID
                )
                newAssets.append((assetID, path))
            }
            let oldAssets = show.assets.filter { $0.kind == .timetable }
            let oldPaths = oldAssets.map(\.relativePath)
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
            self.isSaving = false
            presentToast(.success, message: BSLocalization.text("时刻表原图已保存"))
            return true
        } catch {
            modelContext.rollback()
            await deleteImages(newAssets.map(\.path), showID: show.id)
            await ShowAssetMediaStore.shared.releaseCommitGate()
            self.isSaving = false
            presentToast(.failure, message: BSLocalization.text("图片保存失败，请重试"))
            return false
        }
    }

    // MARK: - Import review

    /// Opens review for an import from any source. The saved timetable is only
    /// read here, to carry over choices for sets that match it exactly.
    @discardableResult
    func beginReview(
        _ result: TimetableImportResult,
        imagesData: [Data],
        show: Show,
        linker: TimetableArtistLinker
    ) -> TimetableImportSession? {
        var result = result
        if let saved = show.timetable {
            TimetableReimportCarryover.apply(from: TimetableDraft(from: saved), to: &result.draft)
        }
        linker.reuseKnownArtists(in: &result.draft)
        importSession = try? TimetableImportSession(result: result, imagesData: imagesData)
        if importSession != nil, result.skippedCount > 0 {
            presentToast(.neutral, message: BSLocalization.format("%d 场缺少艺人名，未导入", result.skippedCount))
        }
        return importSession
    }

    func reviewImportedText(_ text: String, show: Show, linker: TimetableArtistLinker) throws -> TimetableImportSession {
        let document = try TimetableImportParser.document(from: text)
        let result = try TimetableImportMapper.result(
            from: document,
            defaultTimeZoneIdentifier: timeZoneIdentifier(for: show),
            fallbackDate: show.date,
            unnamedStage: { BSLocalization.format("舞台 %d", $0) }
        )
        guard let session = beginReview(result, imagesData: [], show: show, linker: linker) else {
            throw TimetableImportError.invalidFormat
        }
        return session
    }

    func cancelReview() {
        importSession = nil
    }

    /// Writes the reviewed timetable over the saved one; on any failure the saved one stays.
    func saveReview(show: Show, modelContext: ModelContext) async -> Bool {
        guard let session = importSession, !isSaving else { return false }
        let draft = session.reviewedDraft()
        do {
            _ = try draft.buildTimetable()
        } catch let error as TimetableValidationError {
            presentToast(.failure, message: BSLocalization.text(TimetableReviewIssues.message(for: error)))
            return false
        } catch {
            return false
        }
        guard await commit(draft: draft, newImagesData: session.imagesData, show: show, modelContext: modelContext) else {
            return false
        }
        importSession = nil
        return true
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

    func updateDayDate(_ day: TimetableDay, to date: Date, in timetable: Timetable, context: ModelContext) {
        performDayChange(context: context) { try timetable.updateDayDate(day, to: date) }
    }

    func addDay(date: Date, to timetable: Timetable, template: TimetableDay?, context: ModelContext) -> TimetableDay? {
        var addedDay: TimetableDay?
        let saved = performDayChange(context: context) {
            let day = try timetable.addDay(
                date: date,
                stageNames: template?.orderedStages.map(\.name) ?? [BSLocalization.text("主舞台")]
            )
            context.insert(day)
            addedDay = day
        }
        return saved ? addedDay : nil
    }

    @discardableResult
    func deleteDay(_ day: TimetableDay, from timetable: Timetable, context: ModelContext) -> Bool {
        performDayChange(context: context) {
            try timetable.removeDay(day)
            context.delete(day)
        }
    }

    @discardableResult
    func addStage(named name: String, to day: TimetableDay, context: ModelContext) -> Bool {
        performDayChange(context: context) {
            let stage = try day.addStage(name: name)
            context.insert(stage)
        }
    }

    @discardableResult
    func renameStage(_ stage: TimetableStage, to name: String, context: ModelContext) -> Bool {
        performDayChange(context: context) { try stage.updateName(name) }
    }

    func reorderStages(of day: TimetableDay, to ids: [UUID], context: ModelContext) {
        performDayChange(context: context) { day.reorderStages(ids) }
    }

    @discardableResult
    func deleteStage(_ stage: TimetableStage, from day: TimetableDay, context: ModelContext) -> Bool {
        performDayChange(context: context) {
            try day.removeStage(stage)
            context.delete(stage)
        }
    }

    @discardableResult
    private func performDayChange(context: ModelContext, change: () throws -> Void) -> Bool {
        dayManagementError = nil
        var didChange = false
        do {
            try change()
            didChange = true
            try context.save()
            return true
        } catch {
            if didChange { context.rollback() }
            let message: String
            switch error as? TimetableValidationError {
            case .invalidDayDate: message = "该日期已有时刻表"
            case .emptyTimetable: message = "请至少保留一天"
            case .emptyDay: message = "请至少保留一个舞台"
            case .emptyStageName: message = "请输入舞台名称"
            case .overlappingDays: message = "结束时间与下一天的演出重叠"
            default: message = "修改失败，请重试"
            }
            dayManagementError = BSLocalization.text(message)
            return false
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
