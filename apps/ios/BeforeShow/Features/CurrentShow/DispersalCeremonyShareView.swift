import SwiftUI
import UIKit

/// 足迹详情里的散场卡分享，与散场仪式的分享步共用同一视图，保证预览与导出一致。
struct DispersalCeremonyShareSheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String

    @Environment(\.dismiss) private var dismiss
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            DispersalShareStep(
                show: show,
                identity: identity,
                rating: rating,
                note: note,
                transitionNamespace: nil,
                onBack: nil,
                onDone: { dismiss() },
                onBusyChange: { isBusy = $0 }
            )
            .navigationBarTitleDisplayMode(.inline)
            .background(BSColor.Stage.background.ignoresSafeArea())
        }
        .tint(BSColor.Stage.foreground)
        .interactiveDismissDisabled(isBusy)
    }
}

struct DispersalShareStep: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let transitionNamespace: Namespace.ID?
    /// nil 时没有上一步，左上角为关闭。
    let onBack: (() -> Void)?
    let onDone: () -> Void
    let onBusyChange: (Bool) -> Void

    @State private var toast: BSToastPayload?
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var ambientColor: Color?

    private var isBusy: Bool {
        isSaving || isSharing
    }

    var body: some View {
        VStack(spacing: 0) {
            cardPreview
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 9) {
                exportButton(
                    title: BSLocalization.text("保存图片"),
                    isLoading: isSaving,
                    isPrimary: false
                ) {
                    Task { await saveToPhotos() }
                }

                exportButton(
                    title: BSLocalization.text("分享图片"),
                    isLoading: isSharing,
                    isPrimary: true
                ) {
                    Task { await shareImage() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle(BSLocalization.text("散场记录"))
        .toolbar { toolbarContent }
        .bsToastOverlay(toast, bottomPadding: 24)
        .background {
            if let onBack {
                BSNavigationBackSwipeRestorer {
                    guard !isBusy else { return }
                    onBack()
                }
            }
        }
        .task(id: show.coverImageURL) {
            ambientColor = await DispersalCeremonyShareExport.loadAmbientColor(
                for: show.coverImageURL
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let onBack {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(isBusy)
                .accessibilityLabel("回到散场记录")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onDone) {
                    Image(systemName: "checkmark")
                }
                .disabled(isBusy)
                .accessibilityLabel(BSLocalization.text("完成"))
            }
        } else {
            BSChromeToolbarCloseButton(action: onDone)
        }
    }

    private var cardPreview: some View {
        DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note,
            ambientColor: ambientColor,
            transitionNamespace: transitionNamespace
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

    private func exportButton(
        title: String,
        isLoading: Bool,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = HStack(spacing: BSSpacing.sm) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(isPrimary ? BSColor.Stage.background : BSColor.Stage.foreground)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)

        return Group {
            if isPrimary {
                Button(action: action) { label }
                    .buttonStyle(BSPrimaryButtonStyle())
            } else {
                Button(action: action) { label }
                    .buttonStyle(BSSecondaryButtonStyle())
            }
        }
        .disabled(isBusy)
    }

    @MainActor
    private func saveToPhotos() async {
        guard !isBusy else { return }
        isSaving = true
        onBusyChange(true)
        defer {
            isSaving = false
            onBusyChange(false)
        }

        let resolvedAmbient = await resolveAmbientColor()
        guard let image = DispersalCeremonyShareExport.renderImage(
            show: show,
            identity: identity,
            rating: rating,
            note: note,
            ambientColor: resolvedAmbient
        ) else {
            presentToast(
                .failure,
                message: BSLocalization.text("分享图片生成失败，请重试")
            )
            return
        }

        do {
            try await FootprintPhotoLibrary.save(image)
            presentToast(
                .success,
                message: BSLocalization.text("已保存到相册")
            )
        } catch {
            presentToast(
                .failure,
                message: BSLocalization.text("保存失败，请检查相册权限")
            )
        }
    }

    @MainActor
    private func shareImage() async {
        guard !isBusy else { return }
        isSharing = true
        onBusyChange(true)
        defer {
            isSharing = false
            onBusyChange(false)
        }

        let resolvedAmbient = await resolveAmbientColor()
        guard let image = DispersalCeremonyShareExport.renderImage(
            show: show,
            identity: identity,
            rating: rating,
            note: note,
            ambientColor: resolvedAmbient
        ),
        let data = image.pngData() else {
            presentToast(
                .failure,
                message: BSLocalization.text("分享图片生成失败，请重试")
            )
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShow-dispersal-\(UUID().uuidString).png")

        do {
            try data.write(to: url, options: .atomic)
            guard SystemPNGSharePresenter.present(url: url) else {
                try? FileManager.default.removeItem(at: url)
                presentToast(
                    .failure,
                    message: BSLocalization.text("系统分享面板暂时无法打开")
                )
                return
            }
        } catch {
            presentToast(
                .failure,
                message: BSLocalization.text("分享图片生成失败，请重试")
            )
        }
    }

    @MainActor
    private func resolveAmbientColor() async -> Color? {
        if let ambientColor {
            return ambientColor
        }
        let resolved = await DispersalCeremonyShareExport.loadAmbientColor(
            for: show.coverImageURL
        )
        ambientColor = resolved
        return resolved
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
