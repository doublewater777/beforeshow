import SwiftUI
import UIKit

private enum FootprintShareCardTokens {
    static let baseWidth: CGFloat = 360
    static let accentGlowSize: CGFloat = 220
    static let accentGlowBlur: CGFloat = 48
    static let accentGlowOffset = CGSize(width: -150, height: -190)
    static let blueGlowSize: CGFloat = 250
    static let blueGlowBlur: CGFloat = 54
    static let blueGlowOffset = CGSize(width: 160, height: 155)
    static let titleTopPadding: CGFloat = 8
    static let venueTopPadding: CGFloat = 4
    static let collageMinHeight: CGFloat = 140
    static let collageRadius: CGFloat = 16
    static let collageTopPadding: CGFloat = 14
    static let collageSpacing: CGFloat = 3
    static let identitySpacing: CGFloat = 7
    static let identityHorizontalPadding: CGFloat = 10
    static let identityHeight: CGFloat = 26
    static let identityTopPadding: CGFloat = 12
    static let cardPadding: CGFloat = 20
    static let trailingColumnWidth: CGFloat = 104
    static let footerTopPadding: CGFloat = 12

    static let backgroundColors = [
        BSColor.Stage.background,
        BSColor.Stage.surfaceRaised,
        BSColor.Stage.background
    ]
    static let accentGlow = BSColor.Stage.accent.opacity(0.12)
    static let blueGlow = BSColor.Stage.glowBlue.opacity(0.13)
    static let brand = Color.white.opacity(0.62)
    static let venue = Color.white.opacity(0.58)
    static let collageBorder = Color.white.opacity(0.14)
    static let identityText = Color.white.opacity(0.84)
    static let identityFill = Color.white.opacity(0.075)
    static let identityBorder = Color.white.opacity(0.11)
    static let footer = Color.white.opacity(0.36)

    static func eyebrowFont(scale: CGFloat) -> Font {
        .system(size: 8.5 * scale, weight: .semibold)
    }

    static func brandFont(scale: CGFloat) -> Font {
        .system(size: 8 * scale, weight: .bold)
    }

    static func titleFont(scale: CGFloat) -> Font {
        .system(size: 24 * scale, weight: .semibold)
    }

    static func venueFont(scale: CGFloat) -> Font {
        .system(size: 10.5 * scale, weight: .medium)
    }

    static func identityFont(scale: CGFloat) -> Font {
        .system(size: 8.8 * scale, weight: .semibold)
    }

    static func footerFont(scale: CGFloat) -> Font {
        .system(size: 7.8 * scale, weight: .medium)
    }
}

struct FootprintMemoryShareCard: View {
    let show: Show
    let identity: FootprintDetailIdentity
    let materials: [FootprintShareMaterial]
    let images: [UUID: UIImage]

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / FootprintShareCardTokens.baseWidth
            ZStack {
                LinearGradient(
                    colors: FootprintShareCardTokens.backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(FootprintShareCardTokens.accentGlow)
                    .frame(
                        width: FootprintShareCardTokens.accentGlowSize * scale,
                        height: FootprintShareCardTokens.accentGlowSize * scale
                    )
                    .blur(radius: FootprintShareCardTokens.accentGlowBlur * scale)
                    .offset(
                        x: FootprintShareCardTokens.accentGlowOffset.width * scale,
                        y: FootprintShareCardTokens.accentGlowOffset.height * scale
                    )
                Circle()
                    .fill(FootprintShareCardTokens.blueGlow)
                    .frame(
                        width: FootprintShareCardTokens.blueGlowSize * scale,
                        height: FootprintShareCardTokens.blueGlowSize * scale
                    )
                    .blur(radius: FootprintShareCardTokens.blueGlowBlur * scale)
                    .offset(
                        x: FootprintShareCardTokens.blueGlowOffset.width * scale,
                        y: FootprintShareCardTokens.blueGlowOffset.height * scale
                    )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(cardEyebrow)
                            .font(FootprintShareCardTokens.eyebrowFont(scale: scale))
                            .tracking(BSFont.titleTracking * scale)
                            .foregroundColor(BSColor.Stage.accent)
                        Spacer()
                        Text("BEFORESHOW")
                            .font(FootprintShareCardTokens.brandFont(scale: scale))
                            .tracking(BSFont.titleTracking * scale)
                            .foregroundColor(FootprintShareCardTokens.brand)
                    }

                    Text(show.name)
                        .font(FootprintShareCardTokens.titleFont(scale: scale))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .padding(.top, FootprintShareCardTokens.titleTopPadding * scale)
                    if let venue = FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) {
                        Text(venue)
                            .font(FootprintShareCardTokens.venueFont(scale: scale))
                            .foregroundColor(FootprintShareCardTokens.venue)
                            .lineLimit(1)
                            .padding(.top, FootprintShareCardTokens.venueTopPadding * scale)
                    }

                    shareCollage(scale: scale)
                        .frame(
                            minHeight: FootprintShareCardTokens.collageMinHeight * scale,
                            maxHeight: .infinity
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: FootprintShareCardTokens.collageRadius * scale)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FootprintShareCardTokens.collageRadius * scale)
                                .stroke(FootprintShareCardTokens.collageBorder)
                        )
                        .padding(.top, FootprintShareCardTokens.collageTopPadding * scale)

                    ViewThatFits(in: .horizontal) {
                        identityRow(cardIdentities, scale: scale)
                        identityRow(Array(cardIdentities.prefix(1)), scale: scale)
                    }
                    .padding(.top, FootprintShareCardTokens.identityTopPadding * scale)

                    HStack {
                        Text(BSLocalization.text("一场现场，一份私人的回看"))
                        Spacer()
                        Text(BSLocalization.text("开场前"))
                    }
                    .font(FootprintShareCardTokens.footerFont(scale: scale))
                    .foregroundColor(FootprintShareCardTokens.footer)
                    .padding(.top, FootprintShareCardTokens.footerTopPadding * scale)
                }
                .padding(FootprintShareCardTokens.cardPadding * scale)
            }
        }
    }

    private var cardEyebrow: String {
        let calendar = show.timingCalendar()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        let date = formatter.string(from: show.effectiveDate)
        return [date, FootprintTextNormalizer.nonEmptyTrimmed(show.city)?.uppercased()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var cardIdentities: [String] {
        FootprintMemoryShareCopy.identities(from: identity)
    }

    private func identityRow(_ values: [String], scale: CGFloat) -> some View {
        HStack(spacing: FootprintShareCardTokens.identitySpacing * scale) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(FootprintShareCardTokens.identityFont(scale: scale))
                    .foregroundColor(FootprintShareCardTokens.identityText)
                    .padding(
                        .horizontal,
                        FootprintShareCardTokens.identityHorizontalPadding * scale
                    )
                    .frame(height: FootprintShareCardTokens.identityHeight * scale)
                    .background(FootprintShareCardTokens.identityFill, in: Capsule())
                    .overlay(Capsule().stroke(FootprintShareCardTokens.identityBorder))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    @ViewBuilder
    private func shareCollage(scale: CGFloat) -> some View {
        switch materials.count {
        case 0:
            BSColor.Stage.surface
                .overlay(Image(systemName: "photo").foregroundColor(BSColor.Stage.dim))
        case 1:
            cardImage(materials[0])
        case 2:
            HStack(spacing: FootprintShareCardTokens.collageSpacing * scale) {
                cardImage(materials[0])
                cardImage(materials[1])
            }
        default:
            HStack(spacing: FootprintShareCardTokens.collageSpacing * scale) {
                cardImage(materials[0])
                    .frame(maxWidth: .infinity)
                VStack(spacing: FootprintShareCardTokens.collageSpacing * scale) {
                    cardImage(materials[1])
                    cardImage(materials[2])
                }
                .frame(width: FootprintShareCardTokens.trailingColumnWidth * scale)
            }
        }
    }

    private func cardImage(_ material: FootprintShareMaterial) -> some View {
        Group {
            if let image = images[material.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                BSColor.Stage.surface
                    .overlay(Image(systemName: "photo").foregroundColor(BSColor.Stage.dim))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

}
