import PhotosUI
import SwiftData
import SwiftUI
import UIKit

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

    static func shouldExposeFaceActions(canFlip: Bool) -> Bool {
        canFlip
    }

    static func hint(canFlip: Bool, opensDetail: Bool) -> String {
        switch (opensDetail, canFlip) {
        case (true, true):
            return BSLocalization.text("轻点查看现场详情，长按翻转动态封面")
        case (true, false):
            return BSLocalization.text("轻点查看现场详情")
        case (false, true):
            return BSLocalization.text("长按翻转动态封面，轻点返回静态封面")
        case (false, false):
            return BSLocalization.text("暂无动态封面")
        }
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

private struct DynamicCoverFaceAccessibilityModifier: ViewModifier {
    let isAvailable: Bool
    let showStaticFace: () -> Void
    let showDynamicFace: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAvailable {
            content
                .accessibilityAction(named: BSLocalization.text("显示静态封面")) { showStaticFace() }
                .accessibilityAction(named: "显示动态封面") { showDynamicFace() }
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
    let opensDetail: Bool
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
        opensDetail: Bool = false,
        accessibilityName: String? = nil,
        @ViewBuilder staticFace: @escaping () -> StaticFace
    ) {
        self.showID = showID
        self.dynamicCover = dynamicCover
        self.width = width
        self.height = height
        self.isPlaybackActive = isPlaybackActive
        self.reduceMotion = reduceMotion
        self.onChooseVideo = onChooseVideo
        self.opensDetail = opensDetail
        self.accessibilityName = accessibilityName
        self.staticFace = staticFace
        _isDynamicFace = State(initialValue: dynamicCover != nil && DynamicCoverFaceStore.isDynamicFace(for: showID))
    }

    private let accessibilityName: String?

    /// 已上传视频时翻向播放面；未上传时翻向带「选择视频」入口的空状态背面。
    private var canFlip: Bool { mediaURL != nil || (dynamicCover == nil && onChooseVideo != nil) }
    private var faceDescription: String { isDynamicFace ? BSLocalization.text("动态封面") : BSLocalization.text("静态封面") }

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

        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard canFlip else { return }
                flip(to: !isDynamicFace, haptic: true)
            }
        )
        .task(id: dynamicCoverRevision) {
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
            // A newly imported/replaced video is the user's explicit request to
            // see the dynamic side. Update local state immediately; the persisted
            // preference is written by the import transaction as well.
            isDynamicFace = true
            DynamicCoverFaceStore.setDynamicFace(true, for: showID)
        }
        .onChange(of: dynamicCover?.relativePath) { oldPath, newPath in
            guard oldPath != nil, newPath != nil, oldPath != newPath else { return }
            flip(to: true, haptic: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [accessibilityName.map { BSLocalization.format("现场封面，%@", $0) } ?? BSLocalization.text("现场封面"), BSLocalization.format("当前为%@", faceDescription)]
                .joined(separator: "，")
        )
        .accessibilityAddTraits(opensDetail ? .isButton : [])
        .accessibilityHint(DynamicCoverAccessibilityPolicy.hint(canFlip: canFlip, opensDetail: opensDetail))
        .modifier(
            DynamicCoverFaceAccessibilityModifier(
                isAvailable: DynamicCoverAccessibilityPolicy.shouldExposeFaceActions(canFlip: canFlip),
                showStaticFace: { flip(to: false, haptic: false) },
                showDynamicFace: { flip(to: true, haptic: false) }
            )
        )
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

    private var dynamicCoverRevision: String? {
        guard let dynamicCover else { return nil }
        return "\(dynamicCover.id.uuidString)|\(dynamicCover.relativePath)|\(dynamicCover.updatedAt.timeIntervalSince1970)"
    }

    private func flip(to dynamicFace: Bool, haptic: Bool) {
        guard dynamicFace != isDynamicFace else { return }
        if haptic {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // Spring instead of easeInOut so the user can grab the cover mid-flip
        // and reverse it without a velocity discontinuity — Apple §3 Interruptibility,
        // §4 Springs. reduceMotion keeps the same animation family but damps to
        // 1.0 to drop the bounce rather than swapping in a different curve.
        withAnimation(.spring(
            response: 0.4,
            dampingFraction: reduceMotion ? 1.0 : 0.85
        )) {
            isDynamicFace = dynamicFace
        }
        DynamicCoverFaceStore.setDynamicFace(dynamicFace, for: showID)
    }

    @ViewBuilder
    private var dynamicFace: some View {
        if let mediaURL {
            DynamicCoverPlaybackView(
                url: mediaURL,
                isPlaying: isDynamicFace && isPlaybackActive
            )
        } else if dynamicCover == nil, let onChooseVideo {
            emptyDynamicFace(onChooseVideo: onChooseVideo)
        } else {
            ZStack {
                BSColor.Stage.surfaceRaised
                Image(systemName: "play.rectangle")
                    .font(BSFont.heroTitle.weight(.light))
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
    }

    /// 未上传视频时延续静态封面的色彩与氛围，只保留一个选择视频入口。
    private func emptyDynamicFace(onChooseVideo: @escaping () -> Void) -> some View {
        ZStack {
            staticFace()
                .scaleEffect(1.08)
                .blur(radius: 18)
                .saturation(0.82)
                .brightness(-0.30)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    BSColor.Stage.background.opacity(0.48),
                    BSColor.Stage.background.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: BSSpacing.sm) {
                Button(action: onChooseVideo) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加动态封面视频")
                .padding(.bottom, BSSpacing.xs)
                Text("添加动态封面")
                    .font(BSFont.caption.weight(.medium))
                    .foregroundColor(.white)
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

            Text("轻点封面进入现场详情。长按主封面可切换静态面与动态面。")
                .font(BSFont.V3.caption)
                .foregroundColor(BSColor.Stage.muted)
                .fixedSize(horizontal: false, vertical: true)

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
            // The coordinator has completed the durable save before exposing the new face.
        } catch is CancellationError {
            return
        } catch let error as DynamicCoverMediaStoreError {
            errorMessage = DynamicCoverErrorMessagePolicy.message(for: error)
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
            errorMessage = BSLocalization.text("动态封面没有删除，请重试。")
        }
        await LocalMediaCommitGate.shared.release()
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
            // Only reveal the dynamic face after both media and SwiftData are committed.
            DynamicCoverFaceStore.setDynamicFace(true, for: show.id)
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
    let isPlaybackActive: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPlaying = false

    private var effectiveIsPlaying: Bool {
        isPlaying && isPlaybackActive && scenePhase == .active
    }

    var body: some View {
        if let cover = show.dynamicCover {
            VStack(alignment: .leading, spacing: BSSpacing.compact) {
                HStack(alignment: .firstTextBaseline) {
                    Text("动态封面")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Spacer()
                    Text(effectiveIsPlaying ? "播放中" : "已暂停")
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
                            isPlaying: effectiveIsPlaying
                        )
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.42)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        Image(systemName: effectiveIsPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(BSFont.heroTitle.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(effectiveIsPlaying ? "暂停动态封面" : "播放动态封面")
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active { isPlaying = false }
            }
            .onDisappear { isPlaying = false }
        }
    }
}
