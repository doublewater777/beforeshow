import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Face state

enum DynamicCoverFaceStore {
    private static let keyPrefix = "dynamic-cover-face-v1-"

    static func isDynamicFace(for showID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: keyPrefix + showID.uuidString)
    }

    static func setDynamicFace(_ isDynamic: Bool, for showID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(isDynamic, forKey: keyPrefix + showID.uuidString)
    }

    static func clear(showID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyPrefix + showID.uuidString)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

enum DynamicCoverAccessibilityPolicy {
    static func shouldExposeAddVideoAction(
        hasDynamicCover: Bool,
        hasChooseVideoAction: Bool
    ) -> Bool {
        !hasDynamicCover && hasChooseVideoAction
    }
}

private struct DynamicCoverAddVideoAccessibilityModifier: ViewModifier {
    let isAvailable: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAvailable {
            content.accessibilityAction(named: "添加动态封面视频", action)
        } else {
            content
        }
    }
}

// MARK: - Cover faces

/// A show-bound cover with a static primary face and an optional video face.
/// The dynamic face is deliberately only played while it is frontmost and active.
struct DynamicCoverFlipView<StaticFace: View>: View {
    let showID: UUID
    let dynamicCover: DynamicCover?
    let width: CGFloat
    let height: CGFloat
    let isPlaybackActive: Bool
    let reduceMotion: Bool
    let onChooseVideo: (() -> Void)?
    private let staticFace: () -> StaticFace

    @State private var isDynamicFace: Bool
    @State private var mediaURL: URL?

    init(
        showID: UUID,
        dynamicCover: DynamicCover?,
        width: CGFloat,
        height: CGFloat,
        isPlaybackActive: Bool,
        reduceMotion: Bool,
        onChooseVideo: (() -> Void)? = nil,
        @ViewBuilder staticFace: @escaping () -> StaticFace
    ) {
        self.showID = showID
        self.dynamicCover = dynamicCover
        self.width = width
        self.height = height
        self.isPlaybackActive = isPlaybackActive
        self.reduceMotion = reduceMotion
        self.onChooseVideo = onChooseVideo
        self.staticFace = staticFace
        _isDynamicFace = State(initialValue: dynamicCover != nil && DynamicCoverFaceStore.isDynamicFace(for: showID))
    }

    private var canFlip: Bool { dynamicCover != nil && mediaURL != nil }
    private var faceDescription: String { isDynamicFace ? "动态封面" : "静态封面" }

    private func chooseVideoFromAccessibility() {
        guard dynamicCover == nil else { return }
        onChooseVideo?()
    }

    var body: some View {
        ZStack {
            if reduceMotion {
                staticFace()
                    .opacity(isDynamicFace ? 0 : 1)
                dynamicFace
                    .opacity(isDynamicFace ? 1 : 0)
            } else {
                staticFace()
                    .rotation3DEffect(
                        .degrees(isDynamicFace ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.72
                    )
                    .opacity(isDynamicFace ? 0 : 1)
                dynamicFace
                    .rotation3DEffect(
                        .degrees(isDynamicFace ? 0 : -180),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.72
                    )
                    .opacity(isDynamicFace ? 1 : 0)
            }

            if dynamicCover == nil, let onChooseVideo {
                Button(action: onChooseVideo) {
                    Label("添加动态封面", systemImage: "plus.circle.fill")
                        .font(BSFont.V3.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, BSSpacing.compact)
                        .padding(.vertical, BSSpacing.sm)
                        .background(.black.opacity(0.48), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加动态封面视频")
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard canFlip else { return }
                    let nextFace = !isDynamicFace
                    withAnimation(.easeInOut(duration: reduceMotion ? 0.25 : 0.55)) {
                        isDynamicFace = nextFace
                    }
                    DynamicCoverFaceStore.setDynamicFace(nextFace, for: showID)
                }
        )
        .task(id: dynamicCover?.relativePath) {
            guard let dynamicCover else {
                mediaURL = nil
                isDynamicFace = false
                return
            }
            mediaURL = try? await DynamicCoverMediaStore.shared.absoluteURL(
                for: dynamicCover.relativePath,
                showID: showID
            )
            if mediaURL == nil {
                isDynamicFace = false
            }
        }
        .onChange(of: dynamicCover?.id) { _, newID in
            guard newID != nil else {
                isDynamicFace = false
                DynamicCoverFaceStore.clear(showID: showID)
                return
            }
            isDynamicFace = DynamicCoverFaceStore.isDynamicFace(for: showID)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("现场封面，当前为\(faceDescription)")
        .accessibilityHint(canFlip ? "长按翻转动态封面" : "暂无动态封面")
        .accessibilityAction(named: "显示静态封面") {
            guard canFlip else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.25 : 0.55)) { isDynamicFace = false }
            DynamicCoverFaceStore.setDynamicFace(false, for: showID)
        }
        .accessibilityAction(named: "显示动态封面") {
            guard canFlip else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.25 : 0.55)) { isDynamicFace = true }
            DynamicCoverFaceStore.setDynamicFace(true, for: showID)
        }
        .modifier(
            DynamicCoverAddVideoAccessibilityModifier(
                isAvailable: DynamicCoverAccessibilityPolicy.shouldExposeAddVideoAction(
                    hasDynamicCover: dynamicCover != nil,
                    hasChooseVideoAction: onChooseVideo != nil
                ),
                action: chooseVideoFromAccessibility
            )
        )
    }

    @ViewBuilder
    private var dynamicFace: some View {
        if let mediaURL {
            DynamicCoverPlaybackView(
                url: mediaURL,
                isPlaying: isDynamicFace && isPlaybackActive
            )
        } else {
            ZStack {
                BSColor.Stage.surfaceRaised
                Image(systemName: "play.rectangle")
                    .font(BSFont.heroTitle.weight(.light))
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
    }
}

/// Local video surface for management and historical previews.
struct DynamicCoverVideoPreviewView: View {
    let showID: UUID
    let cover: DynamicCover
    let isPlaying: Bool

    @State private var mediaURL: URL?

    var body: some View {
        Group {
            if let mediaURL {
                DynamicCoverPlaybackView(url: mediaURL, isPlaying: isPlaying)
            } else {
                ZStack {
                    BSColor.Stage.surfaceRaised
                    ProgressView().tint(BSColor.Stage.muted)
                }
            }
        }
        .task(id: cover.relativePath) {
            mediaURL = try? await DynamicCoverMediaStore.shared.absoluteURL(
                for: cover.relativePath,
                showID: showID
            )
        }
        .clipped()
    }
}

// MARK: - Management

struct DynamicCoverManagementSection: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: PhotosPickerItem?
    @State private var importTask: Task<Void, Never>?
    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var isShowingDeleteConfirmation = false
    @State private var coverPendingDeletion: DynamicCover?

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("动态封面")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                if show.dynamicCover != nil {
                    Text("已添加")
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.accent)
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.compact) {
                if let cover = show.dynamicCover {
                    DynamicCoverVideoPreviewView(showID: show.id, cover: cover, isPlaying: false)
                        .frame(maxWidth: .infinity)
                        .frame(height: 164)
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                        .overlay(alignment: .bottomLeading) {
                            Text("封面背面 · 默认静音")
                                .font(BSFont.V3.caption)
                                .foregroundColor(.white.opacity(0.86))
                                .padding(.horizontal, BSSpacing.sm)
                                .padding(.vertical, BSSpacing.xs)
                                .background(.black.opacity(0.42), in: Capsule())
                                .padding(BSSpacing.sm)
                        }

                    HStack(spacing: BSSpacing.sm) {
                        coverActionButton("更换视频", icon: "arrow.triangle.2.circlepath") {
                            isPickerPresented = true
                        }
                        .disabled(isImporting)
                        coverActionButton("删除", icon: "trash", tint: BSColor.Stage.danger) {
                            coverPendingDeletion = cover
                            isShowingDeleteConfirmation = true
                        }
                        .disabled(isImporting)
                    }
                } else {
                    HStack(spacing: BSSpacing.compact) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(BSColor.Stage.accent)
                            .frame(width: 36, height: 36)
                            .background(BSColor.Stage.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text("给这场现场加一面动态封面")
                                .font(BSFont.V3.small.weight(.medium))
                                .foregroundColor(BSColor.Stage.foreground)
                            Text("导入一段不超过 15 秒的视频")
                                .font(BSFont.V3.caption)
                                .foregroundColor(BSColor.Stage.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    coverActionButton("添加视频", icon: "plus") {
                        isPickerPresented = true
                    }
                }

                if isImporting {
                    HStack(spacing: BSSpacing.sm) {
                        ProgressView().tint(BSColor.Stage.accent)
                        Text("正在准备视频…")
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.muted)
                    }
                }
            }
            .padding(BSSpacing.compact)
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border, lineWidth: 1))
        }
        .photosPicker(
            isPresented: $isPickerPresented,
            selection: $selectedItem,
            matching: .videos
        )
        .onChange(of: selectedItem) { _, item in
            guard let item, !isImporting else { return }
            importTask?.cancel()
            isImporting = true
            importTask = Task { @MainActor in
                await importVideo(item)
            }
        }
        .onDisappear {
            importTask?.cancel()
        }
        .alert("删除动态封面？", isPresented: $isShowingDeleteConfirmation) {
            Button("删除", role: .destructive) {
                if let coverPendingDeletion {
                    Task { @MainActor in await deleteCover(coverPendingDeletion) }
                }
                coverPendingDeletion = nil
            }
            Button("取消", role: .cancel) { coverPendingDeletion = nil }
        } message: {
            Text("删除后这段视频将从这场现场移除。")
        }
        .alert(
            "动态封面没有更新",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请重试")
        }
    }

    private func coverActionButton(
        _ title: String,
        icon: String,
        tint: Color = BSColor.Stage.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(BSFont.V3.caption.weight(.medium))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func importVideo(_ item: PhotosPickerItem) async {
        defer {
            selectedItem = nil
            isImporting = false
            importTask = nil
        }
        do {
            try await DynamicCoverImportCoordinator.importVideo(item, for: show, in: modelContext)
        } catch is CancellationError {
            return
        } catch let error as DynamicCoverMediaStoreError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "视频没有载入，请重试。"
        }
    }

    @MainActor
    private func deleteCover(_ cover: DynamicCover) async {
        await LocalMediaCommitGate.shared.acquire()
        let relativePath = cover.relativePath
        do {
            guard show.dynamicCover?.id == cover.id else {
                await LocalMediaCommitGate.shared.release()
                return
            }
            modelContext.delete(cover)
            show.dynamicCover = nil
            try modelContext.save()
            DynamicCoverFaceStore.clear(showID: show.id)
            do {
                try await DynamicCoverMediaStore.shared.delete(relativePath: relativePath, showID: show.id)
            } catch {
                ShowAssetCleanupRetry.markDynamicCoverCleanupPending(
                    showID: show.id,
                    relativePath: relativePath
                )
            }
        } catch {
            modelContext.rollback()
            errorMessage = "动态封面没有删除，请重试。"
        }
        await LocalMediaCommitGate.shared.release()
    }

    private static func message(for error: DynamicCoverMediaStoreError) -> String {
        switch error {
        case .fileTooLarge: return "视频太大，最多支持 100 MB。"
        case .invalidDuration: return "视频需要短于 15 秒。"
        case .unsupportedVideo, .missingVideoTrack: return "这个文件不是可用的视频。"
        case .insufficientDiskSpace: return "设备存储空间不足。"
        case .staleReplacement: return "现场信息已变化，请重新选择视频。"
        default: return "视频没有载入，请重试。"
        }
    }
}

@MainActor
enum DynamicCoverImportCoordinator {
    static func importVideo(
        _ item: PhotosPickerItem,
        for show: Show,
        in modelContext: ModelContext
    ) async throws {
        let expectedCoverID = show.dynamicCover?.id
        let draftID = UUID()
        var committedPath: String?
        var modelSaveCompleted = false
        await LocalMediaCommitGate.shared.acquire()
        defer {
            Task { await LocalMediaCommitGate.shared.release() }
        }

        do {
            guard let imported = try await item.loadTransferable(type: DynamicCoverImportedFile.self) else {
                throw DynamicCoverMediaStoreError.importCancelled
            }
            let staged = try await DynamicCoverMediaStore.shared.stageTransferredFile(imported, draftID: draftID)
            guard !Task.isCancelled else {
                try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
                throw CancellationError()
            }
            guard show.dynamicCover?.id == expectedCoverID else {
                try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
                throw DynamicCoverMediaStoreError.staleReplacement
            }
            let committed = try await DynamicCoverMediaStore.shared.commit(
                draftID: draftID,
                showID: show.id,
                video: staged
            )
            committedPath = committed.relativePath
            try Task.checkCancellation()
            let oldCover = show.dynamicCover
            let oldPath = oldCover?.relativePath
            if let oldCover {
                oldCover.replaceVideo(
                    relativePath: committed.relativePath,
                    contentTypeIdentifier: committed.contentTypeIdentifier,
                    videoDuration: committed.videoDuration
                )
                oldCover.source = .manual
            } else {
                let cover = DynamicCover(
                    id: committed.id,
                    showID: show.id,
                    relativePath: committed.relativePath,
                    contentTypeIdentifier: committed.contentTypeIdentifier,
                    source: .manual,
                    videoDuration: committed.videoDuration
                )
                cover.show = show
                show.dynamicCover = cover
                modelContext.insert(cover)
            }
            do {
                try modelContext.save()
                modelSaveCompleted = true
            } catch {
                modelContext.rollback()
                try? await DynamicCoverMediaStore.shared.rollbackCommittedFile(relativePath: committed.relativePath)
                try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
                throw error
            }
            try await DynamicCoverMediaStore.shared.finalizeCommit(draftID: draftID)
            if let oldPath, oldPath != committed.relativePath {
                do {
                    try await DynamicCoverMediaStore.shared.delete(relativePath: oldPath, showID: show.id)
                } catch {
                    ShowAssetCleanupRetry.markDynamicCoverCleanupPending(
                        showID: show.id,
                        relativePath: oldPath
                    )
                }
            }
        } catch {
            try? await DynamicCoverMediaStore.shared.discardDraft(draftID)
            if let committedPath, !modelSaveCompleted {
                try? await DynamicCoverMediaStore.shared.rollbackCommittedFile(relativePath: committedPath)
            }
            throw error
        }
    }
}

// MARK: - Footprint preview

struct FootprintDynamicCoverSection: View {
    let show: Show
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = false

    var body: some View {
        if let cover = show.dynamicCover {
            VStack(alignment: .leading, spacing: BSSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    Text("动态封面")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Text(isPlaying ? "播放中" : "已暂停")
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.dim)
                }

                Button {
                    isPlaying.toggle()
                } label: {
                    ZStack {
                        DynamicCoverVideoPreviewView(
                            showID: show.id,
                            cover: cover,
                            isPlaying: isPlaying && scenePhase == .active
                        )
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.42)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(BSFont.heroTitle.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "暂停动态封面" : "播放动态封面")
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active { isPlaying = false }
            }
            .onDisappear { isPlaying = false }
        }
    }
}
