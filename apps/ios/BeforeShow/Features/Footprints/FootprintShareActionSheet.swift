import Foundation
import SwiftUI
import UIKit

// MARK: - Footprint Share Action Sheet

struct FootprintShareActionSheet<Preview: View, ExportContent: View>: View {
    let title: String
    let subtitle: String
    let previewHeight: CGFloat
    let exportSize: CGSize
    /// When true, export renders at `exportSize.width` with intrinsic height
    /// (long-screenshot mode) instead of the fixed `exportSize`.
    var usesIntrinsicHeight = false
    /// Pixel scale for export. Long screenshots and fixed cards both use this
    /// so text is rasterized at integer Retina scale instead of 1x-upscaled.
    var exportScale: CGFloat = 1
    /// Async hook (e.g. cover-cache warmup) run before every export render.
    var beforeExport: (() async -> Void)? = nil
    /// When true, the preview fills the sheet's remaining height instead of
    /// the fixed `previewHeight` (used with the .large detent).
    var flexiblePreviewHeight = false
    /// Natural scaled content height. Caps a flexible preview so short
    /// content keeps the buttons close instead of leaving an empty box.
    var previewMaxHeight: CGFloat? = nil
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let exportContent: () -> ExportContent
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isExporting = false
    @State private var toast: BSToastPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 21, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12.5)).foregroundColor(BSColor.Stage.muted).padding(.top, 6)
            }

            preview()
                .frame(height: flexiblePreviewHeight ? nil : previewHeight)
                .frame(maxHeight: flexiblePreviewHeight ? previewMaxHeight ?? .infinity : nil, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.10)))
                .padding(.top, 15)

            HStack(spacing: 8) {
                Button { Task { await saveImage() } } label: {
                    Text(BSLocalization.text("保存图片"))
                        .footprintShareAction(primary: false)
                }
                .buttonStyle(.plain)
                    .disabled(isSaving || isExporting)
                Button { Task { await shareImage() } } label: {
                    Text(BSLocalization.text("分享图片"))
                        .footprintShareAction(primary: true)
                }
                .buttonStyle(.plain)
                    .disabled(isSaving || isExporting)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16).padding(.top, 33).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                BSColor.Stage.background
                RadialGradient(
                    colors: [BSColor.Stage.glowBlue.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: .zero,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        )
        .overlay {
            if isSaving || isExporting {
                ZStack {
                    Color.black.opacity(0.38)
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text(BSLocalization.text("生成中…"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(BSColor.Stage.foreground)
                    }
                }
                .ignoresSafeArea()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(BSLocalization.text("生成中…"))
            }
        }
        .bsToastOverlay(toast, bottomPadding: 24)
    }

    @MainActor
    private func exportImage() -> UIImage? {
        if usesIntrinsicHeight {
            return FootprintShareImageExport.renderLong(exportContent(), width: exportSize.width, scale: exportScale)
        }
        return FootprintShareImageExport.render(exportContent(), size: exportSize, scale: exportScale)
    }

    @MainActor
    private func saveImage() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        await beforeExport?()
        do {
            if usesIntrinsicHeight {
                try await FootprintShareImageExport.saveLong(exportContent(), width: exportSize.width, scale: exportScale)
            } else {
                try await FootprintShareImageExport.save(exportContent(), size: exportSize, scale: exportScale)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? BSLocalization.text("照片保存失败，请重试。")
            presentToast(.failure, message: message)
            return
        }
        dismiss()
        onSaved?()
    }

    @MainActor
    private func shareImage() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        await beforeExport?()
        guard let image = exportImage(),
              let data = image.pngData() else {
            presentToast(.failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShow-footprint-\(UUID().uuidString).png")
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

private extension View {
    func footprintShareAction(primary: Bool) -> some View {
        self
            .font(BSFont.caption)
            .foregroundColor(primary ? BSColor.Stage.background : BSColor.Stage.foreground)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(primary ? BSColor.Stage.foreground : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(primary ? Color.clear : BSColor.Stage.border))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
