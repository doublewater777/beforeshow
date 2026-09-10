import AVFoundation
import AVKit
import PhotosUI
import PostHog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Scoped memory task: sheet for the list, push for editor, full-screen cover for media viewer.
struct MemoryFragmentsSheet: View {
    let show: Show
    var pendingCreate: MemoryCreateSourceOption? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MemoryFragmentsView(show: show, pendingCreate: pendingCreate)
                .toolbar {
                    BSChromeToolbarCloseButton(accessibilityLabel: "取消") { dismiss() }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Timeline

struct MemoryFragmentsView: View {
    let show: Show
    var pendingCreate: MemoryCreateSourceOption? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]
    @State private var isShowingCreateOptions = false
    @State private var editorLaunch: MemoryEditorLaunch?
    @State private var didAutoOpenCreate = false
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var selectedCreateMedia: [PhotosPickerItem] = []
    @State private var directImportTask: Task<Void, Never>?
    @State private var directImportDraftID: UUID?
    @State private var pendingCameraResult: MemoryCameraResult?
    @State private var pendingPresentation: MemoryPendingPresentation?
    @State private var pendingCreateDestination: MemoryCreateDestination?
    @State private var createSourceError: String?
    @State private var pendingDelete: MemoryFragment?
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var viewerTarget: MemoryViewerTarget?

    @State private var deleteConfirmationTarget: MemoryFragment?
    @State private var toast: BSToastPayload?

    init(show: Show, pendingCreate: MemoryCreateSourceOption? = nil) {
        self.show = show
        self.pendingCreate = pendingCreate
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
                        header
                            .padding(.top, 4)

                        if visibleFragments.isEmpty {
                            timelineEmptyState
                        } else {
                            ForEach(timelineSections, id: \.phase) { section in
                                MemoryTimelineSection(
                                    phase: section.phase,
                                    fragments: section.fragments,
                                    onEdit: openExistingEditor,
                                    onDelete: confirmDeleteFragment,
                                    onOpenMedia: openViewer
                                )
                                .id(section.phase)
                                }
                        }

                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: fragments.count)
                    .padding(.bottom, 96)
                }
                .bsNavigationScrollEdge()
                .onChange(of: fragments.count) { oldCount, newCount in
                    guard newCount > oldCount, let firstID = fragments.first?.id else { return }
                    withAnimation { proxy.scrollTo(firstID, anchor: .top) }
                }
            }
        }
        .navigationTitle("记忆碎片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) {
            Button {
                guard directImportTask == nil else { return }
                isShowingCreateOptions = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 54, height: 54)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
            .accessibilityLabel("新增记忆")
            .disabled(directImportTask != nil)
            .opacity(directImportTask != nil ? 0.5 : 1)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .bsToastOverlay(toast, bottomPadding: 80)
       .overlay(alignment: .bottom) {
           if pendingDelete != nil {
               HStack(spacing: BSSpacing.md) {
                    Text(BSLocalization.text("已删除这条记忆"))
                       .font(BSFont.caption)
                       .foregroundColor(BSColor.Stage.foreground)
                    Button(BSLocalization.text("撤销"), action: undoDelete)
                       .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                }
                .padding(.horizontal, BSSpacing.md)
                .padding(.vertical, BSSpacing.compact)
                .background(Color.black.opacity(0.86), in: Capsule())
                .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
                .padding(.bottom, 80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: pendingDelete?.id)
        .sheet(isPresented: $isShowingCreateOptions) {
            MemoryCreateSourceSheet { option in
                beginCreate(from: option)
            }
        }
        .onChange(of: isShowingCreateOptions) { _, isShowing in
            if !isShowing {
                performPendingCreateDestination()
            }
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
        .fullScreenCover(isPresented: $isCameraPresented, onDismiss: {
            guard let result = pendingCameraResult else { return }
            pendingCameraResult = nil
            importDirectCameraResult(result)
        }) {
            SystemMemoryCameraPicker { result in
                isCameraPresented = false
                pendingCameraResult = result
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
        .memoryInternalPushes(
            editorLaunch: $editorLaunch,
            viewerTarget: $viewerTarget,
            onCreate: createFragment,
            onEdit: saveEditedFragment,
            onViewerEdit: { fragment in
                pendingPresentation = .edit(fragment)
                viewerTarget = nil
            },
            onViewerDelete: { fragment in
                pendingPresentation = .delete(fragment)
                viewerTarget = nil
            },
            onViewerDismissed: performPendingPresentation
        )
        .task {
            guard let pendingCreate, !didAutoOpenCreate else { return }
            didAutoOpenCreate = true
            beginCreate(from: pendingCreate)
            performPendingCreateDestination()
        }
        .alert(
            DangerConfirmation.deleteMemory.title,
            isPresented: Binding(
                get: { deleteConfirmationTarget != nil },
                set: { if !$0 { deleteConfirmationTarget = nil } }
            ),
            presenting: deleteConfirmationTarget
        ) { fragment in
            Button(DangerConfirmation.deleteMemory.confirmTitle, role: .destructive) {
                deleteConfirmationTarget = nil
                stageDelete(fragment)
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: { _ in
            Text(DangerConfirmation.deleteMemory.message)
        }

        .onDisappear {
            cancelDirectImport()
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

    private var header: some View {
        let stats = timelineStats
        return VStack(alignment: .leading, spacing: BSSpacing.sm) {
           Text(headerEyebrow)
               .font(.system(size: 10, weight: .semibold))
               .tracking(1.1)
               .foregroundColor(BSColor.Stage.accent)
            Text(BSLocalization.text("这场现场的记忆"))
               .font(.system(size: 20, weight: .bold))
               .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("照片、视频和小记都按现场阶段收在这里。"))
               .font(.system(size: 11))
               .foregroundColor(BSColor.Stage.muted)
            HStack(spacing: BSSpacing.lg) {
                timelineStat(value: "\(stats.memories)", label: BSLocalization.text("条记忆"))
                timelineStat(value: "\(stats.photos)", label: BSLocalization.text("照片"))
                timelineStat(value: "\(stats.videos)", label: BSLocalization.text("视频"))
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


    private var timelineEmptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(BSColor.Stage.muted)
               .frame(width: 68, height: 68)
               .background(Color.white.opacity(0.04), in: Circle())
               .overlay(Circle().stroke(BSColor.Stage.border, lineWidth: 1))
            Text(BSLocalization.text("还没有记忆碎片"))
               .font(.system(size: 20, weight: .regular))
               .foregroundColor(BSColor.Stage.foreground)
               .padding(.top, 18)
            Text(BSLocalization.text("拍一张照片、选择一段短视频，\n或者写下此刻的一句话。"))
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

    private func createDestination(for option: MemoryCreateSourceOption) -> MemoryCreateDestination {
        switch option {
        case .camera: return .camera
        case .library: return .library
        case .text: return .text
        }
    }

    private func beginCreate(from option: MemoryCreateSourceOption) {
        switch option {
        case .text:
            editorLaunch = MemoryEditorLaunch(kind: .createText)
            isShowingCreateOptions = false
        case .library, .camera:
            pendingCreateDestination = createDestination(for: option)
            isShowingCreateOptions = false
        }
    }

    private func performPendingCreateDestination() {
        guard let destination = pendingCreateDestination else { return }
        pendingCreateDestination = nil
        switch destination {
        case .text:
            editorLaunch = MemoryEditorLaunch(kind: .createText)
        case .library:
            guard directImportTask == nil else { return }
            selectedCreateMedia = []
            isPhotoPickerPresented = true
        case .camera:
            guard directImportTask == nil else { return }
            Task { @MainActor in
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                createSourceError = BSLocalization.text("当前设备无法使用相机。")
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                isCameraPresented = true
            case .notDetermined:
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isCameraPresented = true
                } else {
createSourceError = BSLocalization.text("没有相机权限。你可以在系统设置中允许访问。")
                }
            case .denied, .restricted:
                createSourceError = "没有相机权限。你可以在系统设置中允许访问。"
            @unknown default:
                createSourceError = BSLocalization.text("当前无法使用相机。")
            }
            }
        }
    }

    private func importDirectLibrarySelection(_ pickerItems: [PhotosPickerItem]) {
        selectedCreateMedia = []
        guard directImportTask == nil else { return }
        let draftID = UUID()
        directImportDraftID = draftID
        directImportTask = Task { @MainActor in
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
                    directImportDraftID = nil
                    directImportTask = nil
                    createSourceError = "媒体没有载入，请重试。"
                    return
                }
                guard !Task.isCancelled else {
                    try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                    directImportDraftID = nil
                    directImportTask = nil
                    return
                }
                directImportDraftID = nil
                directImportTask = nil
                editorLaunch = MemoryEditorLaunch(kind: .createMedia(draftID: draftID, media: stagedItems))
            } catch {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                directImportDraftID = nil
                directImportTask = nil
                guard !Task.isCancelled else { return }
                createSourceError = "媒体没有载入，请重试。"
            }
        }
    }

    private func importDirectCameraResult(_ result: MemoryCameraResult) {
        guard directImportTask == nil else { return }
        let draftID = UUID()
        directImportDraftID = draftID
        directImportTask = Task { @MainActor in
            do {
                guard case .photo(let data) = result else {
                    directImportDraftID = nil
                    directImportTask = nil
                    createSourceError = BSLocalization.text("相机入口只拍照片，视频请从相册选择。")
                    return
                }
                let staged = try await MemoryFragmentMediaStore.shared.stageCameraPhoto(data, draftID: draftID)
                guard !Task.isCancelled else {
                    try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                    directImportDraftID = nil
                    directImportTask = nil
                    return
                }
                directImportDraftID = nil
                directImportTask = nil
                editorLaunch = MemoryEditorLaunch(kind: .createMedia(draftID: draftID, media: [staged]))
            } catch {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
                directImportDraftID = nil
                directImportTask = nil
                guard !Task.isCancelled else { return }
                createSourceError = "照片没有载入，请重试。"
            }
        }
    }

    private func cancelDirectImport() {
        guard let task = directImportTask else { return }
        let draftID = directImportDraftID
        directImportTask = nil
        directImportDraftID = nil
        task.cancel()
        Task { @MainActor in
            await task.value
            if let draftID {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
            }
        }
    }

    private func openExistingEditor(_ fragment: MemoryFragment) {
        guard directImportTask == nil else { return }
        editorLaunch = MemoryEditorLaunch(kind: .edit(fragment))
    }

    private func confirmDeleteFragment(_ fragment: MemoryFragment) {
        guard directImportTask == nil else { return }
        deleteConfirmationTarget = fragment
    }

    private func openViewer(_ fragment: MemoryFragment, index: Int) {
        guard directImportTask == nil else { return }
        viewerTarget = MemoryViewerTarget(fragment: fragment, initialIndex: index)
    }

    private func performPendingPresentation() {
        guard let pendingPresentation else { return }
        self.pendingPresentation = nil
        switch pendingPresentation {
        case .edit(let fragment):
            editorLaunch = MemoryEditorLaunch(kind: .edit(fragment))
        case .delete(let fragment):
            deleteConfirmationTarget = fragment
        }
    }

    private var timelineSections: [(phase: MemoryFragmentPhase, fragments: [MemoryFragment])] {
        MemoryFragmentPhase.timelineDisplayOrder.compactMap { phase in
            let items = visibleFragments.filter {
                resolvedPhase(for: show, at: $0.createdAt) == phase
            }
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
            PostHogSDK.shared.capture("memory_fragment_created", properties: ["has_media": false, "media_count": 0])
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
        PostHogSDK.shared.capture("memory_fragment_created", properties: ["has_media": true, "media_count": media.count])
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
        try await MemoryFragmentEditCoordinator.save(
            fragment,
            showID: show.id,
            fullOrder: fullOrder,
            caption: caption,
            removedIDs: removedIDs,
            additions: additions,
            draftID: draftID,
            modelContext: modelContext
        )
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
