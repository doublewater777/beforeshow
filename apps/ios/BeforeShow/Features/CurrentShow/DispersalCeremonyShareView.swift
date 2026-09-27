import SwiftUI
import UIKit

struct DispersalCeremonyShareSheet: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let onSaved: () -> Void

    @State private var ambientColor: Color?
    @State private var hasResolvedAmbientColor = false

    var body: some View {
        Group {
            if hasResolvedAmbientColor {
                FootprintShareActionSheet(
            title: BSLocalization.text("分享记录"),
            subtitle: "",
            previewHeight: 368,
            exportSize: DispersalCeremonyShareExport.renderSize,
            exportScale: DispersalCeremonyShareExport.renderScale,
            beforeExport: {
                await prepareAmbientColorForExport()
            },
            flexiblePreviewHeight: true,
            preview: {
                DispersalCeremonyShareCard(
                    show: show,
                    identity: identity,
                    rating: rating,
                    note: note,
                    ambientColor: ambientColor
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
                    note: note,
                    ambientColor: ambientColor
                )
                .frame(
                    width: DispersalCeremonyShareExport.renderSize.width,
                    height: DispersalCeremonyShareExport.renderSize.height
                )
            },
                    onSaved: onSaved
                )
            } else {
                ProgressView()
                    .tint(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BSColor.Stage.background)
            }
        }
        .task(id: show.coverImageURL) {
            hasResolvedAmbientColor = false
            await prepareAmbientColorForExport()
            hasResolvedAmbientColor = true
        }
    }

    @MainActor
    private func prepareAmbientColorForExport() async {
        ambientColor = await DispersalCeremonyShareExport.loadAmbientColor(
            for: show.coverImageURL
        )
    }
}

struct DispersalShareStep: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let transitionNamespace: Namespace.ID?
    let onBack: () -> Void
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
            header

            cardPreview
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 9) {
                exportButton(
                    title: BSLocalization.text("保存图片"),
                    isLoading: isSaving
                ) {
                    Task { await saveToPhotos() }
                }

                exportButton(
                    title: BSLocalization.text("分享图片"),
                    isLoading: isSharing
                ) {
                    Task { await shareImage() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .bsToastOverlay(toast, bottomPadding: 24)
        .background(
            BSNavigationBackSwipeRestorer {
                guard !isBusy else { return }
                onBack()
            }
        )
        .task(id: show.coverImageURL) {
            ambientColor = await DispersalCeremonyShareExport.loadAmbientColor(
                for: show.coverImageURL
            )
        }
    }

    private var header: some View {
        HStack {
            BSChromeIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "回到散场记录"
            ) {
                guard !isBusy else { return }
                onBack()
            }
            .disabled(isBusy)

            Spacer()

            Text(BSLocalization.text("散场记录"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)

            Spacer()

            Button(action: onDone) {
                Text(BSLocalization.text("完成"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(
                        minWidth: BSLayout.minTouchTarget,
                        minHeight: BSLayout.minTouchTarget
                    )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BSSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BSColor.Stage.foreground)
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BSSecondaryButtonStyle())
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
