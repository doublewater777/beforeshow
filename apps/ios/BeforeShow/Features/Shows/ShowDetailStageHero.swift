import SwiftUI

/// The same stage as a footprint, before the show: a work light while doors are shut,
/// the poster's colours once it is on, house lights after, and darkness if it will not happen.
struct ShowDetailStageHero: View {
    let show: Show
    let mood: ShowStageMood
    let startTime: Date?
    let endTime: Date?
    let reunions: [BSStageLineupChips.Entry]
    let coverTransition: Namespace.ID
    let onOpenCover: () -> Void

    @State private var lights = BSStageLights.fallback
    @State private var powered = false
    @State private var showsExactTime = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BSStageScene(colors: colors, lighting: lighting, powered: powered) {
                ledWall
            } lip: {
                clock
            }
            .padding(.horizontal, -BSSpacing.roomy)
            info.padding(.top, 18)
            BSStageLineupChips(entries: reunions, accent: colors[1], onOpen: openArtist)
                .padding(.top, 14)
        }
        .task(id: show.coverImageURL) {
            await sampleLights()
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08).delay(0.25)) { powered = true }
        }
    }

    private var colors: [Color] { lights.map(\.color) }

    private var lighting: BSStageLighting {
        switch mood {
        case let .before(daysToGo): .workLight(lamps: ShowDetailStagePolicy.warmLamps(daysToGo: daysToGo))
        case .live: .show
        case .ended: .house
        case .postponed, .canceled: .dark
        }
    }

    // MARK: Poster

    private var ledWall: some View {
        Button(action: onOpenCover) {
            ShowCoverImageView(
                urlString: show.coverImageURL,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fill,
                alignment: .top,
                enforcesAspectRatio: false,
                cornerRadius: 0
            )
            .frame(width: 168, height: 224)
            .clipped()
            .overlay { BSLEDScanlines() }
            .grayscale(isOff ? 1 : 0)
            .brightness(wallBrightness)
            .shadow(color: mood == .live ? colors[0].opacity(0.45) : .clear, radius: 30)
            .shadow(color: mood == .live ? colors[1].opacity(0.2) : .clear, radius: 70)
            .overlay { tape }
            .bsTransitionSource(id: "cover", in: coverTransition)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("查看封面大图"))
    }

    private var isOff: Bool { mood == .postponed || mood == .canceled }

    /// The LED wall is dimmed until the show, full while it plays.
    private var wallBrightness: Double {
        switch mood {
        case .before: -0.2
        case .live: 0
        case .ended: -0.08
        case .postponed, .canceled: -0.35
        }
    }

    @ViewBuilder
    private var tape: some View {
        if isOff {
            Text(mood == .canceled ? "CANCELLED" : "POSTPONED")
                .font(.system(size: 15, weight: .semibold).width(.condensed))
                .tracking(5)
                .foregroundStyle(Color(white: 0.07))
                .frame(width: 196, height: 30)
                .background(mood == .canceled ? Color(white: 0.85) : BSColor.Accent.warm)
                .shadow(color: .black.opacity(0.5), radius: 7, y: 6)
                .rotationEffect(.degrees(-8))
                .offset(y: -18)
                .accessibilityHidden(true)
        }
    }

    // MARK: Clock

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            let reading = ShowDetailStagePolicy.clock(
                for: mood,
                start: startTime,
                end: endTime,
                now: context.date,
                exact: showsExactTime,
                calendar: show.timingCalendar()
            )
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) { showsExactTime.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(clockTint)
                        .frame(width: 7, height: 7)
                        .shadow(color: clockTint, radius: 4)
                        .opacity(mood == .live ? (Int(context.date.timeIntervalSinceReferenceDate) % 2 == 0 ? 1 : 0.4) : 1)
                    Text(reading.value)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(clockTint)
                        .shadow(color: clockTint.opacity(0.5), radius: 6)
                        .contentTransition(.numericText())
                    Text(reading.unit)
                        .font(.system(size: 10, weight: .medium).width(.condensed))
                        .tracking(2)
                        .foregroundStyle(BSColor.Stage.dim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(white: 0.045), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.6), radius: 9, y: 8)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: showsExactTime)
            .accessibilityLabel("\(reading.value) \(reading.unit)")
        }
    }

    private var clockTint: Color {
        switch mood {
        case .before: BSColor.Stage.accent
        case .live: BSColor.Stage.liveTitle
        case .ended: BSColor.Stage.foreground
        case .postponed: BSColor.Accent.warm
        case .canceled: BSColor.Stage.dim
        }
    }

    // MARK: Text

    private var info: some View {
        let place = [show.venueName, show.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .medium).width(.condensed).monospacedDigit())
                .tracking(2.5)
                .foregroundStyle(clockTint)
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
            if let notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(clockTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(clockTint.opacity(0.25)))
                    .padding(.top, 6)
            }
        }
    }

    private var dateLine: String {
        BSStageDateLine.text(
            start: show.effectiveDate,
            calendar: show.timingCalendar(),
            end: show.endDate,
            endCalendar: show.endTimingCalendar(),
            showsYear: false,
            startTime: startTime
        )
    }

    private var eyebrow: String {
        switch mood {
        case .before:
            let label = show.changeStatus == .postponed ? BSLocalization.text("已改期") : BSLocalization.text("开场前")
            return label + " · " + dateLine
        case .live: return "LIVE · " + dateLine
        case .ended: return BSLocalization.text("已散场") + " · " + dateLine
        case .postponed: return BSLocalization.text("已延期") + " · " + BSLocalization.text("新日期待定")
        case .canceled: return BSLocalization.text("已取消") + " · " + BSLocalization.format("原定 %@", dateLine)
        }
    }

    private var notice: String? {
        switch mood {
        case .postponed: BSLocalization.text("倒计时已暂停，定下新日期后会重新开始")
        case .canceled: BSLocalization.text("这场已经取消，记录仍会保留")
        case .before, .live, .ended: nil
        }
    }

    private func openArtist(_ name: String) {
        if let link = show.artists.first(where: { $0.name == name })?.appleMusicURL, let url = URL(string: link) {
            openURL(url)
        }
    }

    private func sampleLights() async {
        guard let link = show.coverImageURL, let url = URL(string: link),
              let image = await ShowCoverImageCache.shared.image(from: url) else { return }
        let picked = await BSStageLights.sampled(from: image)
        withAnimation(.easeInOut(duration: 0.6)) { lights = picked }
    }
}
