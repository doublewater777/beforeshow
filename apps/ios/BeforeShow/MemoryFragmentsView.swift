import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Presentation models

private enum MemoryComposerSource {
    case camera
    case photoLibrary
    case text
}

private struct MemoryEditorLaunch: Identifiable {
    enum Kind {
        case create(MemoryComposerSource)
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
    let showID: UUID
    let showName: String

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [MemoryFragment]
    @AppStorage("hasSeenMemoryFragmentsLocalNotice") private var hasSeenLocalNotice = false

    @State private var isShowingCreateOptions = false
    @State private var editorLaunch: MemoryEditorLaunch?
    @State private var deleteTarget: MemoryFragment?
    @State private var viewerTarget: MemoryViewerTarget?
    @State private var toast: BSToastPayload?
    @State private var isShowingLocalNotice = false

    init(showID: UUID, showName: String) {
        self.showID = showID
        self.showName = showName
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
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        header

                        if fragments.isEmpty {
                            BSEmptyPanel(
                                iconName: "sparkles.rectangle.stack",
                                title: "还没有记忆碎片",
                                message: "拍一张照片、从图库选择媒体，\n或者写下一段现场小记。"
                            )
                            .padding(.top, 32)
                        } else {
                            LazyVStack(alignment: .leading, spacing: BSSpacing.lg) {
                                ForEach(timelineSections, id: \.phase) { section in
                                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                                        HStack(spacing: BSSpacing.sm) {
                                            Text(section.phase.title)
                                                .font(.system(size: 11, weight: .semibold))
                                                .tracking(1.0)
                                                .foregroundColor(phaseColor(section.phase))
                                            Text("\(section.fragments.count) 条")
                                                .font(BSFont.caption)
                                                .foregroundColor(BSColor.Stage.dim)
                                            Rectangle()
                                                .fill(Color.white.opacity(0.09))
                                                .frame(height: 1)
                                        }

                                        ForEach(section.fragments) { fragment in
                                            MemoryFragmentRow(
                                                fragment: fragment,
                                                isLatest: fragment.id == fragments.first?.id,
                                                onEdit: {
                                                    editorLaunch = MemoryEditorLaunch(kind: .edit(fragment))
                                                },
                                                onDelete: { deleteTarget = fragment },
                                                onOpenMedia: { index in
                                                    viewerTarget = MemoryViewerTarget(
                                                        fragment: fragment,
                                                        initialIndex: index
                                                    )
                                                }
                                            )
                                            .id(fragment.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.md)
                    .padding(.bottom, 118)
                }
                .onChange(of: fragments.count) { oldCount, newCount in
                    guard newCount > oldCount, let firstID = fragments.first?.id else { return }
                    withAnimation { proxy.scrollTo(firstID, anchor: .top) }
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
                onCamera: { launchEditor(.camera) },
                onPhotoLibrary: { launchEditor(.photoLibrary) },
                onText: { launchEditor(.text) },
                onCancel: { isShowingCreateOptions = false }
            )
        }
        .sheet(item: $editorLaunch) { launch in
            MemoryUnifiedEditorView(
                launch: launch,
                showName: showName,
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
                        deleteTarget = target.fragment
                    }
                }
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
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            var validFilesByFragmentID: [UUID: Set<String>] = [:]
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
                showID: showID,
                validFilesByFragmentID: validFilesByFragmentID
            )
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
        }
    }

    private var header: some View {
        let stats = timelineStats
        return VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text("只保存在本机")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(BSColor.Stage.accent)
            Text(showName)
                .font(BSFont.title)
                .foregroundColor(BSColor.Stage.foreground)
            HStack(spacing: BSSpacing.lg) {
                timelineStat(value: "\(stats.memories)", label: "条记忆")
                timelineStat(value: "\(stats.photos)", label: "照片")
                timelineStat(value: "\(stats.videos)", label: "视频")
            }
            .padding(.top, 2)
        }
        .padding(BSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                .fill(BSColor.Stage.surface.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                        .stroke(BSColor.Stage.accent.opacity(0.15), lineWidth: 1)
                )
        )
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

    private func launchEditor(_ source: MemoryComposerSource) {
        isShowingCreateOptions = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            editorLaunch = MemoryEditorLaunch(kind: .create(source))
        }
    }

    private var timelineSections: [(phase: MemoryFragmentPhase, fragments: [MemoryFragment])] {
        MemoryFragmentPhase.timelineDisplayOrder.compactMap { phase in
            let items = fragments.filter { $0.phase == phase }
            guard !items.isEmpty else { return nil }
            return (phase, items)
        }
    }

    private var timelineStats: (memories: Int, photos: Int, videos: Int) {
        let photos = fragments.reduce(0) { partial, fragment in
            partial + fragment.mediaItems.filter { $0.kind == .photo }.count
        }
        let videos = fragments.reduce(0) { partial, fragment in
            partial + fragment.mediaItems.filter { $0.kind == .video }.count
        }
        return (fragments.count, photos, videos)
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
            let show = fetchShow(for: showID)
            let phase = resolvedPhase(for: show, at: Date())
            let fragment = try MemoryFragment(showID: showID, text: caption, phase: phase)
            fragment.show = show
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
            let show = fetchShow(for: showID)
            let phase = resolvedPhase(for: show, at: Date())
            let fragment = try MemoryFragment(id: fragmentID, showID: showID, text: caption, phase: phase)
            fragment.show = show
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
    private func saveEditedFragment(
        _ fragment: MemoryFragment,
        fullOrder: [UUID],
        caption: String,
        removedIDs: Set<UUID>,
        additions: [MemoryDraftMedia],
        draftID: UUID
    ) async throws {
        try fragment.updateText(caption)

        var removedPaths: [String] = []
        for item in fragment.orderedMediaItems where removedIDs.contains(item.id) {
            removedPaths.append(contentsOf: [item.relativePath, item.thumbnailRelativePath].compactMap { $0 })
            try fragment.removeMedia(item)
            modelContext.delete(item)
        }

        if fragment.mediaItems.isEmpty && additions.isEmpty {
            let normalized = try MemoryFragment.normalized(caption)
            guard normalized != nil else { throw MemoryFragmentValidationError.emptyContent }
        }

        if !additions.isEmpty {
            guard fragment.mediaItems.count + additions.count <= MemoryFragment.maximumMediaCount else {
                throw MemoryFragmentValidationError.mediaLimitExceeded
            }
            await MemoryFragmentMediaStore.shared.acquireCommitGate()
            let committed: [MemoryCommittedMedia]
            do {
                committed = try await MemoryFragmentMediaStore.shared.commitAdditions(
                    draftID: draftID,
                    showID: showID,
                    fragmentID: fragment.id,
                    media: additions
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
                    try fragment.appendMedia(MemoryMediaItem(
                        id: item.id,
                        kind: item.kind,
                        relativePath: item.relativePath,
                        thumbnailRelativePath: item.thumbnailRelativePath,
                        contentTypeIdentifier: item.contentTypeIdentifier,
                        videoDuration: item.videoDuration,
                        sortOrder: fragment.mediaItems.count
                    ))
                }
                // Draft IDs are preserved through commit, so fullOrder can include them.
                fragment.reorderMedia(orderedIDs: fullOrder)
                try modelContext.save()
            } catch {
                modelContext.rollback()
                try? await MemoryFragmentMediaStore.shared.rollbackCommittedFiles(relativePaths: committedPaths)
                await MemoryFragmentMediaStore.shared.releaseCommitGate()
                throw error
            }
            await MemoryFragmentMediaStore.shared.releaseCommitGate()
            try? await MemoryFragmentMediaStore.shared.finalizeCommit(draftID: draftID)
        } else {
            fragment.reorderMedia(orderedIDs: fullOrder)
            try modelContext.save()
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

// MARK: - Create source sheet

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

// MARK: - Timeline row

private struct MemoryFragmentRow: View {
    let fragment: MemoryFragment
    var isLatest = false
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpenMedia: (Int) -> Void

    var body: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.compact) {
                HStack {
                    Text(MemoryFragmentRelativeTime.format(fragment.createdAt))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isLatest ? BSColor.Stage.accent : BSColor.textTertiary)
                    Spacer()
                    Menu {
                        Button("编辑记忆", action: onEdit)
                        Button("删除", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    }
                    .foregroundColor(BSColor.textSecondary)
                }

                if !fragment.mediaItems.isEmpty {
                    MemoryMediaCarousel(items: fragment.orderedMediaItems) { index, _ in
                        onOpenMedia(index)
                    }
                }

                if let text = fragment.text {
                    Text(text)
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !fragment.mediaItems.isEmpty {
                    Text("\(fragment.mediaItems.count) 项媒体 · \(MemoryFragmentRelativeTime.exact(fragment.createdAt))")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                .stroke(isLatest ? BSColor.Stage.accent.opacity(0.28) : Color.clear, lineWidth: 1)
        )
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
                    Menu {
                        Button("编辑记忆", action: onEdit)
                        Button("删除", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
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
                    Text(MemoryFragmentRelativeTime.format(fragment.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Unified editor

private struct MemoryUnifiedEditorView: View {
    let launch: MemoryEditorLaunch
    let showName: String
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
    @State private var operationBusy = false
    @State private var errorMessage: String?
    @State private var activeImportTask: Task<Void, Never>?
    @State private var draggingID: UUID?

    private var isEditing: Bool {
        if case .edit = launch.kind { return true }
        return false
    }

    private var editingFragment: MemoryFragment? {
        if case .edit(let fragment) = launch.kind { return fragment }
        return nil
    }

    private var initialSource: MemoryComposerSource? {
        if case .create(let source) = launch.kind { return source }
        return nil
    }

    init(
        launch: MemoryEditorLaunch,
        showName: String,
        onSaveCreate: @escaping @MainActor (UUID, [MemoryDraftMedia], String) async throws -> Void,
        onSaveEdit: @escaping @MainActor (MemoryFragment, [UUID], String, Set<UUID>, [MemoryDraftMedia], UUID) async throws -> Void
    ) {
        self.launch = launch
        self.showName = showName
        self.onSaveCreate = onSaveCreate
        self.onSaveEdit = onSaveEdit

        switch launch.kind {
        case .create:
            _items = State(initialValue: [])
            _caption = State(initialValue: "")
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
        NavigationStack {
            ZStack {
                CurrentShowStageBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.md) {
                        if items.isEmpty {
                            BSEmptyPanel(
                                iconName: initialSource == .text ? "text.alignleft" : "photo.badge.plus",
                                title: initialSource == .text ? "写一段现场小记" : "选择照片或视频",
                                message: initialSource == .text
                                    ? "也可以稍后继续添加照片或视频。"
                                    : "可以混合选择，多项会保存为同一条记忆。"
                            )
                        } else {
                            draftPreview
                            thumbStrip
                        }

                        TextField(
                            items.isEmpty ? "这一刻，你想记下什么？" : "写点什么……（可选）",
                            text: $caption,
                            axis: .vertical
                        )
                        .lineLimit(items.isEmpty ? 8...14 : 3...8)
                        .onChange(of: caption) { _, value in
                            if value.count > 500 { caption = String(value.prefix(500)) }
                        }
                        .bsInputField()

                        HStack {
                            Text(items.isEmpty ? "最多 500 字" : "整组媒体共用一段文字 · 拖动缩略图排序")
                            Spacer()
                            Text("\(caption.count) / 500")
                        }
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)

                        Button(operationBusy ? "保存中…" : (isEditing ? "保存修改" : "加入这场现场")) {
                            save()
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                        .disabled(operationBusy || !canSave)
                    }
                    .padding(BSSpacing.roomy)
                }
            }
            .navigationTitle(isEditing ? "编辑记忆" : "新记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(operationBusy ? "停止" : "取消") { cancel() }
                        .disabled(operationBusy && activeImportTask == nil)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(isEditing ? "编辑记忆" : "新记忆")
                            .font(.system(size: 14.5, weight: .semibold))
                        Text(items.isEmpty ? "纯文字" : "\(items.count) 项媒体")
                            .font(.system(size: 10.5))
                            .foregroundColor(BSColor.textTertiary)
                    }
                }
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $selectedItems,
                maxSelectionCount: max(1, MemoryFragment.maximumMediaCount - items.count),
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
            .task {
                try? await Task.sleep(for: .milliseconds(320))
                switch initialSource {
                case .camera:
                    requestCamera()
                case .photoLibrary:
                    isPhotoPickerPresented = true
                case .text, .none:
                    break
                }
            }
        }
        .interactiveDismissDisabled(operationBusy)
    }

    private var canSave: Bool {
        let hasText = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !items.isEmpty || hasText
    }

    private var draftPreview: some View {
        VStack(spacing: BSSpacing.sm) {
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
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
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
                    Button("移除") { removeCurrent() }
                        .font(BSFont.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .foregroundStyle(Color(red: 1, green: 0.77, blue: 0.79))
                        .clipShape(Capsule())
                    Spacer()
                    Menu {
                        Button("继续拍照") { requestCamera() }
                        Button("从图库选择") { isPhotoPickerPresented = true }
                    } label: {
                        Text("继续添加")
                            .font(BSFont.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.55))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(items.count >= MemoryFragment.maximumMediaCount || operationBusy)
                }
                .padding(10)
            }
        }
    }

    private var thumbStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("点击查看 · 拖动调整顺序")
                Spacer()
                Text("最多 \(MemoryFragment.maximumMediaCount) 项")
            }
            .font(.system(size: 10.5))
            .foregroundColor(BSColor.Stage.dim)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        thumbCell(item: item, index: index)
                            .onDrag {
                                draggingID = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: MemoryThumbReorderDropDelegate(
                                    targetID: item.id,
                                    items: $items,
                                    draggingID: $draggingID,
                                    selection: $selection
                                )
                            )
                    }

                    if items.count < MemoryFragment.maximumMediaCount {
                        Menu {
                            Button("继续拍照") { requestCamera() }
                            Button("从图库选择") { isPhotoPickerPresented = true }
                        } label: {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundStyle(BSColor.Stage.accent)
                                .frame(width: 62, height: 76)
                                .overlay(
                                    Text("＋")
                                        .font(.system(size: 22))
                                        .foregroundStyle(BSColor.Stage.accent)
                                )
                        }
                        .disabled(operationBusy)
                    }
                }
            }
        }
    }

    private func thumbCell(item: MemoryEditorItem, index: Int) -> some View {
        Button {
            selection = index
        } label: {
            ZStack(alignment: .topTrailing) {
                MemoryThumbnail(relativePath: item.previewRelativePath)
                    .frame(width: 62, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                if item.mediaKind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .padding(4)
                }
                Text("\(index + 1)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        selection == index ? BSColor.Stage.accent : Color.white.opacity(0.09),
                        lineWidth: selection == index ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func removeCurrent() {
        guard items.indices.contains(selection) else { return }
        let removed = items.remove(at: selection)
        if case .existing(let id, _, _, _, _) = removed.kind {
            removedExistingIDs.insert(id)
        } else if case .draft(let draft) = removed.kind {
            Task { try? await MemoryFragmentMediaStore.shared.removeStagedItem(draft) }
        }
        selection = min(selection, max(0, items.count - 1))
    }

    private func requestCamera() {
        guard !operationBusy else { return }
        guard items.count < MemoryFragment.maximumMediaCount else {
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

    private func importLibrary(_ pickerItems: [PhotosPickerItem]) {
        activeImportTask?.cancel()
        activeImportTask = Task { @MainActor in
            operationBusy = true
            defer {
                operationBusy = false
                selectedItems = []
            }
            let remaining = MemoryFragment.maximumMediaCount - items.count
            guard remaining > 0 else {
                errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体。"
                return
            }
            if pickerItems.count > remaining {
                errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体，已只载入前 \(remaining) 个。"
            }
            for item in pickerItems.prefix(remaining) {
                if Task.isCancelled { return }
                do {
                    guard let imported = try await item.loadTransferable(type: MemoryImportedFile.self) else { continue }
                    let staged = try await MemoryFragmentMediaStore.shared.stageTransferredFile(
                        imported,
                        draftID: draftID
                    )
                    items.append(MemoryEditorItem(id: staged.id, kind: .draft(staged)))
                } catch is CancellationError {
                    return
                } catch {
                    errorMessage = "媒体没有载入，请重试。"
                }
            }
            selection = max(0, items.count - 1)
        }
    }

    private func importCamera(_ result: MemoryCameraResult) {
        activeImportTask?.cancel()
        activeImportTask = Task { @MainActor in
            operationBusy = true
            defer { operationBusy = false }
            guard items.count < MemoryFragment.maximumMediaCount else {
                errorMessage = "一条记忆最多 \(MemoryFragment.maximumMediaCount) 个媒体。"
                return
            }
            do {
                switch result {
                case .photo(let data):
                    let staged = try await MemoryFragmentMediaStore.shared.stageCameraPhoto(data, draftID: draftID)
                    items.append(MemoryEditorItem(id: staged.id, kind: .draft(staged)))
                case .video:
                    errorMessage = "App 内相机只拍照片，视频请从图库选择。"
                    return
                }
                selection = max(0, items.count - 1)
            } catch {
                errorMessage = "照片没有载入，请重试。"
            }
        }
    }

    private func save() {
        operationBusy = true
        Task { @MainActor in
            defer { operationBusy = false }
            do {
                let draftsInOrder = items.compactMap(\.draftMedia)
                // Keep editor visual order, including interleaved new drafts.
                // Draft IDs are preserved by MediaStore commit, so this list is the final order.
                let fullOrder = items.map(\.id)
                switch launch.kind {
                case .create:
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
                dismiss()
            } catch {
                errorMessage = "内容没有保存，请重试。"
            }
        }
    }

    private func cancel() {
        if operationBusy {
            activeImportTask?.cancel()
            activeImportTask = nil
            operationBusy = false
            return
        }
        let drafts = items.compactMap(\.draftMedia)
        Task {
            if !drafts.isEmpty {
                try? await MemoryFragmentMediaStore.shared.discardDraft(draftID)
            }
        }
        dismiss()
    }
}

// Drop delegate for thumbnail reorder.
private struct MemoryThumbReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var items: [MemoryEditorItem]
    @Binding var draggingID: UUID?
    @Binding var selection: Int

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != targetID,
              let from = items.firstIndex(where: { $0.id == draggingID }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            if let newSelection = items.firstIndex(where: { $0.id == draggingID }) {
                selection = newSelection
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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
