import PostHog
import SwiftUI
import SwiftData
import UIKit

enum DispersalCeremonyShareExport {
    static let renderSize = CGSize(width: 360, height: 450)
    static let renderScale: CGFloat = 3

    @MainActor
    static func renderImage(
        show: Show,
        identity: FootprintDetailIdentity,
        rating: Int?,
        note: String
    ) -> UIImage? {
        let card = DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note
        )
        .frame(width: renderSize.width, height: renderSize.height)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(
            width: renderSize.width,
            height: renderSize.height
        )
        renderer.scale = renderScale
        return renderer.uiImage
    }
}

struct DispersalCeremonyShareSheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let onSaved: () -> Void

    var body: some View {
        FootprintShareActionSheet(
            title: BSLocalization.text("分享这场回忆"),
            subtitle: "",
            previewHeight: 368,
            exportSize: DispersalCeremonyShareExport.renderSize,
            exportScale: DispersalCeremonyShareExport.renderScale,
            flexiblePreviewHeight: true,
            preview: {
                DispersalCeremonyShareCard(
                    show: show,
                    identity: identity,
                    rating: rating,
                    note: note
                )
                .aspectRatio(
                    DispersalCeremonyShareExport.renderSize.width
                        / DispersalCeremonyShareExport.renderSize.height,
                    contentMode: .fit
                )
            },
            exportContent: {
                DispersalCeremonyShareCard(
                    show: show,
                    identity: identity,
                    rating: rating,
                    note: note
                )
                .frame(
                    width: DispersalCeremonyShareExport.renderSize.width,
                    height: DispersalCeremonyShareExport.renderSize.height
                )
            },
            onSaved: onSaved
        )
    }
}

struct DispersalShareStep: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let onBack: () -> Void
    let onEnterMemory: () -> Void

    @State private var toast: BSToastPayload?
    @State private var isSaving = false
    @State private var isSharing = false

    var body: some View {
        VStack(spacing: 0) {
            header

            cardPreview
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 9) {
                HStack(spacing: 9) {
                    Button(BSLocalization.text("保存图片")) {
                        Task { await saveToPhotos() }
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                    .disabled(isSaving || isSharing)

                    Button(BSLocalization.text("分享图片")) {
                        Task { await shareImage() }
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                    .disabled(isSaving || isSharing)
                }

                Button(BSLocalization.text("进入现场回忆"), action: onEnterMemory)
                    .buttonStyle(BSPrimaryButtonStyle())
                    .disabled(isSaving || isSharing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .overlay {
            if isSaving || isSharing {
                ZStack {
                    Color.black.opacity(0.38)
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    isSaving
                        ? BSLocalization.text("保存图片")
                        : BSLocalization.text("分享图片")
                )
            }
        }
        .bsToastOverlay(toast, bottomPadding: 24)
        .background(BSNavigationBackSwipeRestorer(onBack: onBack))
    }

    private var header: some View {
        HStack {
            BSChromeIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "回到评级",
                action: onBack
            )
            Spacer()
            Text("散场卡")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear.frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var cardPreview: some View {
        DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note
        )
        .aspectRatio(
            DispersalCeremonyShareExport.renderSize.width
                / DispersalCeremonyShareExport.renderSize.height,
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }

    @MainActor
    private func saveToPhotos() async {
        guard !isSaving, !isSharing else { return }
        isSaving = true
        defer { isSaving = false }
        guard let image = DispersalCeremonyShareExport.renderImage(
            show: show,
            identity: identity,
            rating: rating,
            note: note
        ) else {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        do {
            try await FootprintPhotoLibrary.save(image)
            presentToast(.success, message: BSLocalization.text("已保存到相册"))
        } catch {
            presentToast(.failure, message: BSLocalization.text("保存失败，请检查相册权限"))
        }
    }

    @MainActor
    private func shareImage() async {
        guard !isSaving, !isSharing else { return }
        isSharing = true
        defer { isSharing = false }
        guard let image = DispersalCeremonyShareExport.renderImage(
            show: show,
            identity: identity,
            rating: rating,
            note: note
        ),
              let data = image.pngData() else {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShow-dispersal-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            guard SystemPNGSharePresenter.present(url: url) else {
                try? FileManager.default.removeItem(at: url)
                presentToast(.failure, message: BSLocalization.text("系统分享面板暂时无法打开"))
                return
            }
        } catch {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload { toast = nil }
        }
    }
}

// MARK: - 底部操作条

/// 与 App 其他 sheet 一致的标准按钮组:次要(描边) + 主要(白底),等宽排列。
