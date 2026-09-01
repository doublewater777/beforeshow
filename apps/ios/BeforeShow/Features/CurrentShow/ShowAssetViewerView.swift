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
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .gesture(magnifyGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if scale > 1.05 {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2
                                    lastScale = 2
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 12)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let disclaimer = kind.viewerDisclaimer {
                Text(disclaimer)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            Text("双指缩放，拖动查看细节")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.55))
                .padding(.bottom, 28)
        }
        .navigationBarHidden(true)
        .background(BSNavigationBackSwipeRestorer(onBack: { dismiss() }))
        .bsToastOverlay(toast, bottomPadding: 36)
        .task(id: "\(asset.relativePath)|\(asset.updatedAt.timeIntervalSince1970)") {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
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

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("返回")

            Spacer()

            Text(kind.viewerTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Menu {
                Button(BSLocalization.text("替换图片")) {
                    isReplacing = true
                }
                Button(BSLocalization.format("删除%@", kind.title), role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel(BSLocalization.format("管理%@", kind.title))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(4, max(1, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
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
                    try? await Task.sleep(nanoseconds: 350_000_000)
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
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}
