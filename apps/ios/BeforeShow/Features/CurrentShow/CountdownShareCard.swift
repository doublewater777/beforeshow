import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The show sent from 现场详情, and the share sheet it goes out through.
enum CountdownShareExport {
    static let posterSize = CGSize(width: 360, height: 480)
    static let footerHeight: CGFloat = 156
    static let renderSize = CGSize(width: posterSize.width, height: posterSize.height + footerHeight)
    static let renderScale: CGFloat = 3

    /// The detail button is always there, including after the show has ended.
    static func isAvailable(_ snapshot: HomeHeroSnapshot) -> Bool {
        _ = snapshot
        return true
    }

    /// Draws the card and opens the share sheet; false when either fails.
    @MainActor
    static func share(show: Show, snapshot: HomeHeroSnapshot) async -> Bool {
        guard let data = await renderImage(show: show, snapshot: snapshot)?.pngData() else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BeforeShow-show-\(UUID().uuidString).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        guard SystemPNGSharePresenter.present(url: url) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    @MainActor
    static func renderImage(show: Show, snapshot: HomeHeroSnapshot, style: CountdownShareCardStyle = .classic) async -> UIImage? {
        // A poster this app has already saved. Missing covers stay a plain card; sharing does not wait on the network.
        let poster = ShowCoverReference.url(show.coverImageURL).flatMap {
            ShowCoverImageCache.shared.persistedImage(for: $0)
        }
        let card = CountdownShareCard(
            show: show,
            snapshot: snapshot,
            poster: poster,
            link: ShowShareLink.url(for: show),
            style: style
        )
        .frame(width: renderSize.width, height: renderSize.height)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(renderSize)
        renderer.scale = renderScale
        return renderer.uiImage
    }
}

/// The shared picture: a 3:4 poster, then the time, place and code underneath.
struct CountdownShareCard: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let poster: UIImage?
    let link: URL
    var style: CountdownShareCardStyle = .classic

    var body: some View {
        Group {
            switch style {
            case .classic:
                VStack(spacing: 0) {
                    posterBlock
                    footer
                }
                .background(BSColor.Stage.background)
            case .stub:
                CountdownShareStubCard(copy: copy, timeLine: timeLine, poster: poster, link: link)
            case .invitation:
                CountdownShareInvitationCard(
                    copy: copy,
                    start: snapshot.timeState.effectiveStartTime,
                    calendar: show.timingCalendar(),
                    city: FootprintTextNormalizer.nonEmptyTrimmed(show.city),
                    poster: poster,
                    link: link
                )
            }
        }
        .frame(width: CountdownShareExport.renderSize.width, height: CountdownShareExport.renderSize.height)
    }

    private var posterBlock: some View {
        ZStack(alignment: .bottomLeading) {
            posterFill
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.36),
                    .init(color: .black.opacity(0.78), location: 0.66),
                    .init(color: .black.opacity(0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 0) {
                if !timeLine.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(timeLine)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.42), in: Capsule())
                }
                Text(copy.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 12)
                if let venue = copy.venueSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11, weight: .semibold))
                        Text(venue)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .frame(width: CountdownShareExport.posterSize.width, height: CountdownShareExport.posterSize.height)
        .clipped()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            dashedRule
            CountdownShareSignature(link: link, ink: .white, subInk: .white.opacity(0.62), logoEdge: .white.opacity(0.22))
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: CountdownShareExport.posterSize.width, height: CountdownShareExport.footerHeight, alignment: .top)
        .background(BSColor.Stage.background)
    }

    private var copy: ShowIdentityCopy {
        ShowIdentityCopy(
            name: ShowShareLink.sharedName(show.name),
            venueName: show.venueName,
            city: show.city
        )
    }

    private var timeLine: String {
        guard let start = snapshot.timeState.effectiveStartTime else { return "" }
        return HomeCountdownLockup.startLine(start, calendar: show.timingCalendar())
    }

    private var posterFill: some View {
        Group {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                // No poster: a lit stage rather than a black hole.
                ZStack {
                    LinearGradient(
                        colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    RadialGradient(
                        colors: [BSColor.Stage.accent.opacity(0.28), .clear],
                        center: UnitPoint(x: 0.5, y: 0.08),
                        startRadius: 0,
                        endRadius: 260
                    )
                    RadialGradient(
                        colors: [BSColor.Stage.glowBlue.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.9, y: 0.45),
                        startRadius: 0,
                        endRadius: 220
                    )
                }
            }
        }
        .frame(width: CountdownShareExport.posterSize.width, height: CountdownShareExport.posterSize.height)
        .clipped()
    }

    private var dashedRule: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(
                path,
                with: .color(.white.opacity(0.38)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
        }
        .frame(height: 1)
    }
}

/// Dark ink on a light tile, whatever the card's colours: scanners read that one way round.
struct ShareQRCode: View {
    let link: URL

    private static let code: CGFloat = 92
    private static let inset: CGFloat = 6
    static let side = code + inset * 2

    var body: some View {
        Group {
            if let image = Self.image(for: link) {
                Image(decorative: image, scale: 1)
                    .renderingMode(.template)
                    .interpolation(.none)
                    .resizable()
                    .foregroundStyle(BSColor.Stage.background)
            }
        }
        .frame(width: Self.code, height: Self.code)
        .padding(Self.inset)
        .background(BSColor.Stage.heroIvory, in: RoundedRectangle(cornerRadius: BSRadius.sm))
    }

    /// The modules opaque and the rest clear, so the card's own ink colours them.
    static func image(for link: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        // A code on a screen is never torn or smudged, so the lowest correction keeps it sparse enough to survive
        // a chat app resending the card at two thirds the size.
        filter.correctionLevel = "L"
        guard let modules = filter.outputImage?.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha") else { return nil }
        return CIContext().createCGImage(modules, from: modules.extent)
    }
}

/// Preview before the system share sheet. Saving and sharing are choices on this page.
struct ShowSharePreviewSheet: View {
    let show: Show

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @State private var poster: UIImage?
    @State private var style: CountdownShareCardStyle = .classic
    @State private var isShowingPaywall = false
    @State private var toast: BSToastPayload?
    @State private var isSaving = false
    @State private var isSharing = false

    private var isBusy: Bool { isSaving || isSharing }

    private var snapshot: HomeHeroSnapshot {
        HomeHeroSnapshot(show: show, now: Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CountdownShareCard(
                    show: show,
                    snapshot: snapshot,
                    poster: poster,
                    link: ShowShareLink.url(for: show),
                    style: style
                )
                .aspectRatio(
                    CountdownShareExport.renderSize.width / CountdownShareExport.renderSize.height,
                    contentMode: .fit
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BSSharePosterStylePicker(
                    selection: $style,
                    isProActive: ProEntitlementStorage.decode(entitlementRawValue).isProActive
                ) {
                    isShowingPaywall = true
                }
                .padding(.top, 12)

                HStack(spacing: 9) {
                    exportButton(title: BSLocalization.text("保存图片"), isLoading: isSaving, isPrimary: false) {
                        Task { await saveToPhotos() }
                    }
                    exportButton(title: BSLocalization.text("分享"), isLoading: isSharing, isPrimary: true) {
                        Task { await shareImage() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(BSColor.Stage.background.ignoresSafeArea())
            .navigationTitle(BSLocalization.text("分享这场"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BSChromeToolbarCloseButton { dismiss() } }
            .bsToastOverlay(toast, bottomPadding: 24)
        }
        .tint(BSColor.Stage.foreground)
        .interactiveDismissDisabled(isBusy)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
        .onAppear { loadPoster() }
    }

    private func loadPoster() {
        poster = ShowCoverReference.url(show.coverImageURL).flatMap {
            ShowCoverImageCache.shared.persistedImage(for: $0)
        }
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
        defer { isSaving = false }
        guard let image = await CountdownShareExport.renderImage(show: show, snapshot: snapshot, style: style) else {
            presentFailure(BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        do {
            try await FootprintPhotoLibrary.save(image)
            let payload = BSToastPayload(tone: .success, message: BSLocalization.text("已保存到相册"))
            toast = payload
        } catch {
            presentFailure(BSLocalization.text("保存失败，请检查相册权限"))
        }
    }

    @MainActor
    private func shareImage() async {
        guard !isBusy else { return }
        isSharing = true
        defer { isSharing = false }
        guard let data = await CountdownShareExport.renderImage(show: show, snapshot: snapshot, style: style)?.pngData() else {
            presentFailure(BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeforeShow-show-\(UUID().uuidString).png")
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            presentFailure(BSLocalization.text("分享图片生成失败，请重试"))
            return
        }
        guard SystemPNGSharePresenter.present(items: [file, ShowShareLink.url(for: show)], cleanup: file) else {
            try? FileManager.default.removeItem(at: file)
            presentFailure(BSLocalization.text("系统分享面板暂时无法打开"))
            return
        }
    }

    private func presentFailure(_ message: String) {
        toast = BSToastPayload(tone: .failure, message: message)
    }
}
