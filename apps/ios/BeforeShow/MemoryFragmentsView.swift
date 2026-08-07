import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Presentation models

private struct MemoryEditorLaunch: Identifiable {
    enum Kind {
        case createText
        case createMedia(draftID: UUID, media: [MemoryDraftMedia])
        case edit(MemoryFragment)
    }

    let id = UUID()
    let kind: Kind
}

private struct MemoryViewerTarget: Identifiable {
    let id = UUID()
    let fragment: MemoryFragment
    let initialIndex: Int
}

private struct MemoryEditorItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case existing(
            id: UUID,
            relativePath: String,
            thumbnailRelativePath: String?,
            mediaKind: MemoryMediaKind,
            videoDuration: TimeInterval?
        )
        case draft(MemoryDraftMedia)
    }

    let id: UUID
    var kind: Kind

    var previewRelativePath: String {
        switch kind {
        case .existing(_, let relativePath, let thumbnailRelativePath, _, _):
            return thumbnailRelativePath ?? relativePath
        case .draft(let draft):
            return draft.thumbnailStagedRelativePath ?? draft.stagedRelativePath
        }
    }

    var mediaKind: MemoryMediaKind {
        switch kind {
        case .existing(_, _, _, let mediaKind, _):
            return mediaKind
        case .draft(let draft):
            return draft.kind
        }
    }

    var isDraft: Bool {
        if case .draft = kind { return true }
        return false
    }

    var draftMedia: MemoryDraftMedia? {
        if case .draft(let draft) = kind { return draft }
        return nil
    }

    var existingID: UUID? {
        if case .existing(let id, _, _, _, _) = kind { return id }
        return nil
    }
}

// MARK: - Timeline

struct MemoryFragmentsView: View {
    let show: Show

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]
    @State private var isShowingCreateOptions = false
    @State private var editorLaunch: MemoryEditorLaunch?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var selectedCreateMedia: [PhotosPickerItem] = []
    @State private var createSourceError: String?
    @State private var pendingDelete: MemoryFragment?
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var viewerTarget: MemoryViewerTarget?
    @State private var managementTarget: MemoryFragment?
    @State private var deleteConfirmationTarget: MemoryFragment?
    @State private var toast: BSToastPayload?

    init(show: Show) {
        self.show = show
        let showID = show.id
        _fragments = Query(
            filter: #Predicate<MemoryFragment> { $0.showID == showID },
            sort: [
                SortDescriptor(\MemoryFragment.createdAt, order: .reverse),
                SortDescriptor(\MemoryFragment.id, order: .reverse)
            ]
        )
    }

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        timelineNavigation
                        header
                            .padding(.top, 4)

                        if visibleFragments.isEmpty {
                            timelineEmptyState
                        } else {
                            ForEach(timelineSections, id: \.phase) { section in
                                MemoryTimelineSection(
                                    phase: section.phase,
                                    fragments: section.fragments,
                                    onManage: { managementTarget = $0 },
                                    onOpenMedia: { fragment, index in
                                        viewerTarget = MemoryViewerTarget(fragment: fragment, initialIndex: index)
                                    }
                                )
                                .id(section.phase)
                                }
                        }

                    }
                    .padding(.bottom, 104)
                }
                .onChange(of: fragments.count) { oldCount, newCount in
                    guard newCount > oldCount, let firstID = fragments.first?.id else { return }
                    withAnimation { proxy.scrollTo(firstID, anchor: .top) }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            HStack {
                Button { isShowingCreateOptions = true } label: {
                    Text("＋ 新增记忆")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(BSColor.Stage.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(BSColor.Stage.accent.opacity(0.24), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(6)
            .background(BSColor.Stage.surface.opacity(0.90), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.11), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
            .padding(.horizontal, 15)
            .padding(.bottom, 18)
        }
        .bsToastOverlay(toast, bottomPadding: 92)
        .overlay(alignment: .bottom) {
            if pendingDelete != nil {
                HStack(spacing: BSSpacing.md) {
                    Text("已删除这条记忆")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.foreground)
                    Button("撤销", action: undoDelete)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSpacing.compact)
                .background(Color.black.opacity(0.86), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
                .padding(.bottom, 92)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: pendingDelete?.id)
        .fullScreenCover(isPresented: $isShowingCreateOptions) {
            MemoryCreateSourceView(
                onCamera: { openCameraDirectly() },
                onPhotoLibrary: { openPhotoLibraryDirectly() },
                onText: { launchTextEditor() },
                onCancel: { isShowingCreateOptions = false }
            )
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedCreateMedia,
            maxSelectionCount: MemoryFragment.maximumMediaCount,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedCreateMedia) { _, items in
            guard !items.isEmpty else { return }
            importDirectLibrarySelection(items)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            SystemMemoryCameraPicker { result in
                isCameraPresented = false
                guard let result else { return }
                importDirectCameraResult(result)
            }
            .ignoresSafeArea()
        }
        .alert("无法继续", isPresented: Binding(
            get: { createSourceError != nil },
            set: { if !$0 { createSourceError = nil } }
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
            Text(createSourceError ?? "请稍后重试。")
        }
        .fullScreenCover(item: $editorLaunch) { launch in
            MemoryUnifiedEditorView(
                launch: launch,
                onSaveCreate: { draftID, media, caption in
                    try await createFragment(draftID: draftID, media: media, caption: caption)
                },
                onSaveEdit: { fragment, fullOrder, caption, removedIDs, additions, draftID in
                    try await saveEditedFragment(
                        fragment,
                        fullOrder: fullOrder,
                        caption: caption,
                        removedIDs: removedIDs,
                        additions: additions,
                        draftID: draftID
                    )
                }
            )
        }
        .sheet(item: $managementTarget) { fragment in
            MemoryManagementSheet(
                isTextOnly: fragment.mediaItems.isEmpty,
                onEdit: {
                    managementTarget = nil
                    Task { @MainActor in
                        await Task.yield()
                        editorLaunch = MemoryEditorLaunch(kind: .edit(fragment))
                    }
                },
                onDelete: {
                    managementTarget = nil
                    Task { @MainActor in
                        await Task.yield()
                        deleteConfirmationTarget = fragment
                    }
                },
                onCancel: { managementTarget = nil }
            )
        }
        .sheet(item: $deleteConfirmationTarget) { fragment in
            MemoryDeleteConfirmationSheet(
                onDelete: {
                    deleteConfirmationTarget = nil
                    stageDelete(fragment)
                },
                onCancel: { deleteConfirmationTarget = nil }
            )
        }
        .fullScreenCover(item: $viewerTarget) { target in
            MemoryMediaViewer(
                fragment: target.fragment,
                initialIndex: target.initialIndex,
                onEdit: {
                    viewerTarget = nil
                    Task { @MainActor in
                        await Task.yield()
                        editorLaunch = MemoryEditorLaunch(kind: .edit(target.fragment))
                    }
                },
                onDelete: {
                    viewerTarget = nil
                    Task { @MainActor in
                        await Task.yield()
                        deleteConfirmationTarget = target.fragment
                    }
                }
            )
        }
        .onDisappear {
            if let pendingDelete {
                pendingDeleteTask?.cancel()
                commitDelete(pendingDelete)
            }
        }
        .task(id: fragments.map(\.id)) {
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            var validFilesByFragmentID: [UUID: Set<String>] = [:]
            let showID = show.id
            let descriptor = FetchDescriptor<MemoryFragment>(
                predicate: #Predicate<MemoryFragment> { $0.showID == showID }
            )
            guard let current = try? modelContext.fetch(descriptor) else {
                await MemoryFragmentMediaStore.shared.releaseCommitGate()
                return
            }
            for fragment in current {
                let paths = fragment.mediaItems.flatMap { item in
                    [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
                }
                validFilesByFragmentID[fragment.id] = Set(paths)
            }
            try? await MemoryFragmentMediaStore.shared.reconcileFragmentFiles(
                showID: show.id,
                validFilesByFragmentID: validFilesByFragmentID
            )
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
        }
    }

    private var timelineNavigation: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            VStack(spacing: 2) {
                Text("记忆碎片")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
            }
            .frame(maxWidth: .infinity)

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("记忆碎片设置")
        }
        .padding(.horizontal, 17)
        .frame(height: 58)
        .padding(.top, 4)
    }

    private var header: some View {
        let stats = timelineStats
        return VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(headerEyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(BSColor.Stage.accent)
            Text("这场现场的记忆")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
            Text("照片、视频和小记都按现场阶段收在这里。")
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.muted)
            HStack(spacing: BSSpacing.lg) {
                timelineStat(value: "\(stats.memories)", label: "条记忆")
                timelineStat(value: "\(stats.photos)", label: "照片")
                timelineStat(value: "\(stats.videos)", label: "视频")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                .fill(BSColor.Stage.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                        .stroke(BSColor.Stage.accent.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    private func timelineStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(BSColor.Stage.dim)
        }
    }

    private func phaseColor(_ phase: MemoryFragmentPhase) -> Color {
        switch phase {
        case .after: return BSColor.Stage.accent
        case .live: return BSColor.Stage.liveTitle
        case .before: return BSColor.Stage.muted
        }
    }

    private var timelineEmptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(BSColor.Stage.muted)
                .frame(width: 68, height: 68)
                .background(Color.white.opacity(0.04), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
            Text("还没有记忆碎片")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(BSColor.Stage.foreground)
                .padding(.top, 18)
            Text("拍一张照片、选择一段短视频，\n或者写下此刻的一句话。")
                .font(.system(size: 13))
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.top, 9)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 18)
    }

    private func launchTextEditor() {
        isShowingCreateOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            editorLaunch = MemoryEditorLaunch(kind: .createText)
        }
    }

    private func openPhotoLibraryDirectly() {
        isShowingCreateOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            selectedCreateMedia = []
            isPhotoPickerPresented = true
        }
    }

    private func openCameraDirectly() {
        isShowingCreateOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                createSourceError = "当前设备无法使用相机。"
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                isCameraPresented = true
            case .notDetermined:
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isCameraPresented = true
                } else {
                    createSourceError = "没有相机权限。你可以在系统设置中允许访问。"
                }
            case .denied, .restricted:
                createSourceError = "没有相机权限。你可以在系统设置中允许访问。"
            @unknown default:
                createSourceError = "当前无法使用相机。"
            }
        }
    }

    private func importDirectLibrarySelection(_ pickerItems: [PhotosPickerItem]) {
        selectedCreateMedia = []
        Task { @MainActor in
            let draftID = UUID()
            do {
                var stagedItems: [MemoryDraftMedia] = []
                for item in pickerItems.prefix(MemoryFragment.maximumMediaCount) {
                    guard let imported = try await item.loadTransferable(type: MemoryImportedFile.self) else {
                        continue
                    }
                    let staged = try await MemoryFragmentMediaStore.shared.stageTransferredFile(
                        imported,
                        draftID: draftID
                    )
                    stagedItems.append(staged)
                }
                guard !stagedItems.isEmpty else {
                    try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                    createSourceError = "媒体没有载入，请重试。"
                    return
                }
                editorLaunch = MemoryEditorLaunch(kind: .createMedia(draftID: draftID, media: stagedItems))
            } catch {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                createSourceError = "媒体没有载入，请重试。"
            }
        }
    }

    private func importDirectCameraResult(_ result: MemoryCameraResult) {
        Task { @MainActor in
            let draftID = UUID()
            do {
                guard case .photo(let data) = result else {
                    createSourceError = "相机入口只拍照片，视频请从相册选择。"
                    return
                }
                let staged = try await MemoryFragmentMediaStore.shared.stageCameraPhoto(data, draftID: draftID)
                editorLaunch = MemoryEditorLaunch(kind: .createMedia(draftID: draftID, media: [staged]))
            } catch {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                createSourceError = "照片没有载入，请重试。"
            }
        }
    }

    private var timelineSections: [(phase: MemoryFragmentPhase, fragments: [MemoryFragment])] {
        [MemoryFragmentPhase.after, .live, .before].compactMap { phase in
            let items = visibleFragments.filter { $0.phase == phase }
            guard !items.isEmpty else { return nil }
            return (phase, items)
        }
    }

    private var visibleFragments: [MemoryFragment] {
        fragments.filter { $0.id != pendingDelete?.id }
    }

    private var timelineStats: (memories: Int, photos: Int, videos: Int, notes: Int) {
        let photos = visibleFragments.reduce(0) { count, fragment in
            count + fragment.mediaItems.filter { $0.kind == .photo }.count
        }
        let videos = visibleFragments.reduce(0) { count, fragment in
            count + fragment.mediaItems.filter { $0.kind == .video }.count
        }
        let notes = visibleFragments.filter { $0.mediaItems.isEmpty }.count
        return (visibleFragments.count, photos, videos, notes)
    }

    private var headerEyebrow: String {
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [show.endedAt == nil ? "LIVE" : "MEMORY", city?.uppercased()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var showMetadata: String {
        let date = ShowDisplayFormatter().dateText(for: show)
        let place = show.venueName ?? show.city
        return [date, place].compactMap { $0 }.joined(separator: " · ")
    }

    private func fetchShow(for id: UUID) -> Show? {
        var descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func resolvedPhase(for show: Show?, at date: Date) -> MemoryFragmentPhase {
        guard let show else { return .live }
        return MemoryFragmentPhase.resolved(at: date, timing: show.timingFields)
    }

    @MainActor
    private func createFragment(
        draftID: UUID,
        media: [MemoryDraftMedia],
        caption: String
    ) async throws {
        let normalizedCaption = try MemoryFragment.normalized(caption)
        guard !media.isEmpty || normalizedCaption != nil else {
            throw MemoryFragmentValidationError.emptyContent
        }
        guard media.count <= MemoryFragment.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }

        if media.isEmpty {
            let owner = fetchShow(for: show.id)
            let createdAt = Date()
            let phase = resolvedPhase(for: owner, at: createdAt)
            let fragment = try MemoryFragment(
                showID: show.id,
                text: caption,
                createdAt: createdAt,
                updatedAt: createdAt,
                phase: phase
            )
            fragment.show = owner
            modelContext.insert(fragment)
            try modelContext.save()
            presentToast(.success, "已加入这场现场")
            return
        }

        let fragmentID = UUID()
        await MemoryFragmentMediaStore.shared.acquireCommitGate()
        let committed: [MemoryCommittedMedia]
        do {
            committed = try await MemoryFragmentMediaStore.shared.commit(
                draftID: draftID,
                showID: show.id,
                fragmentID: fragmentID,
                media: media
            )
        } catch {
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            throw error
        }
        let committedPaths = committed.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 }
        }
        do {
            let owner = fetchShow(for: show.id)
            let createdAt = Date()
            let phase = resolvedPhase(for: owner, at: createdAt)
            let fragment = try MemoryFragment(
                id: fragmentID,
                showID: show.id,
                text: caption,
                createdAt: createdAt,
                updatedAt: createdAt,
                phase: phase
            )
            fragment.show = owner
            for (index, item) in committed.enumerated() {
                try fragment.appendMedia(MemoryMediaItem(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbnailRelativePath: item.thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration,
                    sortOrder: index
                ))
            }
            modelContext.insert(fragment)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            try? await MemoryFragmentMediaStore.shared.rollbackCommittedFiles(relativePaths: committedPaths)
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            throw error
        }
        await MemoryFragmentMediaStore.shared.releaseCommitGate()
        try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
        presentToast(.success, "已加入这场现场")
    }

    private func stageDelete(_ fragment: MemoryFragment) {
        if let pendingDelete {
            pendingDeleteTask?.cancel()
            commitDelete(pendingDelete)
        }
        pendingDelete = fragment
        toast = nil
        pendingDeleteTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, pendingDelete?.id == fragment.id else { return }
            commitDelete(fragment)
        }
    }

    private func undoDelete() {
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        pendingDelete = nil
        presentToast(.success, "已撤销删除")
    }

    private func commitDelete(_ fragment: MemoryFragment) {
        let fragmentID = fragment.id
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        if pendingDelete?.id == fragmentID { pendingDelete = nil }
        modelContext.delete(fragment)
        do {
            try modelContext.save()
            Task {
                try? await MemoryFragmentMediaStore.shared.deleteFragment(showID: show.id, fragmentID: fragmentID)
            }
        } catch {
            modelContext.rollback()
            presentToast(.failure, "删除失败，请重试")
        }
    }

    @MainActor
    private func saveEditedFragment(
        _ fragment: MemoryFragment,
        fullOrder: [UUID],
        caption: String,
        removedIDs: Set<UUID>,
        additions: [MemoryDraftMedia],
        draftID: UUID
    ) async throws {
        // Validate the post-edit content shape *before* mutating SwiftData or copying files.
        // Otherwise a failed save can leave partial in-memory model changes (text update /
        // media removals) that still render until the next refresh.
        let normalizedCaption = try MemoryFragment.normalized(caption)
        let remainingExisting = fragment.orderedMediaItems.filter { !removedIDs.contains($0.id) }
        if remainingExisting.isEmpty && additions.isEmpty {
            guard normalizedCaption != nil else { throw MemoryFragmentValidationError.emptyContent }
        }
        guard remainingExisting.count + additions.count <= MemoryFragment.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }

        // Capture file paths to delete only after a successful model save.
        let removedPaths = fragment.orderedMediaItems
            .filter { removedIDs.contains($0.id) }
            .flatMap { item in [item.relativePath, item.thumbnailRelativePath].compactMap { $0 } }

        // Commit new files first so model mutations can stay one transactional unit:
        // either all model edits save, or we roll back the context *and* any newly copied files.
        var committed: [MemoryCommittedMedia] = []
        var committedPaths: [String] = []
        if !additions.isEmpty {
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            do {
                committed = try await MemoryFragmentMediaStore.shared.commitAdditions(
                    draftID: draftID,
                    showID: show.id,
                    fragmentID: fragment.id,
                    media: additions
                )
                committedPaths = committed.flatMap {
                    [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 }
                }
            } catch {
                await MemoryFragmentMediaStore.shared.releaseCommitGate()
                throw error
            }
        }

        do {
            try fragment.updateText(caption)

            let additionItems = committed.map { item in
                MemoryMediaItem(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbnailRelativePath: item.thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration,
                    sortOrder: 0
                )
            }
            let removedItems = fragment.orderedMediaItems.filter { removedIDs.contains($0.id) }
            try fragment.applyMediaEdit(
                removingIDs: removedIDs,
                adding: additionItems,
                finalOrder: fullOrder
            )
            for item in removedItems {
                modelContext.delete(item)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            if !committedPaths.isEmpty {
                try? await MemoryFragmentMediaStore.shared.rollbackCommittedFiles(relativePaths: committedPaths)
            }
            if !additions.isEmpty {
                await MemoryFragmentMediaStore.shared.releaseCommitGate()
            }
            throw error
        }

        if !additions.isEmpty {
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
        }

        if !removedPaths.isEmpty {
            Task { try? await MemoryFragmentMediaStore.shared.deleteFiles(relativePaths: removedPaths) }
        }
        presentToast(.success, "已保存修改")
    }

    private func presentToast(_ tone: BSToastTone, _ message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toast == payload { toast = nil }
        }
    }
}

// MARK: - Create source

private struct MemoryCreateSourceView: View {
    let onCamera: () -> Void
    let onPhotoLibrary: () -> Void
    let onText: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 41, height: 41)
                            .background(Color.white.opacity(0.06), in: Circle())
                            .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                    VStack(spacing: 2) {
                        Text("新增记忆")
                            .font(.system(size: 15, weight: .semibold))
                        Text("选择一种方式开始")
                            .font(.system(size: 11))
                            .foregroundColor(BSColor.Stage.dim)
                    }
                    .frame(maxWidth: .infinity)
                    Color.clear.frame(width: 41, height: 41)
                }
                .padding(.horizontal, 17)
                .frame(height: 58)

                Text("记录这一刻")
                    .font(.system(size: 23, weight: .bold))
                    .padding(.top, 12)
                Text("照片、图库媒体或一段文字，都可以成为一条记忆。")
                    .font(.system(size: 12.5))
                    .foregroundColor(BSColor.Stage.muted)
                    .lineSpacing(5)
                    .padding(.top, 7)

                HStack(spacing: 10) {
                    createButton("相机", subtitle: "打开系统相机", icon: "camera", action: onCamera)
                    createButton("图库", subtitle: "多选照片或视频", icon: "photo.on.rectangle", action: onPhotoLibrary)
                    createButton("文字", subtitle: "写一段现场小记", icon: "text.alignleft", action: onText)
                }
                .padding(.top, 20)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .preferredColorScheme(.dark)
    }

    private func createButton(
        _ title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [BSColor.Stage.accent.opacity(0.16), BSColor.Stage.glowBlue.opacity(0.11)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(BSColor.Stage.dim)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(BSColor.Stage.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct MemoryManagementSheet: View {
    let isTextOnly: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(286)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("管理这条记忆")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .padding(.bottom, 8)
                managementButton(
                    "编辑记忆",
                    subtitle: isTextOnly ? "修改这段现场小记" : "修改媒体顺序或文字",
                    icon: "pencil",
                    tint: BSColor.Stage.foreground,
                    action: onEdit
                )
                Divider().overlay(BSColor.Stage.border)
                managementButton(
                    "删除这条记忆",
                    subtitle: "从本地时间流中移除",
                    icon: "trash",
                    tint: BSColor.Stage.danger,
                    action: onDelete
                )
                Button("取消", action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
                    .padding(.top, 8)
            }
        }
    }

    private func managementButton(
        _ title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(tint)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tint)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.muted)
                }
                Spacer()
            }
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
    }
}

private struct MemoryAddMediaSheet: View {
    let onCamera: () -> Void
    let onLibrary: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(292)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("继续添加")
                    .font(.system(size: 18, weight: .semibold))
                Text("给当前这条记忆增加媒体")
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 6)
                HStack(spacing: 10) {
                    sourceButton("继续拍照", subtitle: "打开系统相机", icon: "camera", action: onCamera)
                    sourceButton("从图库选择", subtitle: "照片或视频", icon: "photo.on.rectangle", action: onLibrary)
                }
                .padding(.top, 17)
                Button("取消", action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
                    .padding(.top, 10)
            }
        }
    }

    private func sourceButton(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 42, height: 42)
                    .background(BSColor.Stage.accent.opacity(0.10), in: Circle())
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 9.5)).foregroundColor(BSColor.Stage.dim)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 105)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BSColor.Stage.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct MemoryDeleteConfirmationSheet: View {
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(220)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("删除这条记忆？")
                    .font(.system(size: 18, weight: .semibold))
                Text("照片、视频和文字都会从本地时间流中移除。")
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .lineSpacing(4)
                    .padding(.top, 6)
                HStack(spacing: 9) {
                    Button("取消", action: onCancel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    Button("删除", role: .destructive, action: onDelete)
                        .foregroundColor(Color(red: 0.10, green: 0.03, blue: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .background(BSColor.Stage.danger, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 15)
            }
        }
    }
}

// MARK: - Timeline row

private struct MemoryTimelineSection: View {
    let phase: MemoryFragmentPhase
    let fragments: [MemoryFragment]
    let onManage: (MemoryFragment) -> Void
    let onOpenMedia: (MemoryFragment, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(phase.title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(phaseTitleColor)
                Text("\(fragments.count) 条")
                    .font(.system(size: 9.5))
                    .foregroundColor(BSColor.Stage.dim)
                Rectangle()
                    .fill(BSColor.Stage.border)
                    .frame(height: 1)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            VStack(spacing: 17) {
                ForEach(fragments) { fragment in
                    MemoryTimelinePost(
                        fragment: fragment,
                        onManage: { onManage(fragment) },
                        onOpenMedia: { onOpenMedia(fragment, $0) }
                    )
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)
        }
    }

    private var phaseTitleColor: Color {
        switch phase {
        case .after: BSColor.Stage.accent
        case .live: Color(red: 1, green: 0.82, blue: 0.83)
        case .before: BSColor.Stage.muted
        }
    }
}

private struct MemoryTimelinePost: View {
    let fragment: MemoryFragment
    let onManage: () -> Void
    let onOpenMedia: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(BSColor.Stage.surfaceRaised)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(BSColor.Stage.accent, lineWidth: 2))
                    .overlay(Circle().stroke(BSColor.Stage.background, lineWidth: 5).padding(-5))
                    .padding(.top, 5)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [BSColor.Stage.border, Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 31)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(MemoryFragmentRelativeTime.format(fragment.createdAt, now: context.date))
                    }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Button(action: onManage) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                            .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("管理这条记忆")
                }

                if fragment.mediaItems.isEmpty {
                    textCard
                } else {
                    mediaCard
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(fragment.text ?? "")
                .font(.system(size: 14, design: .serif))
                .foregroundColor(Color(red: 0.90, green: 0.91, blue: 0.93))
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            MemoryMediaCarousel(items: fragment.orderedMediaItems) { index, _ in
                onOpenMedia(index)
            }
            if let text = fragment.text, !text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.90, green: 0.91, blue: 0.93))
                        .lineSpacing(5)
                }
                .padding(13)
            }
        }
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 17))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(BSColor.Stage.border, lineWidth: 1))
    }
}

private struct MemoryMediaCarousel: View {
    let items: [MemoryMediaItem]
    let onTap: (Int, MemoryMediaItem) -> Void
    @State private var selection = 0

    var body: some View {
        VStack(spacing: BSSpacing.sm) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { onTap(index, item) } label: {
                        ZStack {
                            MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                            if item.kind == .video {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 330)
            .onChange(of: items.map(\.id)) { _, _ in
                selection = min(selection, max(0, items.count - 1))
            }

            if items.count > 1 {
                HStack(spacing: 5) {
                    ForEach(items.indices, id: \.self) { index in
                        Circle()
                            .fill(index == selection ? BSColor.Stage.accent : Color.white.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct MemoryThumbnail: View {
    let relativePath: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ZStack {
                    BSColor.Stage.surface
                    Image(systemName: "photo")
                        .foregroundColor(BSColor.Stage.muted)
                }
            }
        }
        .task(id: relativePath) {
            let path = MemoryMediaLocation.applicationSupport().url(for: relativePath).path
            let loaded = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)
            }.value
            image = loaded
        }
    }
}

// MARK: - Viewer

private struct MemoryMediaViewer: View {
    let fragment: MemoryFragment
    let initialIndex: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var isShowingManagement = false

    init(
        fragment: MemoryFragment,
        initialIndex: Int,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.fragment = fragment
        self.initialIndex = initialIndex
        self.onEdit = onEdit
        self.onDelete = onDelete
        _index = State(initialValue: max(0, min(initialIndex, max(0, fragment.orderedMediaItems.count - 1))))
    }

    private var items: [MemoryMediaItem] { fragment.orderedMediaItems }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(items.isEmpty ? "0 / 0" : "\(index + 1) / \(items.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { isShowingManagement = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("管理这条记忆")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                        Group {
                            if item.kind == .video {
                                VideoPlayer(
                                    player: AVPlayer(
                                        url: MemoryMediaLocation.applicationSupport().url(for: item.relativePath)
                                    )
                                )
                            } else {
                                MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                                    .scaledToFit()
                            }
                        }
                        .tag(itemIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(alignment: .leading, spacing: 8) {
                    if let text = fragment.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(MemoryFragmentRelativeTime.format(fragment.createdAt, now: context.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $isShowingManagement) {
            MemoryManagementSheet(
                isTextOnly: false,
                onEdit: {
                    isShowingManagement = false
                    onEdit()
                },
                onDelete: {
                    isShowingManagement = false
                    onDelete()
                },
                onCancel: { isShowingManagement = false }
            )
        }
    }
}

// MARK: - Unified editor

private enum MemoryEditorOperation: Equatable {
    case idle
    case importing(UInt64)
    case saving(UInt64)
}

private struct MemoryUnifiedEditorView: View {
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
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // The editor fills the screen, then puts back the actual
                        // container inset so the header sits below the status bar.
                        Color.clear
                            .frame(height: geometry.safeAreaInsets.top)
                        HStack(spacing: 10) {
                            Button(isImporting ? "停止" : "取消") { cancel() }
                                .font(.system(size: 13))
                                .foregroundColor(BSColor.Stage.muted)
                                .disabled(isSaving)
                                .frame(width: 52, alignment: .leading)
                            Spacer()
                            VStack(spacing: 2) {
                                Text(editorTitle)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(items.isEmpty ? "纯文字" : "\(items.count) 项媒体")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(BSColor.Stage.dim)
                            }
                            Spacer()
                            Color.clear.frame(width: 52, height: 1)
                        }
                        .frame(height: 58)

                        if isMediaComposer {
                            if !items.isEmpty {
                                draftPreview
                                    .padding(.top, 4)
                            }
                            HStack {
                                Text("点击查看 · 拖动调整顺序")
                                Spacer()
                                Text("最多 \(MemoryFragment.maximumMediaCount) 项")
                            }
                            .font(.system(size: 9.5))
                            .foregroundColor(BSColor.Stage.dim)
                            .padding(.horizontal, 2)
                            .padding(.top, 13)
                            mediaThumbs
                                .padding(.top, 8)
                        }

                        TextField(
                            items.isEmpty ? "这一刻，你想记下什么？" : "写点什么……（可选）",
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
                        .frame(minHeight: items.isEmpty ? 270 : 105, alignment: .top)
                        .padding(.top, 15)

                        HStack {
                            Text(items.isEmpty ? "最多 500 字" : "整组媒体共用一段文字")
                            Spacer()
                            Text("\(caption.count) / \(captionLimit)")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(BSColor.Stage.dim)
                        .padding(.top, 10)

                        Button(isSaving ? "保存中…" : (isEditing ? "保存修改" : "加入这场现场")) {
                            save()
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                        .disabled(operationBusy || !canSave)
                        .padding(.top, 15)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
                }
                .ignoresSafeArea(.container, edges: .top)
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
            .sheet(isPresented: $isShowingAddSource) {
                MemoryAddMediaSheet(
                    onCamera: {
                        replacementIndex = nil
                        isShowingAddSource = false
                        Task { @MainActor in
                            await Task.yield()
                            requestCamera()
                        }
                    },
                    onLibrary: {
                        replacementIndex = nil
                        isShowingAddSource = false
                        Task { @MainActor in
                            await Task.yield()
                            isPhotoPickerPresented = true
                        }
                    },
                    onCancel: { isShowingAddSource = false }
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

    private var editorTitle: String {
        if isEditing { return "编辑记忆" }
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
        if items.isEmpty { return "自动记录当前现场时间。" }
        return "像发一条私密动态，但不会公开发布。"
    }

    private var canSave: Bool {
        let hasText = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !items.isEmpty || hasText
    }

    private var captionLimit: Int { 500 }

    private var draftPreview: some View {
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
            .frame(height: 365)
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

    private func replaceCurrent() {
        guard items.indices.contains(selection) else { return }
        replacementIndex = selection
        if items[selection].mediaKind == .photo {
            requestCamera()
        } else {
            isPhotoPickerPresented = true
        }
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
            errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体。"
            return
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "当前设备无法使用相机。"
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
                    errorMessage = "没有相机权限。你可以在系统设置中允许访问。"
                }
            }
        case .denied, .restricted:
            errorMessage = "没有相机权限。你可以在系统设置中允许访问。"
        @unknown default:
            errorMessage = "当前无法使用相机。"
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
                errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体。"
                return
            }
            if isEditing, pickerItems.count > remaining, isCurrentImport(generation) {
                errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体，已只载入前 \(remaining) 个。"
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
                errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体。"
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
                    errorMessage = "相机入口只拍照片，视频请从相册选择。"
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
                return "所选媒体的临时文件已失效，请返回图库重新选择。"
            case .insufficientDiskSpace:
                return "设备储存空间不足，暂时无法保存。"
            case .unsupportedMedia:
                return "这个媒体格式暂不支持，请换一张照片或视频。"
            case .imageEncodingFailed:
                return "这张图片无法处理，请换一张图片后重试。"
            case .importCancelled:
                return "媒体导入已取消，请重新选择。"
            }
        }
        if let validationError = error as? MemoryFragmentValidationError {
            switch validationError {
            case .emptyContent:
                return "请保留至少一项媒体或一段文字。"
            case .textTooLong:
                return "文字最多 500 字。"
            case .mediaLimitExceeded:
                return "一条记忆最多 10 项媒体。"
            }
        }
        return "内容没有保存，请重试。"
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

// MARK: - Camera

private enum MemoryCameraResult {
    case photo(Data)
    case video(URL)
}

private struct SystemMemoryCameraPicker: UIViewControllerRepresentable {
    let onComplete: (MemoryCameraResult?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (MemoryCameraResult?) -> Void

        init(onComplete: @escaping (MemoryCameraResult?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let mediaType = info[.mediaType] as? String
            if mediaType == UTType.movie.identifier, let url = info[.mediaURL] as? URL {
                onComplete(.video(url))
                return
            }
            guard let image = info[.originalImage] as? UIImage else {
                onComplete(nil)
                return
            }
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let data = image.jpegData(compressionQuality: 0.92) else {
                    await MainActor.run { self?.onComplete(nil) }
                    return
                }
                await MainActor.run { self?.onComplete(.photo(data)) }
            }
        }
    }
}
