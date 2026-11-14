import SwiftUI
import UIKit

enum CountdownShareCardStyle: String, BSSharePosterStyle {
    case classic
    case stub
    case headline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: BSLocalization.text("海报")
        case .stub: BSLocalization.text("票根")
        case .headline: BSLocalization.text("大字")
        }
    }

    var isPro: Bool { self != .classic }
}

/// A paper ticket: the poster pinned in the top half, the details, a torn line, and the stub with the code.
struct CountdownShareStubCard: View {
    let copy: ShowIdentityCopy
    let timeLine: String
    let poster: UIImage?
    let link: URL

    private let ink = BSColor.Stage.background

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CountdownSharePosterImage(poster: poster)
                .frame(width: 320, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(copy.title)
                .font(.system(size: 24, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 5) {
                if !timeLine.isEmpty { Text(timeLine) }
                if let venue = copy.venueSummary { Text(venue).lineLimit(1) }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ink.opacity(0.62))
            .padding(.top, 8)
            Spacer(minLength: 0)
            tear
                .padding(.horizontal, -20)
                .padding(.bottom, 14)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(BSShareByline.appName)
                        .font(.system(size: 14, weight: .bold))
                    Text(BSLocalization.text("扫码添加这场演出"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink.opacity(0.55))
                }
                Spacer(minLength: 8)
                ShareQRCode(link: link)
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.sm).stroke(ink.opacity(0.18), lineWidth: 1))
            }
        }
        .foregroundStyle(ink)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BSColor.Stage.heroIvory)
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

/// The name set as large as it will go, the date beneath it, the poster kept small in the corner.
struct CountdownShareHeadlineCard: View {
    let copy: ShowIdentityCopy
    let timeLine: String
    let poster: UIImage?
    let link: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(verbatim: "LIVE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(BSColor.Stage.accent)
                Spacer(minLength: 0)
                if poster != nil {
                    CountdownSharePosterImage(poster: poster)
                        .frame(width: 84, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            Spacer(minLength: 12)
            Text(copy.title)
                .font(.system(size: 52, weight: .black))
                .lineLimit(4)
                .minimumScaleFactor(0.5)
                .lineSpacing(-4)
            Rectangle().fill(BSColor.Stage.foreground).frame(height: 2)
                .padding(.top, 18)
            VStack(alignment: .leading, spacing: 6) {
                if !timeLine.isEmpty {
                    Text(timeLine).font(.system(size: 17, weight: .bold))
                }
                if let venue = copy.venueSummary {
                    Text(venue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.top, 14)
            HStack(alignment: .bottom, spacing: 10) {
                BSShareByline(tone: BSColor.Stage.foreground.opacity(0.6))
                Spacer(minLength: 8)
                ShareQRCode(link: link)
            }
            .padding(.top, 26)
        }
        .foregroundStyle(BSColor.Stage.foreground)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BSColor.Stage.background)
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
