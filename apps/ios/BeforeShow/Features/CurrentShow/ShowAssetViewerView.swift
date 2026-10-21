import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ShowAssetViewerView: View {
    let showID: UUID
    let showName: String
    let kind: ShowAssetKind
    let asset: ShowAsset

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var image: UIImage?
    @State private var isReplacing = false
    @State private var isConfirmingDelete = false
    @State private var toast: BSToastPayload?
    @State private var isChromeVisible = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    BSZoomableImageView(image: image) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isChromeVisible.toggle()
                        }
                    }
                    .padding(.horizontal, 12)
                    .bsMaskUserContent()
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                if let disclaimer = kind.viewerDisclaimer {
                    Text(disclaimer)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                Text("双指缩放，拖动查看细节")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.bottom, 28)
            }
            .opacity(isChromeVisible ? 1 : 0)
        }
        .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(kind.viewerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { manageMenu }
        .bsToastOverlay(toast, bottomPadding: 36)
        .task(id: "\(asset.relativePath)|\(asset.updatedAt.timeIntervalSince1970)") {
            image = nil
            await loadImage()
        }
        .navigationDestination(isPresented: $isReplacing) {
            ShowAssetUploadView(
                showID: showID,
                showName: showName,
                kind: kind,
                replacingAsset: asset
            )
        }
        .alert(
            DangerConfirmation.deleteAsset(kind).title,
            isPresented: $isConfirmingDelete
        ) {
            Button(DangerConfirmation.deleteAsset(kind).confirmTitle, role: .destructive) {
                deleteAsset()
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(DangerConfirmation.deleteAsset(kind).message)
        }
    }

    private var manageMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(BSLocalization.text("替换图片")) {
                    isReplacing = true
                }
                Button(BSLocalization.format("删除%@", kind.title), role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .tint(BSColor.Stage.foreground)
            .accessibilityLabel(BSLocalization.format("管理%@", kind.title))
        }
    }

    private func loadImage() async {
        let relativePath = asset.relativePath
        guard let url = try? await ShowAssetMediaStore.shared.absoluteURL(
            for: relativePath,
            showID: showID,
            kind: kind
        ) else {
            image = nil
            presentToast(.failure, message: BSLocalization.text("图片暂时不可用"))
            return
        }
        if let data = try? Data(contentsOf: url), let loaded = UIImage(data: data) {
            image = loaded
        } else {
            image = nil
            presentToast(.failure, message: BSLocalization.text("图片暂时打不开"))
        }
    }

    private func deleteAsset() {
        let assetID = asset.id
        Task { @MainActor in
            do {
                await ShowAssetMediaStore.shared.acquireCommitGate()
                do {
                    let currentAsset = try modelContext.fetch(
                        FetchDescriptor<ShowAsset>(predicate: #Predicate { $0.id == assetID })
                    ).first
                    guard let currentAsset else {
                        await ShowAssetMediaStore.shared.releaseCommitGate()
                        return
                    }
                    let currentRelativePath = currentAsset.relativePath
                    let currentKind = currentAsset.kind
                    modelContext.delete(currentAsset)
                    try saveModelContextRollingBackOnFailure(modelContext)
                    let cleanupPending: Bool
                    let invalidPath: Bool
                    do {
                        try await ShowAssetMediaStore.shared.delete(
                            relativePath: currentRelativePath,
                            showID: showID,
                            kind: currentKind
                        )
                        cleanupPending = false
                        invalidPath = false
                    } catch ShowAssetMediaStoreError.invalidRelativePath {
                        cleanupPending = false
                        invalidPath = true
                    } catch {
                        cleanupPending = true
                        invalidPath = false
                    }
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                    if cleanupPending,
                       ShowAsset.isValidRelativePath(
                           currentRelativePath,
                           showID: showID,
                           kind: currentKind
                       ) {
                        ShowAssetCleanupRetry.markAssetCleanupPending(
                            showID: showID,
                            kind: currentKind,
                            relativePath: currentRelativePath
                        )
                    }
                    presentToast(
                        invalidPath || cleanupPending ? .neutral : .success,
                        message: invalidPath
                            ? BSLocalization.format("%@记录已删除，异常图片将在下次启动整理", kind.title)
                            : cleanupPending
                            ? BSLocalization.format("%@记录已删除，图片将在下次启动继续清理", kind.title)
                            : BSLocalization.format("%@已删除", kind.title)
                    )
                    try? await Task.sleep(for: .milliseconds(350))
                    dismiss()
                    return
                } catch {
                    await ShowAssetMediaStore.shared.releaseCommitGate()
                    throw error
                }
            } catch {
                presentToast(.failure, message: BSLocalization.text("删除失败，请重试"))
            }
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            if toast == payload {
                toast = nil
            }
        }
    }
}
