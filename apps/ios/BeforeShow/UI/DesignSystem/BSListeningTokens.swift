import SwiftUI

/// Listening component dimensions; player model coordinates remain in CDPlayerConfiguration.
enum BSListeningTokens {
    static let avatar: CGFloat = 24
    static let artwork: CGFloat = 82
    static let detailArtwork: CGFloat = 160
    static let playerWidthFraction: CGFloat = 0.78
    static let shelfArtwork: CGFloat = 84
    static let shelfItemWidth: CGFloat = 104
    static let shelfLabelHeight: CGFloat = 18
    static let shelfItemSpacing: CGFloat = 6
    static let shelfContentHeight: CGFloat = shelfArtwork + shelfItemSpacing + shelfLabelHeight + BSSpacing.sm
    static let selectionRestingOpacity = 0.68
    static let shelfShadowHeight: CGFloat = 12
    static let shelfShadowBlur: CGFloat = 7
    static let sleeveLabel = Font.caption.weight(.medium)
    static let songTitle = Font.title3.weight(.medium)
    static let discTitle = Font.system(size: 24, weight: .bold)
    static let songSpacing: CGFloat = 6
    static let songHeight: CGFloat = 70
    static let stageTopOffset: CGFloat = 24
    static let statusIcon: CGFloat = 16
    static let hairline: CGFloat = 0.75
    static let caption = Font.caption
    static let captionMedium = Font.caption.weight(.medium)
    static let body = Font.body
    static let headline = Font.headline
    static let badge = Font.system(size: 10, weight: .semibold)
    static let sleevePalette: [Color] = [BSColor.Accent.warm, BSColor.Accent.info, BSColor.Accent.violet, BSColor.Accent.prepare]
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.81)
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let paperOpacity = 0.94
    static let sleeveInsetFraction = 0.09
    static let sleeveNumberFraction = 0.24
    static let sleeveTitleFraction = 0.11
    static let sleeveAngles: [Double] = [-2, 1.5, -1, 2]
    static let pressDuration = 0.12
    static let releaseDuration = 0.18
    static let selectionAnimation = Animation.easeOut(duration: 0.22)
    static let flipDuration = 0.4
    static let lightDuration = 1.2
    static let lightBlur: CGFloat = 45
    static let playingLightOpacity = 0.7
}

/// Subtle press feedback shared by the listening controls.
struct BSListeningPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(.easeOut(duration: configuration.isPressed ? BSListeningTokens.pressDuration : BSListeningTokens.releaseDuration), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.3), trigger: configuration.isPressed)
    }
}
