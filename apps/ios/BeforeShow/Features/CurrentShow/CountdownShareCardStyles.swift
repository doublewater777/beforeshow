import SwiftUI
import UIKit

enum CountdownShareCardStyle: String, BSSharePosterStyle {
    case classic
    case stub
    case invitation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: BSLocalization.text("海报")
        case .stub: BSLocalization.text("票根")
        case .invitation: BSLocalization.text("邀请")
        }
    }

    var isPro: Bool { self != .classic }
}

/// A paper ticket: the poster filling the top, the details right under it, a torn line, and the stub with the code.
/// Without a poster the name is set large on the paper instead of leaving an empty frame.
struct CountdownShareStubCard: View {
    let copy: ShowIdentityCopy
    let timeLine: String
    let poster: UIImage?
    let link: URL

    private let ink = BSColor.Stage.background

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if poster != nil {
                // A 3:4 print as tall as the space left allows, centred on the paper.
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay { CountdownSharePosterImage(poster: poster) }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(copy.title)
                    .font(.system(size: 24, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 16)
            } else {
                Text(verbatim: "ADMIT ONE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(ink.opacity(0.5))
                Spacer(minLength: 16)
                Text(copy.title)
                    .font(.system(size: 44, weight: .heavy))
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
            }
            details
                .padding(.top, 8)
            tear
                .padding(.horizontal, -20)
                .padding(.vertical, 14)
            CountdownShareSignature(
                link: link,
                ink: ink,
                subInk: ink.opacity(0.55),
                logoEdge: ink.opacity(0.12),
                codeEdge: ink.opacity(0.18)
            )
        }
        .foregroundStyle(ink)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BSColor.Stage.heroIvory)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !timeLine.isEmpty { Text(timeLine) }
            if let venue = copy.venueSummary { Text(venue).lineLimit(1) }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(ink.opacity(0.62))
    }

    /// The perforation, with a half-circle bitten out of each edge.
    private var tear: some View {
        HStack(spacing: 0) {
            Circle().fill(BSColor.Stage.background).frame(width: 18, height: 18).offset(x: -9)
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 18)
            Circle().fill(BSColor.Stage.background).frame(width: 18, height: 18).offset(x: 9)
        }
    }
}

/// An engraved invitation: foil corners, the poster tucked in as a slightly tilted print, the name in serif, and the
/// date and doors set as large figures, like a card you would hand someone.
struct CountdownShareInvitationCard: View {
    let copy: ShowIdentityCopy
    let start: Date?
    let calendar: Calendar
    let city: String?
    let poster: UIImage?
    let link: URL

    private let foil = BSColor.Stage.accent
    private let ink = BSColor.Stage.foreground

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                rule
                Text(verbatim: "INVITATION")
                    .font(.system(size: 10.5, weight: .semibold, design: .serif))
                    .tracking(5)
                    .foregroundStyle(foil)
                rule
            }
            if poster != nil {
                posterPrint
                    .padding(.top, 22)
            }
            Spacer(minLength: 12)
            Text(BSLocalization.text("邀你一起去看"))
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(ink.opacity(0.55))
            Text(copy.title)
                .font(.system(size: poster == nil ? 36 : 25, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(poster == nil ? 4 : 2)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
            if let start {
                figures(start)
                    .padding(.top, 18)
            }
            if let venue = FootprintTextNormalizer.nonEmptyTrimmed(copy.venueSummary) {
                Text(venue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.opacity(0.55))
                    .lineLimit(1)
                    .padding(.top, 12)
            }
            Spacer(minLength: 12)
            CountdownShareSignature(link: link, ink: ink, subInk: ink.opacity(0.6), logoEdge: .white.opacity(0.22))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 32)
        .padding(.top, 34)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                BSColor.Stage.background
                RadialGradient(colors: [foil.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 340)
                RadialGradient(
                    colors: [BSColor.Stage.glowBlue.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 300
                )
                CountdownShareFoilCorners()
                    .stroke(foil.opacity(0.7), lineWidth: 1)
                    .padding(14)
            }
        }
    }

    /// The poster as a bordered print, turned a few degrees as if slipped into the card.
    private var posterPrint: some View {
        Color.clear
            .frame(width: 140, height: 186)
            .overlay { CountdownSharePosterImage(poster: poster) }
            .clipped()
            .padding(5)
            .background(BSColor.Stage.heroIvory)
            .rotationEffect(.degrees(-3))
            .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
    }

    /// Date and doors as two large figures, divided by a foil hairline.
    private func figures(_ start: Date) -> some View {
        HStack(alignment: .top, spacing: 18) {
            figure(format(start, "MM.dd"), caption: format(start, "EEE"))
            Rectangle().fill(foil.opacity(0.5)).frame(width: 0.5, height: 44)
            figure(format(start, "HH:mm"), caption: city)
        }
    }

    private func figure(_ value: String, caption: String?) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 30, weight: .regular, design: .serif).monospacedDigit())
            if let caption {
                Text(caption)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(foil)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(foil.opacity(0.45)).frame(width: 28, height: 0.5)
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Four foil corner marks in place of a full border.
struct CountdownShareFoilCorners: Shape {
    var length: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        Path { path in
            for (corner, dx, dy) in [
                (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
            ] {
                path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            }
        }
    }
}

/// The app's mark, the line asking to scan, and the code: the same signature at the foot of every style.
struct CountdownShareSignature: View {
    let link: URL
    let ink: Color
    let subInk: Color
    let logoEdge: Color
    /// On a light card the code's light tile needs an edge to stand apart.
    var codeEdge: Color = .clear

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(logoEdge, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(BSShareByline.appName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                Text(BSLocalization.text("扫码添加这场演出"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(subInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ShareQRCode(link: link)
                .overlay(RoundedRectangle(cornerRadius: BSRadius.sm).stroke(codeEdge, lineWidth: 1))
        }
    }
}

/// The saved poster, or the stage dark when there is none.
struct CountdownSharePosterImage: View {
    let poster: UIImage?

    var body: some View {
        if let poster {
            Image(uiImage: poster)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            BSColor.Stage.surface
        }
    }
}
