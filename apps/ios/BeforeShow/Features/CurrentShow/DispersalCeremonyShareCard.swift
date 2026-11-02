import SwiftUI
import UIKit

// MARK: - 渲染 token

private enum DispersalCeremonyCardTokens {
    static let baseWidth: CGFloat = 360
    static let baseHeight: CGFloat = 500

    static let brand = BSColor.Stage.accent
    static let quote = Color(red: 0.94, green: 0.94, blue: 0.96)
    static let footer = Color.white.opacity(0.45)

    static func sloganFont(scale: CGFloat) -> Font {
        .system(size: 10 * scale, weight: .semibold)
    }

    static func brandFont(scale: CGFloat) -> Font {
        .system(size: 11 * scale, weight: .bold)
    }

    static func eventFont(scale: CGFloat) -> Font {
        .system(size: 22 * scale, weight: .heavy)
    }

    static func dateFont(scale: CGFloat) -> Font {
        .system(size: 11 * scale, weight: .medium)
    }

    static func pillFont(scale: CGFloat) -> Font {
        .system(size: 11 * scale, weight: .semibold)
    }

    static func quoteFont(scale: CGFloat) -> Font {
        .custom("Songti SC", size: 14 * scale, relativeTo: .body)
    }

    static func footerFont(scale: CGFloat) -> Font {
        .system(size: 11 * scale, weight: .medium)
    }
}

enum DispersalCeremonyShareExport {
    static let renderSize = CGSize(width: 360, height: 640)
    static let renderScale: CGFloat = 3

    @MainActor
    static func renderImage(
        show: Show,
        identity: FootprintDetailIdentity,
        rating: Int?,
        note: String,
        ambientColor: Color? = nil
    ) -> UIImage? {
        let card = DispersalCeremonyShareCard(
            show: show,
            identity: identity,
            rating: rating,
            note: note,
            ambientColor: ambientColor
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

    static func loadAmbientColor(for coverURLString: String?) async -> Color? {
        guard let coverURLString,
              let url = URL(string: coverURLString),
              let image = await ShowCoverImageCache.shared.image(from: url),
              let ambient = CoverAmbientColor.uiColor(from: image) else {
            return nil
        }
        return Color(ambient)
    }
}

// MARK: - 散场影评卡（暗调磨砂版）

struct DispersalCeremonyShareCard: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let rating: Int?
    let note: String
    let ambientColor: Color?
    let transitionNamespace: Namespace.ID?

    init(
        show: Show,
        identity: FootprintDetailIdentity,
        rating: Int?,
        note: String,
        ambientColor: Color? = nil,
        transitionNamespace: Namespace.ID? = nil
    ) {
        self.show = show
        self.identity = identity
        self.rating = rating
        self.note = note
        self.ambientColor = ambientColor
        self.transitionNamespace = transitionNamespace
    }

    private var currentRating: DispersalRating? {
        guard let rating else { return nil }
        return DispersalRating.from(rawValue: rating)
    }

    private var trimmedNote: String? {
        FootprintTextNormalizer.nonEmptyTrimmed(note)
    }

    private var cityText: String? {
        FootprintTextNormalizer.nonEmptyTrimmed(show.city)
    }

    private var eventLines: [String] {
        DispersalCeremonyCardCopy.eventLines(
            name: show.name,
            artistNames: show.artistNames
        )
    }

    private var dateLine: String {
        let calendar = show.timingCalendar()
        let date = BSDateFormat.dottedDate(show.effectiveDate, calendar: calendar)
        return [date, cityText].compactMap { $0 }.joined(separator: " · ")
    }

    private var durationText: String? {
        let start = show.startTime
        let end = show.endedAt ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        guard minutes > 0 else { return nil }
        return ShowDurationFormatter.single(totalMinutes: minutes)
    }

    private var dispersalTimeText: String? {
        guard let endedAt = show.endedAt else { return nil }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = show.timingCalendar().timeZone
        return timeFormatter.string(from: endedAt)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / DispersalCeremonyCardTokens.baseWidth
            VStack(spacing: 0) {
                posterHeader(scale: scale)

                reviewSection(scale: scale)

                ticketDivider(scale: scale)

                footerSection(scale: scale)
            }
            .background(
                RoundedRectangle(cornerRadius: 24 * scale)
                    .fill(Color(red: 0.07, green: 0.09, blue: 0.13).opacity(0.92))
            )
            .clipShape(RoundedRectangle(cornerRadius: 24 * scale))
            .overlay(
                RoundedRectangle(cornerRadius: 24 * scale)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    // MARK: - Poster Header (3:4 Ratio Poster Top)

    private func posterHeader(scale: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Poster Artwork Background
            ZStack {
                Color(red: 0.09, green: 0.11, blue: 0.16)
                if let ambientColor {
                    ambientColor.opacity(0.35)
                }
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fill,
                    enforcesAspectRatio: true,
                    cornerRadius: 0,
                    restoresPersistedImageOnFirstFrame: true
                )
            }
            .frame(height: 480 * scale)
            .clipped()

            // Scrims
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top Slogan
            VStack {
                HStack {
                    Spacer()
                    Text("现 场 落 幕 · 留 住 今 晚")
                        .font(DispersalCeremonyCardTokens.sloganFont(scale: scale))
                        .tracking(4 * scale)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.6), radius: 3)
                    Spacer()
                }
                .padding(.top, 14 * scale)
                Spacer()
            }

            // Bottom Overlays in Poster
            VStack(alignment: .leading, spacing: 6 * scale) {
                if !dateLine.isEmpty {
                    Text(dateLine)
                        .font(DispersalCeremonyCardTokens.dateFont(scale: scale))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                ForEach(Array(eventLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(DispersalCeremonyCardTokens.eventFont(scale: scale))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                }

                // Translucent pill with Rating + Dispersal Facts
                HStack(spacing: 6 * scale) {
                    Text(BSLocalization.text("我的感受"))
                        .font(.system(size: 9.5 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))

                    if let currentRating {
                        Text(DispersalCeremonyCardCopy.ratingTitle(currentRating))
                            .font(DispersalCeremonyCardTokens.pillFont(scale: scale))
                            .foregroundStyle(currentRating.tint)
                            .dispersalMatchedGeometry(
                                id: "dispersal.rating",
                                namespace: transitionNamespace
                            )
                    } else {
                        Text(BSLocalization.text("已落幕"))
                            .font(DispersalCeremonyCardTokens.pillFont(scale: scale))
                            .foregroundStyle(BSColor.Stage.muted)
                    }

                    if let timeText = dispersalTimeText {
                        Text("·")
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(BSLocalization.format("%@ 散场", timeText))
                            .font(.system(size: 10 * scale, weight: .medium))
                            .foregroundStyle(BSColor.Stage.accent)
                    }

                    if let dur = durationText {
                        Text("·")
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(BSLocalization.format("历时 %@", dur))
                            .font(.system(size: 10 * scale, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 5 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 8 * scale)
                        .fill(Color.black.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8 * scale)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16 * scale)
            .padding(.bottom, 12 * scale)
        }
        .frame(height: 480 * scale)
    }

    // MARK: - Review Section

    private func reviewSection(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            if let trimmedNote {
                Text("\u{201C}\(trimmedNote)\u{201D}")
                    .font(DispersalCeremonyCardTokens.quoteFont(scale: scale))
                    .foregroundStyle(DispersalCeremonyCardTokens.quote)
                    .lineSpacing(4 * scale)
                    .lineLimit(4)
                    .dispersalMatchedGeometry(
                        id: "dispersal.note",
                        namespace: transitionNamespace
                    )
            } else {
                Text(BSLocalization.text("散场了，现场的心跳收进这里。"))
                    .font(DispersalCeremonyCardTokens.quoteFont(scale: scale))
                    .foregroundStyle(BSColor.Stage.dim)
            }

            HStack {
                Text(DispersalCeremonyCardCopy.footerLeading(identity: identity))
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent)
                Spacer()
            }
            .padding(.top, 2 * scale)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ticket Divider

    private func ticketDivider(scale: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 14 * scale)

            HStack {
                Circle()
                    .fill(Color(red: 0.03, green: 0.03, blue: 0.04))
                    .frame(width: 14 * scale, height: 14 * scale)
                    .offset(x: -7 * scale)
                Spacer()
                Circle()
                    .fill(Color(red: 0.03, green: 0.03, blue: 0.04))
                    .frame(width: 14 * scale, height: 14 * scale)
                    .offset(x: 7 * scale)
            }

            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4 * scale, 3 * scale]))
                .foregroundStyle(Color.white.opacity(0.14))
                .frame(height: 1)
                .padding(.horizontal, 14 * scale)
        }
        .frame(height: 14 * scale)
    }

    // MARK: - Footer Section

    private func footerSection(scale: CGFloat) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(DispersalCeremonyCardCopy.brand)
                    .font(DispersalCeremonyCardTokens.brandFont(scale: scale))
                    .tracking(1 * scale)
                    .foregroundStyle(Color.white)
                Text(dateLine)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            Spacer()

            Text(DispersalCeremonyCardCopy.footerTrailing)
                .font(.system(size: 10.5 * scale, weight: .semibold))
                .foregroundStyle(BSColor.Stage.accent)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 3 * scale)
                .background(
                    Capsule()
                        .fill(BSColor.Stage.accent.opacity(0.14))
                )
                .overlay(
                    Capsule()
                        .stroke(BSColor.Stage.accent.opacity(0.28), lineWidth: 1)
                )
        }
        .padding(.horizontal, 18 * scale)
        .padding(.top, 8 * scale)
        .padding(.bottom, 14 * scale)
    }
}
