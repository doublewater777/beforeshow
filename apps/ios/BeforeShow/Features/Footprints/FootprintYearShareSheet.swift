import SwiftUI
import UIKit

/// 分享这一年: the year poster, its looks, and saving or sharing it.
struct FootprintYearShareSheet: View {
    let recap: FootprintBookRecap
    let covers: [UUID: FootprintCover]

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var style: FootprintYearPosterStyle = .film
    @State private var artwork: [UUID: UIImage] = [:]
    @State private var isShowingPaywall = false
    @State private var isSaving = false
    @State private var isSharing = false
    @State private var toast: BSToastPayload?

    private var isBusy: Bool { isSaving || isSharing }
    private var isProActive: Bool { ProEntitlementStorage.decode(entitlementRawValue).isProActive }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FootprintYearPoster(recap: recap, style: style, artwork: artwork)
                    .scaleEffect(previewScale, anchor: .center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.onAppear { availableSize = proxy.size }
                                .onChange(of: proxy.size) { _, size in availableSize = size }
                        }
                    }
                BSSharePosterStylePicker(selection: $style, isProActive: isProActive) {
                    isShowingPaywall = true
                }
                .padding(.top, 12)
                HStack(spacing: 9) {
                    Button { Task { await save() } } label: { label(BSLocalization.text("保存图片"), isLoading: isSaving, isPrimary: false) }
                        .buttonStyle(BSSecondaryButtonStyle())
                    Button { Task { await share() } } label: { label(BSLocalization.text("分享"), isLoading: isSharing, isPrimary: true) }
                        .buttonStyle(BSPrimaryButtonStyle())
                }
                .disabled(isBusy)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .background(BSColor.Stage.background.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("分享这一年"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BSChromeToolbarCloseButton { dismiss() } }
            .bsToastOverlay(toast, bottomPadding: 24)
        }
        .tint(BSColor.Stage.foreground)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isBusy)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
        .task { artwork = await FootprintYearPosterArtwork.load(shows: recap.shows, covers: covers) }
    }

    @State private var availableSize: CGSize = .zero

    /// The poster fitted into the space above the controls, with a margin.
    private var previewScale: CGFloat {
        guard availableSize.width > 0, availableSize.height > 0 else { return 0.8 }
        let size = FootprintYearPosterLayout.size
        return min((availableSize.width - 44) / size.width, (availableSize.height - 16) / size.height)
    }

    private func label(_ title: String, isLoading: Bool, isPrimary: Bool) -> some View {
        HStack(spacing: BSSpacing.sm) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(isPrimary ? BSColor.Stage.background : BSColor.Stage.foreground)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func render() -> UIImage? {
        FootprintShareImageExport.render(
            FootprintYearPoster(recap: recap, style: style, artwork: artwork),
            size: FootprintYearPosterLayout.size,
            scale: FootprintYearPosterLayout.scale
        )
    }

    @MainActor
    private func save() async {
        guard !isBusy else { return }
        isSaving = true
        defer { isSaving = false }
        guard let image = render() else {
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        do {
            try await FootprintPhotoLibrary.save(image)
            toast = BSToastPayload(tone: .success, message: BSLocalization.text("已保存到相册"))
        } catch {
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("保存失败，请检查相册权限"))
        }
    }

    @MainActor
    private func share() async {
        guard !isBusy else { return }
        isSharing = true
        defer { isSharing = false }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("BeforeShow-\(recap.year)-\(UUID().uuidString).png")
        guard let data = render()?.pngData(), (try? data.write(to: file, options: .atomic)) != nil else {
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        guard SystemPNGSharePresenter.present(items: [file], cleanup: file) else {
            try? FileManager.default.removeItem(at: file)
            toast = BSToastPayload(tone: .failure, message: BSLocalization.text("系统分享面板暂时无法打开"))
            return
        }
    }
}
