import SwiftUI

/// Listening component dimensions; player model coordinates remain in CDPlayerConfiguration.
enum BSListeningTokens {
    static let avatar: CGFloat = 40
    static let artistWidth: CGFloat = 74
    static let artwork: CGFloat = 82
    static let detailArtwork: CGFloat = 160
    static let playerWidthFraction: CGFloat = 0.84
    static let shelfArtwork: CGFloat = 76
    static let shelfItemWidth: CGFloat = 96
    static let shelfLabelHeight: CGFloat = 18
    static let shelfItemSpacing: CGFloat = 6
    static let shelfContentHeight: CGFloat = shelfArtwork + shelfItemSpacing + shelfLabelHeight + BSSpacing.xs * 2
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
    static let flipDuration = 0.4
    static let lightDuration = 0.7
    static let lightHeight: CGFloat = 240
    static let lightBlur: CGFloat = 45
    static let lightOffset: CGFloat = 40
    static let playingLightOpacity = 0.28
    static let restingLightOpacity = 0.10
    static let recentLift: CGFloat = 4
}

/// Tactile spring-loaded press style conforming to Apple Design WWDC fluid guidelines.
struct BSListeningPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.3), trigger: configuration.isPressed)
    }
}
