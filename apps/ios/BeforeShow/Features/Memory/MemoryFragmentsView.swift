import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// The show's memories as one sheet: a contact sheet of the night plus the three ways to add.
struct MemoryFragmentsSheet: View {
    let show: Show
    var pendingCreate: MemoryCreateSourceOption? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MemoryFragmentsView(show: show, pendingCreate: pendingCreate)
                .toolbar {
                    BSChromeToolbarCloseButton(accessibilityLabel: "关闭") { dismiss() }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

private struct MemoryViewerStart: Identifiable {
    let id: UUID
}

private struct DeletedFragmentSnapshot {
    let showID: UUID
    let text: String?
    let createdAt: Date
    let mediaItems: [MemoryMediaItemSnapshot]
}

private struct MemoryMediaItemSnapshot {
    let id: UUID
    let kind: MemoryMediaKind
    let relativePath: String
    let thumbPath: String?
    let contentType: String
    let duration: TimeInterval?
    let sortOrder: Int
}

/// 整晚一卷胶卷：开场前 / 现场 / 散场后 三段，每段一条齿孔胶片 + 时间范围。
/// 底部常驻玻璃输入栏（相册、写一句、大快门），点一格全屏看。
struct MemoryFragmentsView: View {
    let show: Show
    var pendingCreate: MemoryCreateSourceOption? = nil

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]

    @State private var draftText = ""
    @State private var viewerStart: MemoryViewerStart?
    @State private var newlyAddedIDs: Set<UUID> = []
    @State private var undoToastMessage: String?
    @State private var onUndoAction: (() -> Void)?
    @State private var undoDismissTask: Task<Void, Never>?

    // Camera & PhotosPicker
    @State private var isCameraPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var pickedPhotoItems: [PhotosPickerItem] = []
    @State private var didHandlePendingCreate = false
    @State private var cameraError: String?

    // Undo storage
    @State private var lastCreatedFragmentIDs: [UUID] = []
    @State private var lastDeletedSnapshot: DeletedFragmentSnapshot?

    init(show: Show, pendingCreate: MemoryCreateSourceOption? = nil) {
        self.show = show
        self.pendingCreate = pendingCreate
        let showID = show.id
        _fragments = Query(filter: #Predicate<MemoryFragment> { $0.showID == showID })
    }

    private var moments: [MemoryMoment] { MemoryMomentTimeline.moments(from: fragments) }

    private var currentPhase: MemoryFragmentPhase {
        MemoryFragmentPhase.resolved(at: Date(), timing: show.timingFields)
    }

    var body: some View {
        let moments = moments
        let sections = MemoryMomentTimeline.sections(moments, timing: show.timingFields)

        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(sections) { section in
                            FilmStripSectionView(
                                section: section,
                                timing: show.timingFields,
                                currentPhase: currentPhase,
                                newlyAddedIDs: newlyAddedIDs
                            ) { moment in
                                viewerStart = MemoryViewerStart(id: moment.id)
                            }
                        }

                        Color.clear.frame(height: 1).id("roll-bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                }
                .onChange(of: moments.count) { old, new in
                    if new > old {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            proxy.scrollTo("roll-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                if let message = undoToastMessage, let action = onUndoAction {
                    MemoryUndoToast(message: message, onUndo: action)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                MemoryRollInputBar(
                    draftText: $draftText,
                    onOpenLibrary: { isPhotosPickerPresented = true },
                    onSubmitText: submitText,
                    onShoot: openCamera
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(red: 6/255, green: 8/255, blue: 12/255).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(BSLocalization.text("记忆碎片"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(BSLocalization.format("%lld 格", moments.count))
                        .font(.system(size: 11))
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
        }
        .fullScreenCover(item: $viewerStart) { start in
            MemoryMomentViewer(show: show, startID: start.id) { deletedMoment in
                handleViewerDelete(deletedMoment)
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            SystemMemoryCameraPicker { result in
                isCameraPresented = false
                guard case .photo(let data) = result else { return }
                Task { @MainActor in
                    await savePhoto(data)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $pickedPhotoItems,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: pickedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotoItems = []
            Task { @MainActor in
                await saveLibraryItems(items)
            }
        }
        .alert(
            BSLocalization.text("无法继续"),
            isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })
        ) {
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                Button(BSLocalization.text("前往设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button(BSLocalization.text("知道了"), role: .cancel) {}
        } message: {
            Text(cameraError ?? "")
        }
        .task {
            handleInitialPendingCreate()
        }
        .task(id: fragments.map(\.id)) { await reconcileFiles() }
    }

    // MARK: - Capture Handlers

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            isPhotosPickerPresented = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            Task { @MainActor in
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isCameraPresented = true
                } else {
                    cameraError = BSLocalization.text("没有相机权限。你可以在系统设置中允许访问。")
                }
            }
        default:
            cameraError = BSLocalization.text("没有相机权限。你可以在系统设置中允许访问。")
        }
    }

    private func handleInitialPendingCreate() {
        guard let pending = pendingCreate, !didHandlePendingCreate else { return }
        didHandlePendingCreate = true
        if pending == .camera || pending == .quick {
            openCamera()
        } else if pending == .library {
            isPhotosPickerPresented = true
        }
    }

    private func submitText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftText = ""
        let beforeFragmentIDs = Set(fragments.map(\.id))
        Task { @MainActor in
            do {
                try await MemoryCaptureCoordinator.saveText(text, to: show, in: modelContext)
                let newFragIDs = fragments.filter { !beforeFragmentIDs.contains($0.id) }.map(\.id)
                highlightAndToastNewMoments(fragmentIDs: newFragIDs)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func savePhoto(_ data: Data) async {
        let beforeFragmentIDs = Set(fragments.map(\.id))
        do {
            try await MemoryCaptureCoordinator.saveCameraPhoto(data, to: show, in: modelContext)
            let newFragIDs = fragments.filter { !beforeFragmentIDs.contains($0.id) }.map(\.id)
            highlightAndToastNewMoments(fragmentIDs: newFragIDs)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func saveLibraryItems(_ items: [PhotosPickerItem]) async {
        let beforeFragmentIDs = Set(fragments.map(\.id))
        _ = await MemoryCaptureCoordinator.saveLibraryItems(items, to: show, in: modelContext)
        let newFragIDs = fragments.filter { !beforeFragmentIDs.contains($0.id) }.map(\.id)
        if !newFragIDs.isEmpty {
            highlightAndToastNewMoments(fragmentIDs: newFragIDs)
        }
    }

    private func highlightAndToastNewMoments(fragmentIDs: [UUID]) {
        lastCreatedFragmentIDs = fragmentIDs
        let newMoments = moments.filter { fragmentIDs.contains($0.fragment.id) }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            newlyAddedIDs = Set(newMoments.map(\.id))
        }

        let phaseTitle = currentPhase.rollTitle
        showUndoToast(message: BSLocalization.format("已存进「%@」", phaseTitle)) {
            undoAdd(fragmentIDs: fragmentIDs)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.5)) {
                newlyAddedIDs.removeAll()
            }
        }
    }

    private func undoAdd(fragmentIDs: [UUID]) {
        for id in fragmentIDs {
            if let target = fragments.first(where: { $0.id == id }) {
                modelContext.delete(target)
            }
        }
        try? modelContext.save()
        newlyAddedIDs.removeAll()
        hideUndoToast()
    }

    // MARK: - Viewer Delete & Undo

    private func handleViewerDelete(_ moment: MemoryMoment) {
        let fragment = moment.fragment
        let snapshot = DeletedFragmentSnapshot(
            showID: fragment.showID,
            text: fragment.text,
            createdAt: fragment.createdAt,
            mediaItems: fragment.mediaItems.map { item in
                MemoryMediaItemSnapshot(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbPath: item.thumbnailRelativePath,
                    contentType: item.contentTypeIdentifier,
                    duration: item.videoDuration,
                    sortOrder: item.sortOrder
                )
            }
        )
        lastDeletedSnapshot = snapshot

        Task { @MainActor in
            try? await MemoryMomentEditing.delete(moment, in: modelContext)
        }

        showUndoToast(message: BSLocalization.text("已删除")) {
            restoreDeletedSnapshot(snapshot)
        }
    }

    private func restoreDeletedSnapshot(_ snapshot: DeletedFragmentSnapshot) {
        do {
            let restored = try MemoryFragment(
                showID: snapshot.showID,
                text: snapshot.text,
                createdAt: snapshot.createdAt
            )
            for item in snapshot.mediaItems {
                let media = MemoryMediaItem(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbnailRelativePath: item.thumbPath,
                    contentTypeIdentifier: item.contentType,
                    videoDuration: item.duration,
                    sortOrder: item.sortOrder
                )
                try restored.appendMedia(media)
            }
            modelContext.insert(restored)
            try modelContext.save()
            hideUndoToast()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Toast Helpers

    private func showUndoToast(message: String, action: @escaping () -> Void) {
        undoDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            undoToastMessage = message
            onUndoAction = action
        }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            hideUndoToast()
        }
    }

    private func hideUndoToast() {
        withAnimation(.easeOut(duration: 0.25)) {
            undoToastMessage = nil
            onUndoAction = nil
        }
    }

    private func reconcileFiles() async {
        await MemoryFragmentMediaStore.shared.acquireCommitGate()
        let showID = show.id
        let descriptor = FetchDescriptor<MemoryFragment>(predicate: #Predicate<MemoryFragment> { $0.showID == showID })
        if let current = try? modelContext.fetch(descriptor) {
            var valid: [UUID: Set<String>] = [:]
            for fragment in current {
                valid[fragment.id] = Set(fragment.mediaItems.flatMap { [$0.relativePath, $0.thumbnailRelativePath].compactMap { $0 } })
            }
            try? await MemoryFragmentMediaStore.shared.reconcileFragmentFiles(showID: showID, validFilesByFragmentID: valid)
        }
        await MemoryFragmentMediaStore.shared.releaseCommitGate()
    }
}
