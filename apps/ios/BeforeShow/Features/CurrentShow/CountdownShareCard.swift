import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The show sent from 现场详情, and the share sheet it goes out through.
enum CountdownShareExport {
    /// 票根 and 邀请 are this size; 海报 keeps the width and grows with its poster.
    static let renderSize = CGSize(width: 360, height: 636)
    static let renderScale: CGFloat = 3

    static func renderSize(style: CountdownShareCardStyle, poster: UIImage?) -> CGSize {
        guard style == .classic else { return renderSize }
        return CGSize(width: renderSize.width, height: CountdownSharePosterLayout.height(poster: poster))
    }

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
        let size = renderSize(style: style, poster: poster)
        let card = CountdownShareCard(
            show: show,
            snapshot: snapshot,
            poster: poster,
            link: ShowShareLink.url(for: show),
            style: style
        )
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = renderScale
        return renderer.uiImage
    }
}

/// 海报: the whole poster as wide as the rule under it, then the words and the code side by side.
enum CountdownSharePosterLayout {
    static let margin: CGFloat = 20
    static let contentWidth = CountdownShareExport.renderSize.width - margin * 2
    static let ruleGap: CGFloat = 16
    static let infoHeight: CGFloat = 128
    /// Very wide or very long images still keep the card a sane shape.
    static let aspectRange: ClosedRange<CGFloat> = 0.5...1.6
    static let missingPosterAspect: CGFloat = 4.0 / 3.0

    static func posterHeight(poster: UIImage?) -> CGFloat {
        guard let poster, poster.size.width > 0, poster.size.height > 0 else {
            return (contentWidth * missingPosterAspect).rounded()
        }
        let aspect = min(max(poster.size.height / poster.size.width, aspectRange.lowerBound), aspectRange.upperBound)
        return (contentWidth * aspect).rounded()
    }

    static func height(poster: UIImage?) -> CGFloat {
        margin + posterHeight(poster: poster) + ruleGap + 1 + ruleGap + infoHeight + margin
    }
}

struct CountdownShareCard: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let poster: UIImage?
    let link: URL
    var style: CountdownShareCardStyle = .classic

    var body: some View {
        let size = CountdownShareExport.renderSize(style: style, poster: poster)
        Group {
            switch style {
            case .classic:
                posterCard
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
        .frame(width: size.width, height: size.height)
    }

    private var posterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            posterImage
                .frame(
                    width: CountdownSharePosterLayout.contentWidth,
                    height: CountdownSharePosterLayout.posterHeight(poster: poster)
                )
            dashedRule
                .padding(.vertical, CountdownSharePosterLayout.ruleGap)
            info
                .frame(height: CountdownSharePosterLayout.infoHeight)
        }
        .padding(CountdownSharePosterLayout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { backdrop }
        .clipped()
    }

    @ViewBuilder
    private var posterImage: some View {
        if let poster {
            Image(uiImage: poster)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
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
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private var info: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if !timeLine.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        Text(timeLine)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
                if let venue = copy.venueSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .semibold))
                        Text(venue)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    Image("AppLogo")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                        )
                    Text(BSShareByline.appName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text(BSLocalization.text("扫码添加这场演出"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ShareQRCode(link: link)
        }
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

    @ViewBuilder
    private var backdrop: some View {
        if let poster {
            ZStack {
                BSColor.Stage.background
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 50)
                    .scaleEffect(1.3)
                    .opacity(0.8)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .black.opacity(0.55), location: 0.55),
                        .init(color: BSColor.Stage.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            BSColor.Stage.background
        }
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
        .frame(width: CountdownSharePosterLayout.contentWidth, height: 1)
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
    @State private var poster: UIImage?
    @State private var style: CountdownShareCardStyle = .classic
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
                GeometryReader { proxy in
                    CountdownShareCard(
                        show: show,
                        snapshot: snapshot,
                        poster: poster,
                        link: ShowShareLink.url(for: show),
                        style: style
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .scaleEffect(previewScale(in: proxy.size))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                }

                // No look here is Pro, so nothing is ever locked.
                BSSharePosterStylePicker(selection: $style, isProActive: true) {}
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
        .onAppear { loadPoster() }
    }

    /// Fitted above the controls with room around it, never edge to edge.
    private func previewScale(in available: CGSize) -> CGFloat {
        let size = CountdownShareExport.renderSize(style: style, poster: poster)
        return max(0.1, min((available.width - 112) / size.width, (available.height - 28) / size.height))
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
