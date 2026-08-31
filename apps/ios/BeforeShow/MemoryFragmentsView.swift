import AVFoundation
import AVKit
import PhotosUI
import PostHog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Presentation models

private struct MemoryEditorLaunch: Identifiable, Hashable {
    enum Kind {
        case createText
        case createMedia(draftID: UUID, media: [MemoryDraftMedia])
        case edit(MemoryFragment)
    }

    let id = UUID()
    let kind: Kind

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct MemoryViewerTarget: Identifiable, Hashable {
    let id = UUID()
    let fragment: MemoryFragment
    let initialIndex: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

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

struct MemoryCreateSourceSheet: View {
    let onSelect: (MemoryCreateSourceOption) -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(MemoryCreateSourcePresentation.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(MemoryCreateSourcePresentation.message)
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 6)

                HStack(spacing: 10) {
                    ForEach(MemoryCreateSourceOption.allCases, id: \.self) { option in
                        MemorySourceOptionCard(
                            title: option.title,
                            icon: option.iconName,
                            action: { onSelect(option) }
                        )
                    }
                }
                .padding(.top, 17)
            }
        }
    }
}

private struct MemoryInternalPushes: ViewModifier {
    @Binding var editorLaunch: MemoryEditorLaunch?
    @Binding var viewerTarget: MemoryViewerTarget?
    let onCreate: @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void
    let onEdit: @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void
    let onViewerEdit: (MemoryFragment) -> Void
    let onViewerDelete: (MemoryFragment) -> Void
    let onViewerDismissed: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $editorLaunch) { launch in
                MemoryUnifiedEditorView(
                    launch: launch,
                    onSaveCreate: onCreate,
                    onSaveEdit: onEdit
                )
            }
            .fullScreenCover(item: $viewerTarget, onDismiss: onViewerDismissed) { target in
                MemoryMediaViewer(
                    fragment: target.fragment,
                    initialIndex: target.initialIndex,
                    onEdit: { onViewerEdit(target.fragment) },
                    onDelete: { onViewerDelete(target.fragment) }
                )
            }
    }
}

private extension View {
    func memoryInternalPushes(
        editorLaunch: Binding<MemoryEditorLaunch?>,
        viewerTarget: Binding<MemoryViewerTarget?>,
        onCreate: @escaping @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void,
        onEdit: @escaping @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void,
        onViewerEdit: @escaping (MemoryFragment) -> Void,
        onViewerDelete: @escaping (MemoryFragment) -> Void,
        onViewerDismissed: @escaping () -> Void
    ) -> some View {
        modifier(
            MemoryInternalPushes(
                editorLaunch: editorLaunch,
                viewerTarget: viewerTarget,
                onCreate: onCreate,
                onEdit: onEdit,
                onViewerEdit: onViewerEdit,
                onViewerDelete: onViewerDelete,
                onViewerDismissed: onViewerDismissed
            )
        )
    }
}

private enum MemoryPendingPresentation {
    case edit(MemoryFragment)
    case delete(MemoryFragment)
}

private enum MemoryCreateDestination {
    case text
    case library
    case camera
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
            Text("这场现场的记忆")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
            Text("照片、视频和小记都按现场阶段收在这里。")
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

@MainActor
enum MemoryFragmentEditCoordinator {
    static func save(
        _ fragment: MemoryFragment,
        showID: UUID,
        fullOrder: [UUID],
        caption: String,
        removedIDs: Set<UUID>,
        additions: [MemoryDraftMedia],
        draftID: UUID,
        modelContext: ModelContext
    ) async throws {
        let normalizedCaption = try MemoryFragment.normalized(caption)
        let remainingExisting = fragment.orderedMediaItems.filter { !removedIDs.contains($0.id) }
        if remainingExisting.isEmpty && additions.isEmpty {
            guard normalizedCaption != nil else { throw MemoryFragmentValidationError.emptyContent }
        }
        guard remainingExisting.count + additions.count <= MemoryFragment.maximumMediaCount else {
            throw MemoryFragmentValidationError.mediaLimitExceeded
        }

        let removedPaths = fragment.orderedMediaItems
            .filter { removedIDs.contains($0.id) }
            .flatMap { item in [item.relativePath, item.thumbnailRelativePath].compactMap { $0 } }

        var committed: [MemoryCommittedMedia] = []
        var committedPaths: [String] = []
        if !additions.isEmpty {
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            do {
                committed = try await MemoryFragmentMediaStore.shared.commitAdditions(
                    draftID: draftID,
                    showID: showID,
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
    }
}

private struct MemoryAddMediaSheet: View {
    let onCamera: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(292), fitsContent: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text("继续添加")
                    .font(.system(size: 18, weight: .semibold))
                Text("给当前这条记忆增加媒体")
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 6)
                HStack(spacing: 10) {
                    MemorySourceOptionCard(
                        title: BSLocalization.text("继续拍照"),
                        icon: "camera",
                        action: onCamera
                    )
                    MemorySourceOptionCard(
                        title: BSLocalization.text("从图库选择"),
                        icon: "photo.on.rectangle",
                        action: onLibrary
                    )
                }
                .padding(.top, 17)
            }
        }
    }
}

private struct MemorySourceOptionCard: View {
    let title: String
    let icon: String
    var height: CGFloat = 105
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 42, height: 42)
                    .background(BSColor.Stage.accent.opacity(0.10), in: Circle())
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BSColor.Stage.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline row

private struct MemoryTimelineSection: View {
    let phase: MemoryFragmentPhase
    let fragments: [MemoryFragment]
    let onEdit: (MemoryFragment) -> Void
    let onDelete: (MemoryFragment) -> Void
    let onOpenMedia: (MemoryFragment, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(phase.title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(phaseTitleColor)
                Text(BSLocalization.format("%lld 条", fragments.count))
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
                        onEdit: { onEdit(fragment) },
                        onDelete: { onDelete(fragment) },
                        onOpenMedia: { onOpenMedia(fragment, $0) }
                    )
                    .id(fragment.id)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94).combined(with: .opacity),
                            removal: .opacity
                        )
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
    let onEdit: () -> Void
    let onDelete: () -> Void
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
                    Menu {
                        Button("编辑记忆", action: onEdit)
                        Button("删除这条记忆", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.Stage.dim)
                            .frame(width: 32, height: 28)
                    }
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

struct MemoryThumbnail: View {
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

// MARK: - Shared review flow

/// Read/edit/delete flow shared by the memory timeline and the read-only footprint detail.
/// Creation stays owned by `MemoryFragmentsView`.
struct MemoryFragmentReviewView: View {
    let showID: UUID
    let fragment: MemoryFragment
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editorLaunch: MemoryEditorLaunch?
    @State private var deleteConfirmationTarget: MemoryFragment?
    @State private var toast: BSToastPayload?

    var body: some View {
        Group {
            if fragment.orderedMediaItems.isEmpty {
                MemoryTextFragmentViewer(
                    fragment: fragment,
                    onEdit: { presentEditorAfterManagementDismisses() },
                    onDelete: { presentDeleteAfterManagementDismisses() }
                )
            } else {
                MemoryMediaViewer(
                    fragment: fragment,
                    initialIndex: initialIndex,
                    onEdit: { presentEditorAfterManagementDismisses() },
                    onDelete: { presentDeleteAfterManagementDismisses() }
                )
            }
        }
        .bsToastOverlay(toast, bottomPadding: 36)
        .fullScreenCover(item: $editorLaunch) { launch in
            MemoryUnifiedEditorView(
                launch: launch,
                onSaveCreate: { _, _, _ in },
                onSaveEdit: { fragment, fullOrder, caption, removedIDs, additions, draftID in
                    try await MemoryFragmentEditCoordinator.save(
                        fragment,
                        showID: showID,
                        fullOrder: fullOrder,
                        caption: caption,
                        removedIDs: removedIDs,
                        additions: additions,
                        draftID: draftID,
                        modelContext: modelContext
                    )
                    presentToast(.success, "已保存修改")
                }
            )
        }
        .alert(
            DangerConfirmation.deleteMemory.title,
            isPresented: Binding(
                get: { deleteConfirmationTarget != nil },
                set: { if !$0 { deleteConfirmationTarget = nil } }
            ),
            presenting: deleteConfirmationTarget
        ) { target in
            Button(DangerConfirmation.deleteMemory.confirmTitle, role: .destructive) {
                deleteConfirmationTarget = nil
                delete(target)
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: { _ in
            Text(DangerConfirmation.deleteMemory.message)
        }
        .preferredColorScheme(.dark)
    }

    private func presentEditorAfterManagementDismisses() {
        editorLaunch = MemoryEditorLaunch(kind: .edit(fragment))
    }

    private func presentDeleteAfterManagementDismisses() {
        deleteConfirmationTarget = fragment
    }

    private func delete(_ fragment: MemoryFragment) {
        let fragmentID = fragment.id
        modelContext.delete(fragment)
        do {
            try modelContext.save()
            Task {
                try? await MemoryFragmentMediaStore.shared.deleteFragment(
                    showID: showID,
                    fragmentID: fragmentID
                )
            }
            dismiss()
        } catch {
            modelContext.rollback()
            presentToast(.failure, "删除失败，请重试")
        }
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

private struct MemoryTextFragmentViewer: View {
    let fragment: MemoryFragment
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.Stage.foreground)
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                            .background(BSColor.Stage.surfaceRaised, in: Circle())
                            .overlay(Circle().stroke(BSColor.Stage.border))
                    }
                    Spacer()
                    Text("记忆碎片")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Menu {
                        Button("编辑记忆", action: onEdit)
                        Button("删除这条记忆", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.Stage.foreground)
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                            .background(BSColor.Stage.surfaceRaised, in: Circle())
                            .overlay(Circle().stroke(BSColor.Stage.border))
                    }
                    .accessibilityLabel("管理这条记忆")
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)

                VStack(alignment: .leading, spacing: BSSpacing.roomy) {
                    Image(systemName: "quote.opening")
                        .font(BSFont.V3.title2.weight(.light))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(fragment.text ?? "")
                        .font(BSFont.V3.title2.weight(.regular))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineSpacing(BSSpacing.sm)
                    Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BSSpacing.roomy)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(BSColor.Stage.border))
                .padding(BSSpacing.roomy)

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(BSNavigationBackSwipeRestorer(onBack: { dismiss() }))
    }
}

// MARK: - Viewer

private struct MemoryMediaInteractionSurface: View {
    let kind: MemoryMediaKind
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .contextMenu {
                Button("编辑记忆", action: onEdit)
                Button("删除这条记忆", role: .destructive, action: onDelete)
            }
            .accessibilityLabel(kind == .video ? "视频" : "照片")
            .accessibilityHint("轻点关闭，长按管理")
            .accessibilityAction(named: "关闭", onDismiss)
            .accessibilityAction(named: "编辑记忆", onEdit)
            .accessibilityAction(named: "删除这条记忆", onDelete)
    }
}

private struct MemoryMediaViewer: View {
    let fragment: MemoryFragment
    let initialIndex: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

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
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { itemIndex, item in
                    ZStack {
                        mediaPage(item: item, isActive: itemIndex == index)
                        MemoryMediaInteractionSurface(
                            kind: item.kind,
                            onDismiss: { dismiss() },
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                    }
                    .tag(itemIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
        // The viewer plays video with sound, so it needs `playback`; restore the
        // ambient policy on exit so covers stay non-interrupting.
        .onAppear { AppAudioSession.configureSoundPlayback() }
        .onDisappear { AppAudioSession.configureAmbient() }
    }

    @ViewBuilder
    private func mediaPage(item: MemoryMediaItem, isActive: Bool) -> some View {
        if item.kind == .video {
            MemoryViewerVideoPage(
                url: MemoryMediaLocation.applicationSupport().url(for: item.relativePath),
                isActive: isActive
            )
        } else {
            MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                .scaledToFit()
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                        if isMediaComposer {
                            if !items.isEmpty {
                                draftPreview
                                    .padding(.top, 4)
                            }
                            HStack {
                                Text("点击查看 · 拖动调整顺序")
                                Spacer()
                                Text(BSLocalization.format("最多 %lld 项", MemoryFragment.maximumMediaCount))
                            }
                            .font(.system(size: 9.5))
                            .foregroundColor(BSColor.Stage.dim)
                            .padding(.horizontal, 2)
                            .padding(.top, 13)
                            mediaThumbs
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
                        .frame(minHeight: items.isEmpty ? 270 : 105, alignment: .top)
                        .padding(.top, 15)

                        HStack {
                            Text(items.isEmpty ? BSLocalization.text("最多 500 字") : BSLocalization.text("整组媒体共用一段文字"))
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
        .scrollDismissesKeyboard(.interactively)
        .background(BSColor.Stage.background.ignoresSafeArea())
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
            defer { finishSave(generation) }
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
