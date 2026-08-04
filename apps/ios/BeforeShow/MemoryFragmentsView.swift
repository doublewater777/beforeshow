import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum MemoryComposerSource {
    case camera
    case photoLibrary
}

private struct MemoryComposerLaunch: Identifiable {
    let id = UUID()
    let source: MemoryComposerSource
}

private struct MemoryTextEditorTarget: Identifiable {
    let id = UUID()
    let fragment: MemoryFragment?
    let text: String
}

struct MemoryFragmentsView: View {
    let showID: UUID
    let showName: String

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]
    @AppStorage("hasSeenMemoryFragmentsLocalNotice") private var hasSeenLocalNotice = false

    @State private var isShowingCreateOptions = false
    @State private var composerLaunch: MemoryComposerLaunch?
    @State private var textEditorTarget: MemoryTextEditorTarget?
    @State private var mediaManagerTarget: MemoryFragment?
    @State private var deleteTarget: MemoryFragment?
    @State private var toast: BSToastPayload?
    @State private var isShowingLocalNotice = false

    init(showID: UUID, showName: String) {
        self.showID = showID
        self.showName = showName
        _fragments = Query(
            filter: #Predicate<MemoryFragment> { $0.showID == showID },
            sort: [SortDescriptor(\MemoryFragment.createdAt), SortDescriptor(\MemoryFragment.id)]
        )
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        header

                        if fragments.isEmpty {
                            BSEmptyPanel(
                                iconName: "sparkles.rectangle.stack",
                                title: "还没有记忆碎片",
                                message: "照片、视频或一句话，\n都可以留在这一场现场里。"
                            )
                            .padding(.top, 32)
                        } else {
                            LazyVStack(spacing: BSSpacing.md) {
                                ForEach(fragments) { fragment in
                                    MemoryFragmentRow(
                                        fragment: fragment,
                                        onEditText: {
                                            textEditorTarget = MemoryTextEditorTarget(
                                                fragment: fragment,
                                                text: fragment.text ?? ""
                                            )
                                        },
                                        onManageMedia: { mediaManagerTarget = fragment },
                                        onDelete: { deleteTarget = fragment }
                                    )
                                    .id(fragment.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.md)
                    .padding(.bottom, 118)
                }
                .onChange(of: fragments.count) { oldCount, newCount in
                    guard newCount > oldCount, let lastID = fragments.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
        .navigationTitle("记忆碎片")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { isShowingCreateOptions = true } label: {
                Label("新增记忆", systemImage: "plus")
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .padding(.horizontal, BSSpacing.roomy)
            .padding(.top, BSSpacing.compact)
            .padding(.bottom, BSLayout.floatingTabBarClearance - 20)
            .background(.ultraThinMaterial)
        }
        .bsToastOverlay(toast, bottomPadding: 92)
        .sheet(isPresented: $isShowingCreateOptions) {
            MemoryCreateSheet(
                onCamera: { launchComposer(.camera) },
                onPhotoLibrary: { launchComposer(.photoLibrary) },
                onText: {
                    isShowingCreateOptions = false
                    textEditorTarget = MemoryTextEditorTarget(fragment: nil, text: "")
                },
                onCancel: { isShowingCreateOptions = false }
            )
        }
        .sheet(item: $composerLaunch) { launch in
            MemoryMediaComposerView(
                launch: launch,
                showName: showName,
                onSave: { media, caption in
                    try await createMediaFragment(draftID: launch.id, media: media, caption: caption)
                }
            )
        }
        .sheet(item: $textEditorTarget) { target in
            MemoryTextComposerView(
                initialText: target.text,
                allowsEmptyText: target.fragment.map { !$0.mediaItems.isEmpty } ?? false
            ) { text in
                try saveText(text, editing: target.fragment)
            }
        }
        .sheet(item: $mediaManagerTarget) { fragment in
            MemoryMediaManagerView(
                fragment: fragment,
                showName: showName,
                onAdd: { draftID, media in
                    try await addMedia(draftID: draftID, media: media, to: fragment)
                },
                onDeleteItem: { item in
                    try deleteMedia(item, from: fragment)
                },
                onDeleteLastItem: {
                    mediaManagerTarget = nil
                    Task { @MainActor in
                        await Task.yield()
                        deleteTarget = fragment
                    }
                }
            )
        }
        .sheet(item: $deleteTarget) { fragment in
            BSDangerConfirmationSheet(
                title: "删除这条记忆？",
                message: "文字和 App 内保存的照片或视频将一起删除，且无法恢复。",
                destructiveTitle: "删除",
                onConfirm: {
                    deleteTarget = nil
                    delete(fragment)
                },
                onCancel: { deleteTarget = nil }
            )
        }
        .alert("只保存在这台设备上", isPresented: $isShowingLocalNotice) {
            Button("知道了") {
                hasSeenLocalNotice = true
            }
        } message: {
            Text("删除 App 或清除本地数据后，记忆碎片可能无法恢复。")
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--skip-memory-local-notice") {
                hasSeenLocalNotice = true
                return
            }
            #endif
            if !hasSeenLocalNotice {
                isShowingLocalNotice = true
            }
        }
        .task(id: fragments.map(\.id)) {
            // Gated so this per-show reconcile cannot delete a concurrent commit's
            // files. Fetch a fresh snapshot from the context *inside* the gate (not the
            // SwiftUI @Query value captured at task start) so the valid set is consistent
            // with any commit that holds the gate. Staging cleanup is launch-only
            // (BeforeShowApp) so it never evicts a draft still in use or awaiting retry.
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            var validFilesByFragmentID: [UUID: Set<String>] = [:]
            let descriptor = FetchDescriptor<MemoryFragment>(
                predicate: #Predicate<MemoryFragment> { $0.showID == showID }
            )
            // A fetch failure must NOT be treated as an authoritative empty set:
            // reconcileFragmentFiles with an empty valid set would delete the whole
            // show's media. Abort (release the gate) and let the next pass retry.
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
                showID: showID,
                validFilesByFragmentID: validFilesByFragmentID
            )
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Text(showName)
                .font(BSFont.title)
                .foregroundColor(BSColor.Stage.foreground)
            Text("\(fragments.count) 条 · 仅保存在本机")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
        }
    }

    private func launchComposer(_ source: MemoryComposerSource) {
        isShowingCreateOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            composerLaunch = MemoryComposerLaunch(source: source)
        }
    }

    private func saveText(_ text: String, editing fragment: MemoryFragment?) throws {
        do {
            if let fragment {
                try fragment.updateText(text)
            } else {
                let fragment = try MemoryFragment(showID: showID, text: text)
                guard fragment.text != nil else { throw MemoryFragmentValidationError.emptyContent }
                // Bind the Show relationship immediately so new text fragments don't
                // rely on reconciliation to backfill it.
                fragment.show = fetchShow(for: showID)
                modelContext.insert(fragment)
            }
            try modelContext.save()
            presentToast(.success, "已加入这场现场")
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @MainActor
    private func createMediaFragment(
        draftID: UUID,
        media: [MemoryDraftMedia],
        caption: String
    ) async throws {
        guard !media.isEmpty else { throw MemoryFragmentValidationError.emptyContent }
        let fragmentID = UUID()
        // Hold the commit gate across copy + SwiftData save so a reconciliation pass
        // cannot take a stale snapshot and delete these just-committed files.
        await MemoryFragmentMediaStore.shared.acquireCommitGate()
        let committed: [MemoryCommittedMedia]
        do {
            committed = try await MemoryFragmentMediaStore.shared.commit(
                draftID: draftID,
                showID: showID,
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
            let fragment = try MemoryFragment(id: fragmentID, showID: showID, text: caption)
            fragment.show = fetchShow(for: showID)
            for (index, item) in committed.enumerated() {
                fragment.appendMedia(MemoryMediaItem(
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
        // DB is authoritative after save; staging cleanup failures must not delete final media.
        try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
        presentToast(.success, "已加入这场现场")
    }

    private func fetchShow(for id: UUID) -> Show? {
        var descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func delete(_ fragment: MemoryFragment) {
        let fragmentID = fragment.id
        modelContext.delete(fragment)
        do {
            try modelContext.save()
            Task {
                try? await MemoryFragmentMediaStore.shared.deleteFragment(showID: showID, fragmentID: fragmentID)
            }
            presentToast(.success, "已删除这条记忆")
        } catch {
            modelContext.rollback()
            presentToast(.failure, "删除失败，请重试")
        }
    }

    @MainActor
    private func addMedia(
        draftID: UUID,
        media: [MemoryDraftMedia],
        to fragment: MemoryFragment
    ) async throws {
        await MemoryFragmentMediaStore.shared.acquireCommitGate()
        let committed: [MemoryCommittedMedia]
        do {
            committed = try await MemoryFragmentMediaStore.shared.commitAdditions(
                draftID: draftID,
                showID: showID,
                fragmentID: fragment.id,
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
            for item in committed {
                fragment.appendMedia(MemoryMediaItem(
                    id: item.id,
                    kind: item.kind,
                    relativePath: item.relativePath,
                    thumbnailRelativePath: item.thumbnailRelativePath,
                    contentTypeIdentifier: item.contentTypeIdentifier,
                    videoDuration: item.videoDuration,
                    sortOrder: fragment.mediaItems.count
                ))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            try? await MemoryFragmentMediaStore.shared.rollbackCommittedFiles(relativePaths: committedPaths)
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            throw error
        }
        await MemoryFragmentMediaStore.shared.releaseCommitGate()
        try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
    }

    private func deleteMedia(_ item: MemoryMediaItem, from fragment: MemoryFragment) throws {
        let paths = [item.relativePath, item.thumbnailRelativePath].compactMap { $0 }
        do {
            try fragment.removeMedia(item)
            modelContext.delete(item)
            try modelContext.save()
            Task { try? await MemoryFragmentMediaStore.shared.deleteFiles(relativePaths: paths) }
        } catch {
            modelContext.rollback()
            throw error
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

private struct MemoryCreateSheet: View {
    let onCamera: () -> Void
    let onPhotoLibrary: () -> Void
    let onText: () -> Void
    let onCancel: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(330)) {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                Text("新增记忆")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                createButton("相机", icon: "camera", action: onCamera)
                createButton("相册", icon: "photo.on.rectangle", action: onPhotoLibrary)
                createButton("文字", icon: "text.alignleft", action: onText)
                Button("取消", action: onCancel)
                    .buttonStyle(BSSecondaryButtonStyle())
            }
        }
    }

    private func createButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BSSecondaryButtonStyle())
    }
}

private struct MemoryTextComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?
    let allowsEmptyText: Bool
    let onSave: (String) throws -> Void

    init(
        initialText: String,
        allowsEmptyText: Bool = false,
        onSave: @escaping (String) throws -> Void
    ) {
        _text = State(initialValue: initialText)
        self.allowsEmptyText = allowsEmptyText
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground().ignoresSafeArea()
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("这一刻，你想记下什么？")
                                .font(BSFont.body)
                                .foregroundColor(BSColor.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $text)
                            .scrollContentBackground(.hidden)
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textPrimary)
                            .frame(minHeight: 220)
                            .onChange(of: text) { _, value in
                                if value.count > 500 { text = String(value.prefix(500)) }
                            }
                    }
                    .padding(BSSpacing.compact)
                    .bsCard()

                    HStack {
                        Text(Date(), format: .dateTime.year().month().day().hour().minute())
                        Spacer()
                        Text("\(text.count) / 500")
                    }
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)

                    Button("加入这场现场") { save() }
                        .buttonStyle(BSPrimaryButtonStyle())
                        .disabled(!allowsEmptyText && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(BSSpacing.roomy)
            }
            .navigationTitle("现场小记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("没有保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
        }
    }

    private func save() {
        do {
            try onSave(text)
            dismiss()
        } catch {
            errorMessage = "内容没有保存，请重试。"
        }
    }
}

private struct MemoryFragmentRow: View {
    let fragment: MemoryFragment
    let onEditText: () -> Void
    let onManageMedia: () -> Void
    let onDelete: () -> Void
    @State private var videoURL: URL?

    var body: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.compact) {
                HStack {
                    Text(fragment.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                    Spacer()
                    Menu {
                        Button(fragment.mediaItems.isEmpty ? "编辑" : "编辑说明", action: onEditText)
                        if !fragment.mediaItems.isEmpty {
                            Button("管理照片和视频", action: onManageMedia)
                        }
                        Button("删除", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    }
                    .foregroundColor(BSColor.textSecondary)
                }

                if !fragment.mediaItems.isEmpty {
                    MemoryMediaCarousel(items: fragment.orderedMediaItems) { item in
                        guard item.kind == .video else { return }
                        videoURL = MemoryMediaLocation.applicationSupport().url(for: item.relativePath)
                    }
                }

                if let text = fragment.text {
                    Text(text)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { videoURL != nil },
            set: { if !$0 { videoURL = nil } }
        )) {
            if let videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .ignoresSafeArea()
            }
        }
    }
}

private struct MemoryMediaCarousel: View {
    let items: [MemoryMediaItem]
    let onTap: (MemoryMediaItem) -> Void
    @State private var selection = 0

    var body: some View {
        VStack(spacing: BSSpacing.sm) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { onTap(item) } label: {
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
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .onChange(of: items.map(\.id)) { _, _ in
                selection = min(selection, max(0, items.count - 1))
            }

            if items.count > 1 {
                Text("\(selection + 1) / \(items.count)")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
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
            // Decoding full-size JPEGs synchronously in the SwiftUI body stalls the UI
            // (especially in carousels); decode off the main thread and cache the result.
            let path = MemoryMediaLocation.applicationSupport().url(for: relativePath).path
            let loaded = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)
            }.value
            image = loaded
        }
    }
}

private struct MemoryMediaManagerView: View {
    let fragment: MemoryFragment
    let showName: String
    let onAdd: (UUID, [MemoryDraftMedia]) async throws -> Void
    let onDeleteItem: (MemoryMediaItem) throws -> Void
    let onDeleteLastItem: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var composerLaunch: MemoryComposerLaunch?
    @State private var deleteTarget: MemoryMediaItem?
    @State private var isConfirmingLastDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground().ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: BSSpacing.compact) {
                        ForEach(fragment.orderedMediaItems) { item in
                            HStack(spacing: BSSpacing.compact) {
                                MemoryThumbnail(relativePath: item.thumbnailRelativePath ?? item.relativePath)
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                                    Label(
                                        item.kind == .photo ? "照片" : "视频",
                                        systemImage: item.kind == .photo ? "photo" : "video"
                                    )
                                    .font(BSFont.caption)
                                    .foregroundColor(BSColor.textPrimary)
                                    if let duration = item.videoDuration {
                                        Text(durationText(duration))
                                            .font(BSFont.caption)
                                            .foregroundColor(BSColor.textTertiary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    if fragment.mediaItems.count == 1, fragment.text == nil {
                                        isConfirmingLastDeletion = true
                                    } else {
                                        deleteTarget = item
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                                }
                            }
                            .padding(BSSpacing.compact)
                            .bsCard()
                        }
                    }
                    .padding(BSSpacing.roomy)
                }
            }
            .navigationTitle("管理照片和视频")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("相机") { composerLaunch = MemoryComposerLaunch(source: .camera) }
                        Button("相册") { composerLaunch = MemoryComposerLaunch(source: .photoLibrary) }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $composerLaunch) { launch in
                MemoryMediaComposerView(
                    launch: launch,
                    showName: showName,
                    showsCaptionField: false,
                    onSave: { media, _ in try await onAdd(launch.id, media) }
                )
            }
            .sheet(item: $deleteTarget) { item in
                BSDangerConfirmationSheet(
                    title: "删除这个媒体？",
                    message: "只会删除 BeforeShow 保存的副本，不会删除系统相册中的原始内容。",
                    destructiveTitle: "删除",
                    onConfirm: {
                        deleteTarget = nil
                        do { try onDeleteItem(item) }
                        catch { errorMessage = "媒体没有删除，请重试。" }
                    },
                    onCancel: { deleteTarget = nil }
                )
            }
            .alert("删除最后一个媒体？", isPresented: $isConfirmingLastDeletion) {
                Button("继续", role: .destructive) {
                    dismiss()
                    onDeleteLastItem()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这条记忆没有文字，删除最后一个媒体后，整条记忆也会被删除。下一步仍会再次确认。")
            }
            .alert("没有完成", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MemoryMediaComposerView: View {
    let launch: MemoryComposerLaunch
    let showName: String
    var showsCaptionField = true
    let onSave: ([MemoryDraftMedia], String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var media: [MemoryDraftMedia] = []
    @State private var caption = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    private enum ComposerOperation {
        case idle
        case importing
        case saving
        case removing
    }

    private static let maximumMediaCount = 20

    @State private var isShowingAddOptions = false
    @State private var operation: ComposerOperation = .idle
    @State private var progressText: String?
    @State private var errorMessage: String?
    @State private var selection = 0
    @State private var activeImportTask: Task<Void, Never>?
    @State private var importGeneration = 0

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground().ignoresSafeArea()
                VStack(spacing: BSSpacing.md) {
                    if media.isEmpty {
                        BSEmptyPanel(
                            iconName: "photo.badge.plus",
                            title: "选择照片或视频",
                            message: "可以混合选择，多项会保存为同一条记忆。"
                        )
                    } else {
                        draftCarousel
                    }

                    if showsCaptionField {
                        TextField("写点什么……（可选）", text: $caption, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: caption) { _, value in
                                if value.count > 500 { caption = String(value.prefix(500)) }
                            }
                            .bsInputField()
                    }

                    HStack(spacing: BSSpacing.compact) {
                        Button("继续添加") { isShowingAddOptions = true }
                            .buttonStyle(BSSecondaryButtonStyle())
                            .disabled(operation != .idle || media.count >= Self.maximumMediaCount)
                        if !media.isEmpty {
                            Button("删除当前项", role: .destructive) {
                                removeCurrentItem()
                            }
                            .buttonStyle(BSSecondaryButtonStyle())
                            .disabled(operation != .idle)
                        }
                    }

                    if let progressText {
                        HStack(spacing: BSSpacing.sm) {
                            ProgressView().tint(BSColor.textPrimary)
                            Text(progressText)
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textSecondary)
                        }
                    }

                    VStack(spacing: 2) {
                        Text("仅自己可见")
                        Text("仅保存在本机")
                    }
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)

                    Button("加入这场现场") { save() }
                        .buttonStyle(BSPrimaryButtonStyle())
                        .disabled(media.isEmpty || operation != .idle)
                }
                .padding(BSSpacing.roomy)
            }
            .navigationTitle("新记忆 · \(showName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(operation == .importing ? "停止" : "取消") { cancel() }
                        .disabled(operation == .saving || operation == .removing)
                }
            }
            .interactiveDismissDisabled()
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedItems,
                maxSelectionCount: max(1, Self.maximumMediaCount - media.count),
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                startImport { await importItems(items) }
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                SystemMemoryCameraPicker { result in
                    isCameraPresented = false
                    guard let result else { return }
                    startImport { await importCameraResult(result) }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("继续添加", isPresented: $isShowingAddOptions) {
                Button("相机") { requestCamera() }
                Button("相册") { isPhotoPickerPresented = true }
                Button("取消", role: .cancel) {}
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
                Button("取消", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "请稍后重试。")
            }
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                switch launch.source {
                case .camera: requestCamera()
                case .photoLibrary: isPhotoPickerPresented = true
                }
            }
        }
    }

    private var draftCarousel: some View {
        VStack(spacing: BSSpacing.sm) {
            TabView(selection: $selection) {
                ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                    ZStack {
                        MemoryThumbnail(relativePath: item.thumbnailStagedRelativePath ?? item.stagedRelativePath)
                        if item.kind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 46))
                                .foregroundStyle(.white)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            Text("\(selection + 1) / \(media.count)")
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
        }
    }

    private func requestCamera() {
        guard operation == .idle else { return }
        guard media.count < Self.maximumMediaCount else {
            errorMessage = "一条记忆最多 \(Self.maximumMediaCount) 个媒体。"
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

    private func startImport(_ work: @escaping @MainActor () async -> Void) {
        guard operation == .idle else {
            errorMessage = "正在处理媒体，请稍后再继续添加。"
            selectedItems = []
            return
        }
        importGeneration += 1
        let generation = importGeneration
        operation = .importing
        activeImportTask = Task { @MainActor in
            await work()
            if generation == importGeneration, operation == .importing {
                operation = .idle
                progressText = nil
                activeImportTask = nil
            }
        }
    }

    @MainActor
    private func importItems(_ items: [PhotosPickerItem]) async {
        defer { selectedItems = [] }
        let remaining = Self.maximumMediaCount - media.count
        guard remaining > 0 else {
            errorMessage = "一条记忆最多 \(Self.maximumMediaCount) 个媒体。"
            return
        }
        let accepted = Array(items.prefix(remaining))
        if items.count > remaining {
            errorMessage = "一条记忆最多 \(Self.maximumMediaCount) 个媒体，已只载入前 \(remaining) 个。"
        }
        for (index, item) in accepted.enumerated() {
            if Task.isCancelled { return }
            progressText = "正在处理 \(index + 1) / \(accepted.count)"
            do {
                guard let imported = try await item.loadTransferable(type: MemoryImportedFile.self) else {
                    throw MemoryMediaStoreError.unsupportedMedia
                }
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: imported.url)
                    return
                }
                media.append(try await MemoryFragmentMediaStore.shared.stageTransferredFile(imported, draftID: launch.id))
            } catch is CancellationError {
                return
            } catch MemoryMediaStoreError.insufficientDiskSpace {
                errorMessage = "可用空间不足，未能载入全部媒体。"
                return
            } catch {
                errorMessage = "第 \(index + 1) 个媒体没有载入，请重试。"
                return
            }
        }
        selection = max(0, media.count - 1)
    }

    @MainActor
    private func importCameraResult(_ result: MemoryCameraResult) async {
        guard media.count < Self.maximumMediaCount else {
            errorMessage = "一条记忆最多 \(Self.maximumMediaCount) 个媒体。"
            return
        }
        progressText = "正在处理拍摄内容"
        do {
            if Task.isCancelled { return }
            switch result {
            case .photo(let data):
                media.append(try await MemoryFragmentMediaStore.shared.stageCameraPhoto(data, draftID: launch.id))
            case .video(let url):
                media.append(try await MemoryFragmentMediaStore.shared.stageTransferredFile(
                    MemoryImportedFile(url: url, contentType: .movie),
                    draftID: launch.id
                ))
            }
            selection = media.count - 1
        } catch is CancellationError {
            return
        } catch MemoryMediaStoreError.insufficientDiskSpace {
            errorMessage = "可用空间不足，拍摄内容没有载入。"
        } catch {
            errorMessage = "拍摄内容没有载入，请重试。"
        }
    }

    private func removeCurrentItem() {
        guard operation == .idle else { return }
        guard media.indices.contains(selection) else { return }
        let removed = media[selection]
        // Enter a dedicated removing state synchronously so save / 继续添加 / 再次删除 /
        // 取消 are blocked until the on-disk deletion completes. Only drop the item from
        // the array if the deletion fully succeeds, so a failure leaves the quota intact
        // and no uncounted staging file is left behind.
        operation = .removing
        Task { @MainActor in
            do {
                try await MemoryFragmentMediaStore.shared.removeStagedItem(removed)
                media.removeAll { $0.id == removed.id }
                selection = min(selection, max(0, media.count - 1))
            } catch {
                errorMessage = "媒体没有删除，请重试。"
            }
            operation = .idle
        }
    }

    private func save() {
        guard operation == .idle else { return }
        guard !media.isEmpty else { return }
        operation = .saving
        Task {
            do {
                try await onSave(media, caption)
                dismiss()
            } catch {
                operation = .idle
                errorMessage = "记忆没有保存，草稿仍然保留。"
            }
        }
    }

    private func cancel() {
        guard operation != .saving else { return }
        activeImportTask?.cancel()
        activeImportTask = nil
        importGeneration += 1
        operation = .idle
        progressText = nil
        selectedItems = []
        Task {
            try? await MemoryFragmentMediaStore.shared.discardDraft(launch.id)
            dismiss()
        }
    }
}

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
        if let available = UIImagePickerController.availableMediaTypes(for: .camera) {
            picker.mediaTypes = available.filter { type in
                type == UTType.image.identifier || type == UTType.movie.identifier
            }
        }
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
            // Full-size JPEG encoding is CPU-heavy; run it off the main thread so the
            // picker callback (and picker dismissal) stay responsive.
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
