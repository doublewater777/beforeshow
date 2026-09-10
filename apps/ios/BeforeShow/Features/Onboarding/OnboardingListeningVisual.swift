import SwiftUI

struct OnboardingListeningVisual: View {
    var body: some View {
        GeometryReader { proxy in
            let size: CGFloat = 136
            let discSize: CGFloat = 122
            ZStack {
                // Ambient atmosphere glow from the active record
                Ellipse()
                    .fill(BSListeningTokens.sleevePalette[1].opacity(BSListeningTokens.playingLightOpacity * 1.3))
                    .frame(width: 300, height: 180)
                    .blur(radius: BSListeningTokens.lightBlur + 10)
                    .offset(y: 10)
                    .accessibilityHidden(true)

                HStack(spacing: -18) {
                    // Sleeve 1 with peeking CD disc
                    ZStack(alignment: .leading) {
                        ListeningOnboardingPeekingDisc(size: 108)
                            .offset(x: 118 - 108 + 24)
                        ListeningOnboardingSleeve(number: 1, title: "夜色", color: BSListeningTokens.sleevePalette[1], size: 118)
                    }
                    .offset(y: 8)
                    .rotationEffect(.degrees(-5))

                    // Sleeve 2 with peeking CD disc pulled out slightly more
                    ZStack(alignment: .leading) {
                        ListeningOnboardingPeekingDisc(size: discSize)
                            .offset(x: size - discSize + 32)
                        ListeningOnboardingSleeve(number: 2, title: "最后一班车", color: BSListeningTokens.sleevePalette[0], size: size)
                    }
                    .rotationEffect(.degrees(4))
                    .offset(y: -6)
                    .zIndex(1)
                }
                .padding(.trailing, 34)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

private struct ListeningOnboardingSleeve: View {
    let number: Int
    let title: String
    let color: Color
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: size * BSListeningTokens.sleeveInsetFraction) {
            Text(String(format: "%02d", number))
                .font(.system(size: size * BSListeningTokens.sleeveNumberFraction,
                              weight: .bold, design: .rounded))
                .foregroundStyle(BSListeningTokens.ink)
                .padding(BSSpacing.xs)
                .background(BSListeningTokens.paper)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: size * BSListeningTokens.sleeveTitleFraction, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(size * BSListeningTokens.sleeveInsetFraction)
                .background(BSListeningTokens.paper.opacity(BSListeningTokens.paperOpacity))
        }
        .foregroundStyle(BSListeningTokens.ink)
        .padding(size * BSListeningTokens.sleeveInsetFraction)
        .frame(width: size, height: size)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: BSListeningTokens.hairline))
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.05)
    }
}

private struct ListeningOnboardingPeekingDisc: View {
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            AngularGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.70, green: 0.74, blue: 0.79),
                    Color(red: 0.90, green: 0.93, blue: 0.98),
                    BSColor.Stage.accent,
                    Color(red: 0.43, green: 0.77, blue: 0.85),
                    Color(red: 0.73, green: 0.56, blue: 0.94),
                    Color(red: 0.88, green: 0.91, blue: 0.96),
                    BSColor.Stage.accent,
                    Color(red: 0.41, green: 0.75, blue: 0.82),
                    Color(red: 0.64, green: 0.47, blue: 0.84),
                    Color(red: 0.70, green: 0.74, blue: 0.79)
                ]),
                center: .center,
                angle: .degrees(35)
            )
            .clipShape(Circle())

            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: size * 0.20)
                .padding(size * 0.12)

            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .frame(width: size * 0.28, height: size * 0.28)

            Circle()
                .fill(Color(white: 0.08))
                .frame(width: size * 0.18, height: size * 0.18)

            Circle()
                .stroke(BSColor.Stage.accent.opacity(0.45), lineWidth: 1)
                .frame(width: size * 0.32, height: size * 0.32)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.55), radius: 5, x: -2, y: 3)
    }
}
