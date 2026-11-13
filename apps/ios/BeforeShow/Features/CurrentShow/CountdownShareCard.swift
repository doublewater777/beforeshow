import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The countdown sent before the show, and the share sheet it goes out through.
enum CountdownShareExport {
    static let renderSize = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    /// Only before doors, and only once there is a start to count down to.
    static func isAvailable(_ snapshot: HomeHeroSnapshot) -> Bool {
        snapshot.phase == .pre && snapshot.timeState.effectiveStartTime != nil
    }

    /// Draws the card and opens the share sheet; false when either fails.
    @MainActor
    static func share(show: Show, snapshot: HomeHeroSnapshot) async -> Bool {
        guard let data = await renderImage(show: show, snapshot: snapshot)?.pngData() else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BeforeShow-countdown-\(UUID().uuidString).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        guard SystemPNGSharePresenter.present(url: url) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    @MainActor
    static func renderImage(show: Show, snapshot: HomeHeroSnapshot) async -> UIImage? {
        // The poster is loaded before drawing so it lands on the first frame, and lights the stage as on 当前.
        var lights = BSStageLights.fallback
        if let url = ShowCoverReference.url(show.coverImageURL),
           let poster = await ShowCoverImageCache.shared.image(from: url) {
            lights = await BSStageLights.sampled(from: poster)
        }
        let card = CountdownShareCard(show: show, snapshot: snapshot, lights: lights.map(\.color), link: ShowShareLink.url(for: show))
            .frame(width: renderSize.width, height: renderSize.height)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(renderSize)
        renderer.scale = renderScale
        return renderer.uiImage
    }
}

/// The 当前 stage as a picture: the poster lit on stage, how long until doors, the show, and a code that adds the
/// show to the app of whoever scans it.
struct CountdownShareCard: View {
    let show: Show
    let snapshot: HomeHeroSnapshot
    let lights: [Color]
    let link: URL

    private static let size = CountdownShareExport.renderSize
    private static let margin: CGFloat = 28
    private static let stageHeight: CGFloat = 372

    var body: some View {
        ZStack(alignment: .top) {
            BSColor.Stage.background
            BSStageScene(colors: lights, lighting: .show(energy: energy), powered: true, height: Self.stageHeight) {
                HomeHeroStage(show: show, snapshot: snapshot, coverWidth: 176, reduceMotion: true, onStage: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                countdown
                LinearGradient(colors: [BSColor.Stage.accent.opacity(0.9), BSColor.Stage.accent.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.vertical, 14)
                identity
                Spacer(minLength: 16)
                footer
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, Self.stageHeight - 46)
            .padding(.bottom, 24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var energy: Double {
        HomeStageEnergy.energy(phase: .pre, start: start, now: snapshot.now, calendar: show.timingCalendar())
    }

    private var start: Date { snapshot.timeState.effectiveStartTime ?? show.startTime }

    private var days: Int? {
        ShowCountdownRule.dayCount(
            remainingSeconds: max(0, Int(start.timeIntervalSince(snapshot.now))),
            dayDistance: snapshot.timeState.dayDistance
        )
    }

    private var countdown: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            // A picture outlives the hour, so the day of the show reads as today rather than hours and minutes.
            Text(days.map { String(format: "%02d", $0) } ?? BSLocalization.text("今天"))
                .font(BSFont.Editorial.serif(days == nil ? 64 : 96))
                .tracking(days == nil ? 0 : -3)
                .monospacedDigit()
                .foregroundStyle(BSColor.Stage.heroIvory)
                .shadow(color: BSColor.Stage.heroIvory.opacity(0.45), radius: 22)
                .lineLimit(1)
                .padding(.vertical, days == nil ? -8 : -14)
            VStack(alignment: .leading, spacing: 4) {
                if days != nil {
                    Text(BSLocalization.text("天后"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(BSColor.Stage.foreground)
                }
                Text(HomeCountdownLockup.startLine(start, calendar: show.timingCalendar()))
                    .font(.system(size: 12.5))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var identity: some View {
        let copy = ShowIdentityCopy(name: show.name, venueName: show.venueName, city: show.city)
        return VStack(alignment: .leading, spacing: 6) {
            Text(copy.title)
                .font(BSFont.Editorial.serif(24))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            if let venue = copy.venueSummary {
                Text(venue)
                    .font(.system(size: 12.5))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            BSShareByline()
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 7) {
                ShareQRCode(link: link)
                Text(BSLocalization.text("扫码添加这场"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
            }
        }
    }
}

/// Dark ink on a light tile, whatever the card's colours: scanners read that one way round.
private struct ShareQRCode: View {
    let link: URL

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
        .frame(width: 92, height: 92)
        .padding(6)
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
