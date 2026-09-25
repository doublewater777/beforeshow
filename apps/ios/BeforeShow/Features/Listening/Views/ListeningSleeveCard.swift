import SwiftUI

/// Sleeve jacket with peeking CD disc representing physical media conservation.
struct ListeningSleeveCard: View {
    let disc: ListeningDisc
    let isLoaded: Bool
    var jacketSize: CGFloat = BSListeningTokens.shelfArtwork
    private var discSize: CGFloat { jacketSize * BSListeningTokens.detailDiscFraction }
    var peekOffset: CGFloat = 18
    var showsPullHint = false
    var show: Show?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            // Peeking CD disc on the right
            ListeningPeekingDisc(disc: disc, size: discSize)
                .offset(x: jacketSize - discSize + peekOffset + (showsPullHint ? 6 : 0))
                .opacity(isLoaded ? 0 : 1)
                .scaleEffect(isLoaded ? 0.75 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: isLoaded)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsPullHint)

            // Sleeve Jacket on the left
            ListeningDiscCover(disc: disc, show: show)
                .frame(width: jacketSize, height: jacketSize)
                .rotationEffect(.degrees(ListeningSleeveIdentity(disc: disc).angle))
                .overlay {
                    // Satin sheen over sleeve
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0.0),
                            .init(color: Color.white.opacity(0.0), location: 0.35),
                            .init(color: Color.black.opacity(0.35), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))
                    .allowsHitTesting(false)
                }
                .compositingGroup()
                .shadow(color: Color.black.opacity(0.4), radius: 4, x: 1, y: 2)
        }
        .frame(width: jacketSize + peekOffset, height: jacketSize, alignment: .leading)
    }
}
