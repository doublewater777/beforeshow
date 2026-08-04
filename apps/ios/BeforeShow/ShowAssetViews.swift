import PhotosUI
import SwiftData
import SwiftUI
import UIKit

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
}

// MARK: - Upload

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
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var importTask: Task<Void, Never>?
    @State private var activeImportToken: UUID?
    @State private var saveTask: Task<Void, Never>?
    @State private var toast: BSToastPayload?
    @State private var didSave = false

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: BSSpacing.lg) {
                    if let previewImage {
                        previewSection(previewImage)
                    } else {
                        emptyUploadSection
                    }
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.md)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(previewImage == nil ? kind.addTitle : "\(kind.title)预览")
        .navigationBarTitleDisplayMode(.inline)
        .bsToastOverlay(toast, bottomPadding: 36)
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            importTask?.cancel()
            let token = UUID()
            activeImportToken = token
            importTask = Task { await importItem(item, token: token) }
        }
        .onDisappear {
            importTask?.cancel()
            activeImportToken = nil
            if !didSave {
                saveTask?.cancel()
            }
            // If user backs out after choosing a preview without saving, nothing was written.
            if !didSave {
                pendingData = nil
                previewImage = nil
            }
        }
        .navigationBarBackButtonHidden(isSaving)
        .interactiveDismissDisabled(isSaving)
    }

    private var emptyUploadSection: some View {
        VStack(spacing: BSSpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                BSColor.Stage.accent.opacity(0.14),
                                BSColor.Stage.glowBlue.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(BSColor.Stage.accent.opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: kind.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
            }
            .frame(width: 76, height: 76)

            VStack(spacing: BSSpacing.xs) {
                Text(kind.addTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(kind.addDescription)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(showName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(1)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(isImporting ? "读取中…" : "选择图片")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isImporting)
            .accessibilityLabel("选择\(kind.title)图片")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
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
            .frame(minHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .overlay(
                RoundedRectangle(cornerRadius: 23)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text("重新选择")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BSSecondaryButtonStyle())
                .disabled(isSaving || isImporting)

                Button {
                    beginSave()
                } label: {
                    Text(isSaving ? "保存中…" : "保存\(kind.title)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BSPrimaryButtonStyle())
                .disabled(isSaving || pendingData == nil)
            }
        }
    }

    private func importItem(_ item: PhotosPickerItem, token: UUID) async {
        isImporting = true
        defer {
            if activeImportToken == token {
                isImporting = false
                activeImportToken = nil
                importTask = nil
            }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                guard activeImportToken == token else { return }
                presentToast(.failure, message: "没有读到这张图片")
                return
            }
            try Task.checkCancellation()
            guard activeImportToken == token else { return }
            guard let image = UIImage(data: data) else {
                presentToast(.failure, message: "这张图片暂时无法使用")
                return
            }
            pendingData = data
            previewImage = image
            selectedItem = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeImportToken == token else { return }
            presentToast(.failure, message: "图片读取失败，请重试")
            selectedItem = nil
        }
    }

    private func savePending() async {
        guard let pendingData else { return }
        defer {
            isSaving = false
            saveTask = nil
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
            let existing = replacingAsset.flatMap { replacement in
                currentAssets.first(where: { $0.id == replacement.id })
            } ?? currentAssets.first
            let previousRelativePath = existing?.relativePath
            let assetID = existing?.id ?? UUID()
            let relativePath = try await ShowAssetMediaStore.shared.saveImage(
                data: pendingData,
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
            if let previousRelativePath, previousRelativePath != relativePath {
                try? await ShowAssetMediaStore.shared.delete(relativePath: previousRelativePath)
            }
            await ShowAssetMediaStore.shared.releaseCommitGate()
            didSave = true
            presentToast(.success, message: "\(kind.title)已保存")
            if replacingAsset != nil {
                try? await Task.sleep(nanoseconds: 350_000_000)
                dismiss()
            }
        } catch {
            modelContext.rollback()
            if let writtenRelativePath {
                try? await ShowAssetMediaStore.shared.delete(relativePath: writtenRelativePath)
            }
            await ShowAssetMediaStore.shared.releaseCommitGate()
            presentToast(.failure, message: saveErrorMessage(error))
        }
    }

    private func beginSave() {
        guard saveTask == nil, !isSaving, pendingData != nil else { return }
        // Enter the busy state in the button action itself. This closes the tiny
        // MainActor scheduling window in which a rapid second tap could otherwise
        // create another unowned save task.
        isSaving = true
        saveTask = Task { @MainActor in
            await savePending()
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
                return "存储空间不足，先腾出一点空间再试"
            case .storageUnavailable:
                return "本地存储暂时不可用，请稍后重试"
            case .unsupportedImage, .imageEncodingFailed:
                return "这张图片暂时无法保存"
            case .importCancelled:
                return "已取消"
            case .missingShow:
                return "这场现场已不存在，无法保存"
            case .missingAsset:
                return "保存失败，请重试"
            }
        }
        return "保存失败，请重试"
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
    @State private var isShowingManage = false
    @State private var isReplacing = false
    @State private var isConfirmingDelete = false
    @State private var toast: BSToastPayload?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                Text("双指缩放，拖动查看细节")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .padding(.bottom, 28)
            }
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
        .sheet(isPresented: $isShowingManage) {
            ShowAssetManageSheet(
                kind: kind,
                onReplace: {
                    isShowingManage = false
                    Task { @MainActor in
                        await Task.yield()
                        isReplacing = true
                    }
                },
                onDelete: {
                    isShowingManage = false
                    Task { @MainActor in
                        await Task.yield()
                        isConfirmingDelete = true
                    }
                },
                onCancel: { isShowingManage = false }
            )
        }
        .navigationDestination(isPresented: $isReplacing) {
            ShowAssetUploadView(
                showID: showID,
                showName: showName,
                kind: kind,
                replacingAsset: asset
            )
        }
        .sheet(isPresented: $isConfirmingDelete) {
            BSDangerConfirmationSheet(
                title: "删除\(kind.title)？",
                message: "删除后可以重新添加。App 内保存的图片会一起移除。",
                destructiveTitle: "删除\(kind.title)",
                onConfirm: {
                    isConfirmingDelete = false
                    deleteAsset()
                },
                onCancel: { isConfirmingDelete = false }
            )
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

            Button {
                isShowingManage = true
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
        let url = await ShowAssetMediaStore.shared.absoluteURL(for: relativePath)
        if let data = try? Data(contentsOf: url), let loaded = UIImage(data: data) {
            image = loaded
        } else {
            image = nil
            presentToast(.failure, message: "图片暂时打不开")
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
                    modelContext.delete(currentAsset)
                    try saveModelContextRollingBackOnFailure(modelContext)
                    try? await ShowAssetMediaStore.shared.delete(relativePath: currentRelativePath)
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                } catch {
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                    throw error
                }
                presentToast(.neutral, message: "\(kind.title)已删除")
                try? await Task.sleep(nanoseconds: 350_000_000)
                dismiss()
            } catch {
                presentToast(.failure, message: "删除失败，请重试")
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

// MARK: - Manage sheet

private struct ShowAssetManageSheet: View {
    let kind: ShowAssetKind
    let onReplace: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detents: [.height(320), .medium]) {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text("管理\(kind.title)")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                Text("你可以更换或删除这张图片。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: BSSpacing.sm) {
                Button(action: onReplace) {
                    manageRow(
                        icon: "photo.on.rectangle",
                        title: "替换图片",
                        subtitle: "选择另一张图片",
                        destructive: false
                    )
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    manageRow(
                        icon: "trash",
                        title: "删除\(kind.title)",
                        subtitle: "删除后可以重新添加",
                        destructive: true
                    )
                }
                .buttonStyle(.plain)

                Button("取消", action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
            }
        }
    }

    private func manageRow(
        icon: String,
        title: String,
        subtitle: String,
        destructive: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(destructive ? BSColor.Accent.danger : BSColor.Stage.accent)
                .frame(width: 36, height: 36)
                .background(
                    (destructive ? BSColor.Accent.danger : BSColor.Stage.accent).opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(destructive ? BSColor.Accent.danger : BSColor.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(BSColor.textTertiary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    destructive ? BSColor.Accent.danger.opacity(0.22) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
    }
}
