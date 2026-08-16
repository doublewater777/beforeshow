import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum DetailVisibilityEvent {
    case assetSheetPresented
    case assetSheetDismissed
}

enum DetailVisibilityHandoff {
    static func tabBarHidden(after event: DetailVisibilityEvent) -> Bool {
        switch event {
        case .assetSheetPresented:
            return true
        case .assetSheetDismissed:
            return false
        }
    }
}

/// Presents one ticket/timetable asset in a drawer sheet.
///
/// The entry view remains inside a navigation stack so its existing upload,
/// replacement, viewer, and delete flows work from both the current-show home
/// and a historical/canceled/ended show detail page.
struct ShowAssetSheet: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    var keepsParentDetailHidden = false

    @Environment(\.dismiss) private var dismiss
    @Query private var assets: [ShowAsset]

    init(
        showID: UUID,
        showName: String,
        kind: ShowAssetKind,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in },
        keepsParentDetailHidden: Bool = false
    ) {
        self.showID = showID
        self.showName = showName
        self.kind = kind
        self.onDetailVisibilityChange = onDetailVisibilityChange
        self.keepsParentDetailHidden = keepsParentDetailHidden
        let kindRaw = kind.rawValue
        _assets = Query(
            filter: #Predicate<ShowAsset> { asset in
                asset.showID == showID && asset.kindRawValue == kindRaw
            }
        )
    }

    var body: some View {
        Group {
            if let asset = assets.first {
                NavigationStack {
                    ShowAssetViewerView(
                        showID: showID,
                        showName: showName,
                        kind: kind,
                        asset: asset
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { dismiss() }
                        }
                    }
                    .bsClearNavigationContainer()
                }
                .bsSystemGlassSheet()
            } else {
                BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
                    ShowAssetUploadView(
                        showID: showID,
                        showName: showName,
                        kind: kind
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setDetailVisibility(for: .assetSheetPresented)
        }
        .onDisappear {
            if keepsParentDetailHidden {
                onDetailVisibilityChange(true)
            } else {
                setDetailVisibility(for: .assetSheetDismissed)
            }
        }
    }

    private func setDetailVisibility(for event: DetailVisibilityEvent) {
        let hidden = DetailVisibilityHandoff.tabBarHidden(after: event)
        onDetailVisibilityChange(hidden)
    }
}

// MARK: - Entry

/// Routes a ticket/timetable quick action: open viewer when saved, otherwise start upload.
struct ShowAssetEntryView: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind

    @Query private var assets: [ShowAsset]

    init(showID: UUID, showName: String, kind: ShowAssetKind) {
        self.showID = showID
        self.showName = showName
        self.kind = kind
        let kindRaw = kind.rawValue
        _assets = Query(
            filter: #Predicate<ShowAsset> { asset in
                asset.showID == showID && asset.kindRawValue == kindRaw
            }
        )
    }

    var body: some View {
        Group {
            if let asset = assets.first {
                ShowAssetViewerView(
                    showID: showID,
                    showName: showName,
                    kind: kind,
                    asset: asset
                )
            } else {
                ShowAssetUploadView(
                    showID: showID,
                    showName: showName,
                    kind: kind
                )
            }
        }
        .bsClearNavigationContainer()
    }
}

// MARK: - Upload

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
        replacingAsset == nil ? kind.addTitle : "替换\(kind.title)"
    }

    private var editorDescription: String {
        replacingAsset == nil
            ? kind.addDescription
            : "选择一张新的\(kind.choosePrompt)，替换当前保存的图片。"
    }

    private var emptyUploadSection: some View {
        VStack(spacing: BSSpacing.lg) {
            BSStageSheetHeader(
                icon: kind.iconName,
                title: editorTitle,
                subtitle: editorDescription
            )

            PhotosPicker(selection: $selectedItem, matching: .images) {
                if isImporting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("选择图片", systemImage: "photo")
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isImporting || isSaving)
            .accessibilityLabel("选择\(kind.title)图片")
        }
        .frame(maxWidth: .infinity)
    }

    private func previewSection(_ image: UIImage) -> some View {
        VStack(spacing: BSSpacing.md) {
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
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("保存\(kind.title)", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(BSPrimaryButtonStyle())
                .disabled(!operation.canBeginSave(
                    hasPendingData: pendingData != nil,
                    saveTaskIsActive: saveTask != nil
                ))
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
                    ? "\(kind.title)已保存，旧图片将在下次启动继续清理"
                    : "\(kind.title)已保存"
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

    private func existingAssetOfSameKind() -> ShowAsset? {
        assetsOfSameKind().first
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

// MARK: - Viewer

struct ShowAssetViewerView: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind
    let asset: ShowAsset

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var image: UIImage?
    @State private var isReplacing = false
    @State private var isConfirmingDelete = false
    @State private var toast: BSToastPayload?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .gesture(magnifyGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if scale > 1.05 {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2
                                    lastScale = 2
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 12)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let disclaimer = kind.viewerDisclaimer {
                Text(disclaimer)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            Text("双指缩放，拖动查看细节")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.55))
                .padding(.bottom, 28)
        }
        .navigationBarHidden(true)
        .bsToastOverlay(toast, bottomPadding: 36)
        .task(id: "\(asset.relativePath)|\(asset.updatedAt.timeIntervalSince1970)") {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
            image = nil
            await loadImage()
        }
        .navigationDestination(isPresented: $isReplacing) {
            ShowAssetUploadView(
                showID: showID,
                showName: showName,
                kind: kind,
                replacingAsset: asset
            )
        }
        .confirmationDialog(
            DangerConfirmation.deleteAsset(kind).title,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(DangerConfirmation.deleteAsset(kind).confirmTitle, role: .destructive) {
                deleteAsset()
            }
        } message: {
            Text(DangerConfirmation.deleteAsset(kind).message)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("返回")

            Spacer()

            Text(kind.viewerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Menu {
                Button("替换图片") {
                    isReplacing = true
                }
                Button("删除\(kind.title)", role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("管理\(kind.title)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(4, max(1, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func loadImage() async {
        let relativePath = asset.relativePath
        guard let url = try? await ShowAssetMediaStore.shared.absoluteURL(
            for: relativePath,
            showID: showID,
            kind: kind
        ) else {
            image = nil
            presentToast(.failure, message: BSLocalization.text("图片暂时不可用"))
            return
        }
        if let data = try? Data(contentsOf: url), let loaded = UIImage(data: data) {
            image = loaded
        } else {
            image = nil
            presentToast(.failure, message: BSLocalization.text("图片暂时打不开"))
        }
    }

    private func deleteAsset() {
        let assetID = asset.id
        Task { @MainActor in
            do {
                await ShowAssetMediaStore.shared.acquireCommitGate()
                do {
                    let currentAsset = try modelContext.fetch(
                        FetchDescriptor<ShowAsset>(predicate: #Predicate { $0.id == assetID })
                    ).first
                    guard let currentAsset else {
                        await ShowAssetMediaStore.shared.releaseCommitGate()
                        return
                    }
                    let currentRelativePath = currentAsset.relativePath
                    let currentKind = currentAsset.kind
                    modelContext.delete(currentAsset)
                    try saveModelContextRollingBackOnFailure(modelContext)
                    let cleanupPending: Bool
                    let invalidPath: Bool
                    do {
                        try await ShowAssetMediaStore.shared.delete(
                            relativePath: currentRelativePath,
                            showID: showID,
                            kind: currentKind
                        )
                        cleanupPending = false
                        invalidPath = false
                    } catch ShowAssetMediaStoreError.invalidRelativePath {
                        cleanupPending = false
                        invalidPath = true
                    } catch {
                        cleanupPending = true
                        invalidPath = false
                    }
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                    if cleanupPending,
                       ShowAsset.isValidRelativePath(
                           currentRelativePath,
                           showID: showID,
                           kind: currentKind
                       ) {
                        ShowAssetCleanupRetry.markAssetCleanupPending(
                            showID: showID,
                            kind: currentKind,
                            relativePath: currentRelativePath
                        )
                    }
                    presentToast(
                        invalidPath || cleanupPending ? .neutral : .success,
                        message: invalidPath
                            ? "\(kind.title)记录已删除，异常图片将在下次启动整理"
                            : cleanupPending
                            ? "\(kind.title)记录已删除，图片将在下次启动继续清理"
                            : "\(kind.title)已删除"
                    )
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    dismiss()
                    return
                } catch {
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                    throw error
                }
            } catch {
                presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
            }
        }
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
