import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum ShowAssetEditorOperation: Equatable {
    case idle
    case importing(UUID)
    case saving(UUID)

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }

    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }

    func canBeginImport() -> Bool {
        if case .saving = self { return false }
        return true
    }

    func canBeginSave(hasPendingData: Bool, saveTaskIsActive: Bool) -> Bool {
        self == .idle && hasPendingData && !saveTaskIsActive
    }
}

struct ShowAssetUploadView: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind
    var replacingAsset: ShowAsset? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var pendingData: Data?
    @State private var operation: ShowAssetEditorOperation = .idle
    @State private var importTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var toast: BSToastPayload?
    @State private var didSave = false
    @State private var isPhotoPickerPresented = false
    @State private var didAutoPresentPhotoPicker = false

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            if let previewImage {
                previewSection(previewImage)
            } else {
                emptyUploadSection
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: replacingAsset == nil ? nil : .infinity,
            alignment: .top
        )
        .navigationTitle(replacingAsset == nil ? "" : editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .bsToastOverlay(toast, bottomPadding: 36)
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedItem,
            matching: .images
        )
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            guard operation.canBeginImport() else { return }
            importTask?.cancel()
            let token = UUID()
            // Claim import ownership synchronously in the selection callback. The
            // async task must never be the first place that marks the editor busy:
            // otherwise Save can observe the previous image in the scheduling gap.
            operation = .importing(token)
            importTask = Task { await importItem(item, token: token) }
        }
        .onDisappear {
            importTask?.cancel()
            if !didSave {
                saveTask?.cancel()
            }
            // If user backs out after choosing a preview without saving, nothing was written.
            if !didSave {
                pendingData = nil
                previewImage = nil
            }
        }
        .task {
            guard replacingAsset != nil, !didAutoPresentPhotoPicker else { return }
            didAutoPresentPhotoPicker = true
            await Task.yield()
            isPhotoPickerPresented = true
        }
        .navigationBarBackButtonHidden(operation.isSaving)
        .interactiveDismissDisabled(operation.isSaving)
    }

    private var isImporting: Bool { operation.isImporting }
    private var isSaving: Bool { operation.isSaving }

    private var editorTitle: String {
        replacingAsset == nil ? kind.addTitle : BSLocalization.format("替换%@", kind.title)
    }

    private var editorDescription: String {
        replacingAsset == nil
            ? kind.addDescription
            : BSLocalization.format("选择一张新的%@，替换当前保存的图片。", kind.choosePrompt)
    }

    private var emptyUploadSection: some View {
        let importing = operation.isImporting

        return VStack(spacing: BSSpacing.lg) {
            BSStageSheetHeader(
                icon: kind.iconName,
                title: editorTitle,
                subtitle: editorDescription
            )

            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack(spacing: BSSpacing.sm) {
                    if importing {
                        ProgressView()
                            .tint(.black)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "photo")
                    }
                    Text(BSLocalization.text("选择图片"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isImporting || isSaving)
            .accessibilityLabel(BSLocalization.format("选择%@图片", kind.title))
            .accessibilityValue(importing ? BSLocalization.text("正在导入…") : "")
        }
        .frame(maxWidth: .infinity)
    }

    private func previewSection(_ image: UIImage) -> some View {
        let saveTitle = BSLocalization.format("保存%@", kind.title)
        return VStack(spacing: BSSpacing.md) {
            ZStack {
                Color.black.opacity(0.35)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: replacingAsset == nil ? 260 : 420)
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .overlay(
                RoundedRectangle(cornerRadius: 23)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("重新选择", systemImage: "photo")
                }
                .buttonStyle(BSSecondaryButtonStyle())
                .disabled(isSaving || isImporting)

                Button {
                    beginSave()
                } label: {
                    HStack(spacing: BSSpacing.sm) {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(saveTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BSPrimaryButtonStyle())
                .disabled(!operation.canBeginSave(
                    hasPendingData: pendingData != nil,
                    saveTaskIsActive: saveTask != nil
                ))
                .accessibilityLabel(saveTitle)
                .accessibilityValue(isSaving ? BSLocalization.text("正在保存") : "")
            }
        }
    }

    private func importItem(_ item: PhotosPickerItem, token: UUID) async {
        defer {
            if operation == .importing(token) {
                operation = .idle
                importTask = nil
            }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                guard operation == .importing(token) else { return }
                presentToast(.failure, message: BSLocalization.text("没有读到这张图片"))
                return
            }
            try Task.checkCancellation()
            guard operation == .importing(token) else { return }
            guard let image = UIImage(data: data) else {
                presentToast(.failure, message: BSLocalization.text("这张图片暂时无法使用"))
                return
            }
            pendingData = data
            previewImage = image
            selectedItem = nil
        } catch is CancellationError {
            return
        } catch {
            guard operation == .importing(token) else { return }
            presentToast(.failure, message: BSLocalization.text("图片读取失败，请重试"))
            selectedItem = nil
        }
    }

    private func savePending(data: Data, token: UUID) async {
        // Re-check ownership inside the task. Button disabled state is only a UI
        // affordance; this guard is the actual invariant against stale tasks.
        guard operation == .saving(token) else { return }
        defer {
            if operation == .saving(token) {
                operation = .idle
                saveTask = nil
            }
        }

        await ShowAssetMediaStore.shared.acquireCommitGate()
        var writtenRelativePath: String?
        do {
            try Task.checkCancellation()
            let currentShow = try modelContext.fetch(
                FetchDescriptor<Show>(predicate: #Predicate { $0.id == showID })
            ).first
            guard let currentShow else {
                throw ShowAssetMediaStoreError.missingShow
            }
            let currentAssets = assetsOfSameKind()
            // A replacement target is a compare-and-swap identity, not a hint
            // to replace whichever asset happens to exist now. Falling back to
            // currentAssets.first could let a stale editor overwrite a newer
            // ticket/timetable created by another scene.
            let existing = try ShowAssetReplacement.target(
                replacingAssetID: replacingAsset?.id,
                currentAssets: currentAssets
            )
            let previousRelativePath = existing?.relativePath
            let assetID = existing?.id ?? UUID()
            let relativePath = try await ShowAssetMediaStore.shared.saveImage(
                data: data,
                showID: showID,
                kind: kind,
                assetID: assetID
            )
            writtenRelativePath = relativePath
            try Task.checkCancellation()

            if let existing {
                existing.show = currentShow
                existing.replaceImage(relativePath: relativePath)
                for duplicate in assetsOfSameKind().filter({ $0.id != existing.id }) {
                    modelContext.delete(duplicate)
                }
            } else {
                let asset = ShowAsset(
                    id: assetID,
                    showID: showID,
                    kind: kind,
                    relativePath: relativePath
                )
                asset.show = currentShow
                modelContext.insert(asset)
            }

            try Task.checkCancellation()
            try modelContext.save()
            var cleanupPending = false
            if let previousRelativePath, previousRelativePath != relativePath {
                do {
                    try await ShowAssetMediaStore.shared.delete(
                        relativePath: previousRelativePath,
                        showID: showID,
                        kind: kind
                    )
                } catch {
                    cleanupPending = true
                }
            }
            if cleanupPending,
               let previousRelativePath,
               ShowAsset.isValidRelativePath(
                   previousRelativePath,
                   showID: showID,
                   kind: kind
               ) {
                ShowAssetCleanupRetry.markAssetCleanupPending(
                    showID: showID,
                    kind: kind,
                    relativePath: previousRelativePath
                )
            }
            await ShowAssetMediaStore.shared.releaseCommitGate()
            didSave = true
            presentToast(
                cleanupPending ? .neutral : .success,
                message: cleanupPending
                    ? BSLocalization.format("%@已保存，旧图片将在下次启动继续清理", kind.title)
                    : BSLocalization.format("%@已保存", kind.title)
            )
            if replacingAsset != nil {
                try? await Task.sleep(nanoseconds: 350_000_000)
                dismiss()
            }
        } catch {
            modelContext.rollback()
            if let writtenRelativePath {
                do {
                    try await ShowAssetMediaStore.shared.delete(
                        relativePath: writtenRelativePath,
                        showID: showID,
                        kind: kind
                    )
                } catch {
                    ShowAssetCleanupRetry.markAssetCleanupPending(
                        showID: showID,
                        kind: kind,
                        relativePath: writtenRelativePath
                    )
                }
            }
            await ShowAssetMediaStore.shared.releaseCommitGate()
            presentToast(.failure, message: saveErrorMessage(error))
        }
    }

    private func beginSave() {
        guard operation.canBeginSave(
            hasPendingData: pendingData != nil,
            saveTaskIsActive: saveTask != nil
        ), let data = pendingData else { return }
        let token = UUID()
        // Enter saving ownership before creating the task. This closes both the
        // rapid double-tap window and the import/save interleaving window.
        operation = .saving(token)
        saveTask = Task { @MainActor in
            await savePending(data: data, token: token)
        }
    }

    private func assetsOfSameKind() -> [ShowAsset] {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<ShowAsset>(
            predicate: #Predicate<ShowAsset> { asset in
                asset.showID == showID && asset.kindRawValue == kindRaw
            },
            sortBy: [
                SortDescriptor(\ShowAsset.updatedAt, order: .reverse),
                SortDescriptor(\ShowAsset.id)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveErrorMessage(_ error: Error) -> String {
        if let storeError = error as? ShowAssetMediaStoreError {
            switch storeError {
            case .insufficientDiskSpace:
                return BSLocalization.text("存储空间不足，先腾出一点空间再试")
            case .storageUnavailable:
                return BSLocalization.text("本地存储暂时不可用，请稍后重试")
            case .unsupportedImage, .imageEncodingFailed:
                return BSLocalization.text("这张图片暂时无法保存")
            case .importCancelled:
                return BSLocalization.text("已取消")
            case .missingShow:
                return BSLocalization.text("这场现场已不存在，无法保存")
            case .missingAsset:
                return BSLocalization.text("保存失败，请重试")
            case .invalidRelativePath:
                return BSLocalization.text("图片路径异常，请重新添加")
            case .fullCleanupPending:
                return BSLocalization.text("本地清除正在重试，请稍后再试")
            }
        }
        return BSLocalization.text("保存失败，请重试")
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}
