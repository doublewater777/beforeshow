import SwiftUI

/// The top of a show's page: its poster is the LED wall, moving heads sweep in the poster's colours.
struct FootprintStageHero: View {
    let show: Show
    let cover: FootprintCover?
    let archive: FootprintArchiveSnapshot
    let identity: FootprintDetailIdentity
    let canOpenCover: Bool
    let coverTransition: Namespace.ID
    let onOpenCover: () -> Void

    @State private var lights = BSStageLights.fallback
    @State private var powered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// The longest-standing reunion on the bill, said under the ticket.
    private var reunionLine: String? {
        FootprintStagePolicy.reunions(for: show, in: archive.shows)
            .filter { $0.nth > 1 }
            .max { $0.nth < $1.nth }
            .map { BSLocalization.format("和%@第 %lld 次见面 · 点票根撕下", $0.name, $0.nth) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BSStageScene(colors: colors, lighting: .show(energy: 1), powered: powered) { ledWall }
                .padding(.horizontal, -BSSpacing.roomy)
            info.padding(.top, 18)
            BSStageLineupChips(
                entries: FootprintStagePolicy.reunions(for: show, in: archive.shows).map { .init(name: $0.name, nth: $0.nth) },
                accent: colors[1],
                onOpen: openArtist
            )
            .padding(.top, 14)
            FootprintTicketStub(show: show, ordinal: identity.showOrdinal, lights: colors, reunionLine: reunionLine)
                .padding(.top, 22)
            if let song = FootprintNumberSongs.song(for: identity.showOrdinal) {
                FootprintNumberRecord(song: song)
                    .padding(.top, 16)
            }
        }
        .task(id: show.id) {
            await sampleLights()
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08).delay(0.25)) { powered = true }
        }
    }

    private var colors: [Color] { lights.map(\.color) }

    private func openArtist(_ name: String) {
        if let link = show.artists.first(where: { $0.name == name })?.appleMusicURL, let url = URL(string: link) {
            openURL(url)
        }
    }

    @ViewBuilder
    private var ledWall: some View {
        let wall = FootprintCoverView(show: show, cover: cover, showsMetadata: false)
            .frame(width: 168, height: 224)
            .overlay { BSLEDScanlines() }
            .shadow(color: colors[0].opacity(0.45), radius: 30)
            .shadow(color: colors[1].opacity(0.2), radius: 70)
        if canOpenCover {
            Button(action: onOpenCover) {
                wall.bsTransitionSource(id: "cover", in: coverTransition)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BSLocalization.text("查看封面大图"))
        } else {
            wall.accessibilityHidden(true)
        }
    }

    // MARK: Text

    private var info: some View {
        let place = [FootprintTextNormalizer.nonEmptyTrimmed(show.venueName), FootprintTextNormalizer.nonEmptyTrimmed(show.city)]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "No. %03d · %@", identity.showOrdinal, BSStageDateLine.text(
                start: show.effectiveDate,
                calendar: show.timingCalendar(),
                end: show.endDate,
                endCalendar: show.endTimingCalendar()
            )))
                .font(.system(size: 12, weight: .medium).width(.condensed).monospacedDigit())
                .tracking(2.5)
                .foregroundStyle(colors[1])
            Text(show.name)
                .font(.system(size: 27, weight: .heavy, design: .serif))
                .foregroundStyle(BSColor.Stage.foreground)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            if !place.isEmpty {
                Text(place)
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(2)
            }
            if let city = FootprintTextNormalizer.nonEmptyTrimmed(show.city), let cityOrdinal = identity.cityOrdinal {
                Text(BSLocalization.format("第 %lld 场现场", identity.showOrdinal) + "  ·  " + "\(city) · " + BSLocalization.format("第 %lld 场", cityOrdinal))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent.opacity(0.88))
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Lights

    private func sampleLights() async {
        guard let cover else { return }
        let image: UIImage?
        switch cover.source {
        case let .local(url):
            image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        case let .remote(url):
            image = await ShowCoverImageCache.shared.image(from: url)
        case .archive:
            image = nil
        }
        guard let image else { return }
        let picked = await BSStageLights.sampled(from: image)
        withAnimation(.easeInOut(duration: 0.6)) { lights = picked }
    }
}
