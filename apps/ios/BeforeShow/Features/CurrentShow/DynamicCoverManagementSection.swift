import PhotosUI
import SwiftData
import SwiftUI

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
                        coverActionButton(BSLocalization.text("更换视频"), icon: "arrow.triangle.2.circlepath") {
                            isPickerPresented = true
                        }
                        .disabled(isImporting)
                        coverActionButton(BSLocalization.text("删除"), icon: "trash", tint: BSColor.Stage.danger) {
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
                    coverActionButton(BSLocalization.text("添加视频"), icon: "plus") {
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
        .alert(BSLocalization.text("删除动态封面？"), isPresented: $isShowingDeleteConfirmation) {
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
            BSLocalization.text("动态封面没有更新"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? BSLocalization.text("请重试"))
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
            errorMessage = BSLocalization.text("视频没有载入，请重试。")
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
