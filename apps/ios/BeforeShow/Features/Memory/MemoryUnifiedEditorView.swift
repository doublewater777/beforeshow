import AVFoundation
import AVKit
import PhotosUI
import PostHog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Unified editor

private enum MemoryEditorOperation: Equatable {
    case idle
    case importing(UInt64)
    case saving(UInt64)
}

struct MemoryUnifiedEditorView: View {
    let launch: MemoryEditorLaunch
    let onSaveCreate: @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void
    let onSaveEdit: @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [MemoryEditorItem]
    @State private var caption: String
    @State private var removedExistingIDs: Set<UUID> = []
    @State private var draftID = UUID()
    @State private var selection = 0
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isShowingAddSource = false
    @State private var pendingAddDestination: MemoryCreateDestination?
    @State private var replacementIndex: Int?
    @State private var draggedItemID: UUID?
    @State private var operation: MemoryEditorOperation = .idle
    @State private var operationGeneration: UInt64 = 0
    @State private var errorMessage: String?
    @State private var activeImportTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var didCommitSuccessfully = false

    private var operationBusy: Bool {
        operation != .idle
    }

    private var isImporting: Bool {
        if case .importing = operation { return true }
        return false
    }

    private var isSaving: Bool {
        if case .saving = operation { return true }
        return false
    }

    private var isEditing: Bool {
        if case .edit = launch.kind { return true }
        return false
    }

    private var editingFragment: MemoryFragment? {
        if case .edit(let fragment) = launch.kind { return fragment }
        return nil
    }

    init(
        launch: MemoryEditorLaunch,
        onSaveCreate: @escaping @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void,
        onSaveEdit: @escaping @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void
    ) {
        self.launch = launch
        self.onSaveCreate = onSaveCreate
        self.onSaveEdit = onSaveEdit

        switch launch.kind {
        case .createText:
            _items = State(initialValue: [])
            _caption = State(initialValue: "")
        case .createMedia(let draftID, let media):
            _items = State(initialValue: media.map { MemoryEditorItem(id: $0.id, kind: .draft($0)) })
            _caption = State(initialValue: "")
            _draftID = State(initialValue: draftID)
        case .edit(let fragment):
            _items = State(initialValue: fragment.orderedMediaItems.map { item in
                MemoryEditorItem(
                    id: item.id,
                    kind: .existing(
                        id: item.id,
                        relativePath: item.relativePath,
                        thumbnailRelativePath: item.thumbnailRelativePath,
                        mediaKind: item.kind,
                        videoDuration: item.videoDuration
                    )
                )
            })
            _caption = State(initialValue: fragment.text ?? "")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - (BSSpacing.roomy * 2))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if isMediaComposer {
                        if !items.isEmpty {
                            draftPreview(width: contentWidth)
                                .padding(.top, 4)
                        }
                        HStack {
                            Text(BSLocalization.text("点击查看 · 拖动调整顺序"))
                            Spacer()
                            Text(BSLocalization.format("最多 %lld 项", MemoryFragment.maximumMediaCount))
                        }
                        .font(.system(size: 9.5))
                        .foregroundColor(BSColor.Stage.dim)
                        .padding(.horizontal, 2)
                        .padding(.top, 13)
                        mediaThumbs
                            .frame(width: contentWidth)
                            .padding(.top, 8)
                    }

                    TextField(
                        items.isEmpty ? BSLocalization.text("这一刻，你想记下什么？") : BSLocalization.text("写点什么……（可选）"),
                        text: $caption,
                        axis: .vertical
                    )
                    .lineLimit(items.isEmpty ? 10...14 : 4...7)
                    .onChange(of: caption) { _, value in
                        if value.count > captionLimit { caption = String(value.prefix(captionLimit)) }
                    }
                    .padding(13)
                    .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(BSColor.Stage.border, lineWidth: 1))
                    .frame(maxWidth: .infinity, minHeight: items.isEmpty ? 270 : 105, alignment: .top)
                    .padding(.top, 15)

                    HStack {
                        Text(items.isEmpty ? BSLocalization.text("最多 500 字") : BSLocalization.text("整组媒体共用一段文字"))
                        Spacer()
                        Text("\(caption.count) / \(captionLimit)")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                    .padding(.top, 10)
                }
                .frame(width: contentWidth, alignment: .top)
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.bottom, BSSpacing.lg)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(isSaving ? BSLocalization.text("保存中…") : (isEditing ? BSLocalization.text("保存修改") : BSLocalization.text("加入这场现场"))) {
                save()
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(operationBusy || !canSave)
            .padding(.horizontal, BSSpacing.roomy)
            .padding(.top, BSSpacing.sm)
            .padding(.bottom, BSSpacing.sm)
            .background(BSColor.Stage.background)
        }
        .navigationTitle(editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(isImporting ? BSLocalization.text("停止导入") : BSLocalization.text("取消"))
                .disabled(isSaving && !isImporting)
            }
        }
        .preferredColorScheme(.dark)
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedItems,
                maxSelectionCount: replacementIndex == nil
                    ? max(1, MemoryFragment.maximumMediaCount - items.count)
                    : 1,
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: selectedItems) { _, pickerItems in
                guard !pickerItems.isEmpty else { return }
                importLibrary(pickerItems)
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                SystemMemoryCameraPicker { result in
                    isCameraPresented = false
                    guard let result else { return }
                    importCamera(result)
                }
                .ignoresSafeArea()
            }
            .alert("无法继续", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                    Button("前往设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
            .sheet(isPresented: $isShowingAddSource, onDismiss: performPendingAddDestination) {
                MemoryAddMediaSheet(
                    onCamera: {
                        replacementIndex = nil
                        pendingAddDestination = .camera
                        isShowingAddSource = false
                    },
                    onLibrary: {
                        replacementIndex = nil
                        pendingAddDestination = .library
                        isShowingAddSource = false
                    }
                )
            }
            .onDisappear {
                // Interactive dismiss and navigation pops bypass the Cancel button.
                // A save owns staging until its transaction finishes.
                if didCommitSuccessfully || isSaving { return }
                let importTask = activeImportTask
                activeImportTask?.cancel()
                let draftID = draftID
                Task {
                    await importTask?.value
                    try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                }
            }
        .interactiveDismissDisabled(operationBusy)
    }

    private func performPendingAddDestination() {
        guard let destination = pendingAddDestination else { return }
        pendingAddDestination = nil
        switch destination {
        case .camera:
            requestCamera()
        case .library:
            isPhotoPickerPresented = true
        case .text:
            break
        }
    }

    private var editorTitle: String {
        if isEditing { return BSLocalization.text("编辑记忆") }
        return items.isEmpty ? "写下这一刻" : "新记忆"
    }

    private var isMediaComposer: Bool {
        if !items.isEmpty { return true }
        switch launch.kind {
        case .createMedia:
            return true
        case .edit(let fragment):
            return !fragment.mediaItems.isEmpty
        case .createText:
            return false
        }
    }

    private var editorSubtitle: String {
        if items.isEmpty { return BSLocalization.text("自动记录当前现场时间。") }
        return BSLocalization.text("像发一条私密动态，但不会公开发布。")
    }

    private var canSave: Bool {
        let hasText = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !items.isEmpty || hasText
    }

    private var captionLimit: Int { 500 }

    private func draftPreview(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if items.indices.contains(selection) {
                    let item = items[selection]
                    MemoryThumbnail(relativePath: item.previewRelativePath)
                    if item.mediaKind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: width, height: 365)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(BSColor.Stage.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Text("\(min(selection + 1, max(items.count, 1))) / \(max(items.count, 1))")
                    .font(BSFont.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(10)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Spacer()
                    Button("移除") { removeCurrent() }
                        .foregroundColor(Color(red: 1, green: 0.77, blue: 0.79))
                }
                .font(.system(size: 10, weight: .medium))
                .padding(10)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color.black.opacity(0.56))
            }
        }
    }

    private var mediaThumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { selection = index } label: {
                        MemoryThumbnail(relativePath: item.previewRelativePath)
                            .frame(width: 62, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(
                                RoundedRectangle(cornerRadius: 13)
                                    .stroke(selection == index ? BSColor.Stage.accent : BSColor.Stage.border, lineWidth: selection == index ? 2 : 1)
                            )
                            .overlay(alignment: .topTrailing) {
                                Text("\(index + 1)")
                                    .font(.system(size: 8))
                                    .frame(minWidth: 17, minHeight: 17)
                                    .background(Color.black.opacity(0.66), in: Capsule())
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                    .onDrag {
                        draggedItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .dropDestination(for: String.self) { _, _ in
                        if let draggedItemID,
                           let source = items.firstIndex(where: { $0.id == draggedItemID }) {
                            moveItem(from: source, to: index)
                        }
                        draggedItemID = nil
                        return true
                    }
                }
                if items.count < MemoryFragment.maximumMediaCount {
                    Button { isShowingAddSource = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(BSColor.Stage.accent)
                            .frame(width: 62, height: 76)
                            .background(BSColor.Stage.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(BSColor.Stage.border, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("继续添加媒体")
                }
            }
        }
    }

    private func moveItem(from source: Int, to destination: Int) {
        guard items.indices.contains(source), items.indices.contains(destination), source != destination else { return }
        let moved = items.remove(at: source)
        items.insert(moved, at: destination)
        selection = destination
    }

    private func removeCurrent() {
        guard items.indices.contains(selection) else { return }
        let removed = items.remove(at: selection)
        if let existingID = removed.existingID {
            removedExistingIDs.insert(existingID)
        }
        if let draft = removed.draftMedia {
            Task { try? await MemoryFragmentMediaStore.shared.removeStagedItem(draft) }
        }
        selection = max(0, min(selection, items.count - 1))
    }

    private func requestCamera() {
        guard !operationBusy else { return }
        guard replacementIndex != nil || items.count < MemoryFragment.maximumMediaCount else {
            errorMessage = BSLocalization.format("一条记忆最多 %lld 个媒体。", MemoryFragment.maximumMediaCount)
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = BSLocalization.text("当前设备无法使用相机。")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isCameraPresented = true
                } else {
errorMessage = BSLocalization.text("没有相机权限。你可以在系统设置中允许访问。")
                }
            }
        case .denied, .restricted:
            errorMessage = "没有相机权限。你可以在系统设置中允许访问。"
        @unknown default:
            errorMessage = BSLocalization.text("当前无法使用相机。")
        }
    }

    private func beginImport() -> UInt64 {
        activeImportTask?.cancel()
        operationGeneration &+= 1
        let generation = operationGeneration
        operation = .importing(generation)
        return generation
    }

    private func isCurrentImport(_ generation: UInt64) -> Bool {
        guard case .importing(let currentGeneration) = operation,
              currentGeneration == generation else { return false }
        return !Task.isCancelled
    }

    private func finishImport(_ generation: UInt64) {
        guard case .importing(let currentGeneration) = operation,
              currentGeneration == generation else { return }
        operation = .idle
        activeImportTask = nil
        selectedItems = []
    }

    private func importLibrary(_ pickerItems: [PhotosPickerItem]) {
        let generation = beginImport()
        activeImportTask = Task { @MainActor in
            defer { finishImport(generation) }
            let remaining = replacementIndex == nil
                ? MemoryFragment.maximumMediaCount - items.count
                : 1
            guard remaining > 0 else {
                errorMessage = BSLocalization.format("一条记忆最多 %lld 个媒体。", MemoryFragment.maximumMediaCount)
                return
            }
            if isEditing, pickerItems.count > remaining, isCurrentImport(generation) {
                errorMessage = BSLocalization.format("一条记忆最多 %lld 个媒体，已只载入前 %lld 个。", MemoryFragment.maximumMediaCount, remaining)
            }
            for item in pickerItems.prefix(remaining) {
                guard isCurrentImport(generation) else { return }
                do {
                    guard let imported = try await item.loadTransferable(type: MemoryImportedFile.self) else { continue }
                    guard isCurrentImport(generation) else {
                        try? await MemoryFragmentMediaStore.shared.discardImportedFile(imported)
                        return
                    }
                    let staged = try await MemoryFragmentMediaStore.shared.stageTransferredFile(
                        imported,
                        draftID: draftID
                    )
                    guard isCurrentImport(generation) else {
                        try? await MemoryFragmentMediaStore.shared.removeStagedItem(staged)
                        return
                    }
                    let editorItem = MemoryEditorItem(id: staged.id, kind: .draft(staged))
                    if let replacementIndex, items.indices.contains(replacementIndex) {
                        let removed = items[replacementIndex]
                        if let existingID = removed.existingID { removedExistingIDs.insert(existingID) }
                        if let draft = removed.draftMedia {
                            try? await MemoryFragmentMediaStore.shared.removeStagedItem(draft)
                        }
                        items[replacementIndex] = editorItem
                        selection = replacementIndex
                        self.replacementIndex = nil
                        break
                    } else {
                        items.append(editorItem)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if isCurrentImport(generation) {
                        errorMessage = "媒体没有载入，请重试。"
                    }
                }
            }
            guard isCurrentImport(generation) else { return }
            if replacementIndex == nil { selection = max(0, items.count - 1) }
        }
    }

    private func importCamera(_ result: MemoryCameraResult) {
        let generation = beginImport()
        activeImportTask = Task { @MainActor in
            defer { finishImport(generation) }
            guard items.count < MemoryFragment.maximumMediaCount else {
                errorMessage = BSLocalization.format("一条记忆最多 %lld 个媒体。", MemoryFragment.maximumMediaCount)
                return
            }
            do {
                switch result {
                case .photo(let data):
                    let staged = try await MemoryFragmentMediaStore.shared.stageCameraPhoto(data, draftID: draftID)
                    guard isCurrentImport(generation) else {
                        try? await MemoryFragmentMediaStore.shared.removeStagedItem(staged)
                        return
                    }
                    let editorItem = MemoryEditorItem(id: staged.id, kind: .draft(staged))
                    if let replacementIndex, items.indices.contains(replacementIndex) {
                        let removed = items[replacementIndex]
                        if let existingID = removed.existingID { removedExistingIDs.insert(existingID) }
                        if let draft = removed.draftMedia {
                            try? await MemoryFragmentMediaStore.shared.removeStagedItem(draft)
                        }
                        items[replacementIndex] = editorItem
                        selection = replacementIndex
                        self.replacementIndex = nil
                    } else {
                        items.append(editorItem)
                    }
                case .video:
                    errorMessage = BSLocalization.text("相机入口只拍照片，视频请从相册选择。")
                    return
                }
                guard isCurrentImport(generation) else { return }
                if replacementIndex == nil { selection = max(0, items.count - 1) }
            } catch is CancellationError {
                return
            } catch {
                if isCurrentImport(generation) {
                    errorMessage = "照片没有载入，请重试。"
                }
            }
        }
    }

    private func finishSave(_ generation: UInt64) {
        guard case .saving(generation) = operation else { return }
        operation = .idle
        saveTask = nil
    }

    private func save() {
        guard operation == .idle, canSave else { return }
        operationGeneration &+= 1
        let generation = operationGeneration
        operation = .saving(generation)
        saveTask = Task { @MainActor in
            defer { finishSave(generation) }
            do {
                let draftsInOrder = items.compactMap(\.draftMedia)
                // Keep editor visual order, including interleaved new drafts.
                // Draft IDs are preserved by MediaStore commit, so this list is the final order.
                let fullOrder = items.map(\.id)
                switch launch.kind {
                case .createText, .createMedia:
                    // Create path commits drafts in array order.
                    try await onSaveCreate(draftID, draftsInOrder, caption)
                case .edit(let fragment):
                    try await onSaveEdit(
                        fragment,
                        fullOrder,
                        caption,
                        removedExistingIDs,
                        draftsInOrder,
                        draftID
                    )
                }
                didCommitSuccessfully = true
                dismiss()
            } catch {
                if case .saving(generation) = operation {
                    #if DEBUG
                    print("[MemoryFragments] save failed: \(String(reflecting: error))")
                    #endif
                    errorMessage = saveFailureMessage(for: error)
                }
            }
        }
    }

    private func saveFailureMessage(for error: Error) -> String {
        if let storeError = error as? MemoryMediaStoreError {
            switch storeError {
            case .missingStagedDraft:
                return BSLocalization.text("所选媒体的临时文件已失效，请返回图库重新选择。")
            case .insufficientDiskSpace:
                return BSLocalization.text("设备储存空间不足，暂时无法保存。")
            case .unsupportedMedia:
                return BSLocalization.text("这个媒体格式暂不支持，请换一张照片或视频。")
            case .imageEncodingFailed:
                return BSLocalization.text("这张图片无法处理，请换一张图片后重试。")
            case .importCancelled:
                return BSLocalization.text("媒体导入已取消，请重新选择。")
            }
        }
        if let validationError = error as? MemoryFragmentValidationError {
            switch validationError {
            case .emptyContent:
                return BSLocalization.text("请保留至少一项媒体或一段文字。")
            case .textTooLong:
                return BSLocalization.text("文字最多 500 字。")
            case .mediaLimitExceeded:
                return BSLocalization.text("一条记忆最多 10 项媒体。")
            }
        }
        return BSLocalization.text("内容没有保存，请重试。")
    }

    private func cancel() {
        switch operation {
        case .importing:
            activeImportTask?.cancel()
            return
        case .saving:
            return
        case .idle:
            let draftID = draftID
            Task {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
            }
            dismiss()
        }
    }
}
