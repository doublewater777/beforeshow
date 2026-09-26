import SwiftUI

/// Listening component dimensions; player model coordinates remain in CDPlayerConfiguration.
enum BSListeningTokens {
    // Lighting is expressed in player model coordinates, then scaled with the machine.
    static let restingLight = Color(red: 0.63, green: 0.72, blue: 0.82)
    static let placingLight = Color(red: 0.84, green: 0.89, blue: 0.94)
    static let roomLightOpacity = 0.4
    static let haloWidth: CGFloat = 2.2
    static let haloHeight: CGFloat = 1.9
    static let haloRadius: CGFloat = 340
    static let haloBlur: CGFloat = 30
    static let haloRestingOpacity = 0.22
    static let haloPlacingOpacity = 0.40
    static let haloPlayingOpacity = 0.56
    static let haloRestingScale: CGFloat = 0.88
    static let haloPlacingScale: CGFloat = 0.96
    static let loadedLidOpacity = 0.025
    static let detailDiscFraction: CGFloat = 0.92
    static let detailDiscReveal: CGFloat = 0.34
    static let statusDot: CGFloat = 4
    static let statusTracking: CGFloat = 1.4
    static let actionHeight: CGFloat = 52
    static let stateIconSize: CGFloat = 56
    static let stateIconFont = Font.system(size: 24, weight: .light)
    static let stateTitle = Font.system(size: 22, weight: .medium)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let gridTitle = Font.system(size: 15, weight: .medium)
    static let detailTitle = Font.system(size: 26, weight: .semibold)
    static let rowNumber = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let rowAccessory: CGFloat = 24
    static let rowDividerInset: CGFloat = 36
    static let candidateAvatar: CGFloat = 48
    static let cabinetAvatar: CGFloat = 56
    static let stateVerticalPadding: CGFloat = 48
    static let emptyArtwork: CGFloat = 168
    static let emptyDiscFraction: CGFloat = 0.84
    static let emptyDiscOffset: CGFloat = 0.22
    static let sheetGlowHeight: CGFloat = 360
    static let sheetGlowOpacity = 0.10
    static let selectionFillOpacity = 0.13
    static let selectionBorderOpacity = 0.35
    static let inactiveFillOpacity = 0.65
    static let avatar: CGFloat = 24
    static let artwork: CGFloat = 82
    static let detailArtwork: CGFloat = 184
    static let playerWidthFraction: CGFloat = 1.08
    static let discRotationRPM = 20.0
    /// Radius as a fraction of the full CD diameter; 0.0625 = 12.5% hub diameter.
    static let discHubRadiusFraction: CGFloat = 0.0625
    /// Radius as a fraction of the full CD diameter; 0.025 = 5% spindle diameter.
    static let discSpindleRadiusFraction: CGFloat = 0.025
    static let shelfArtwork: CGFloat = 64
    static let shelfItemWidth: CGFloat = 98
    static let shelfLabelHeight: CGFloat = 16
    static let shelfItemSpacing: CGFloat = 6
    static let shelfContentHeight: CGFloat = shelfArtwork + shelfItemSpacing + shelfLabelHeight + BSSpacing.sm
    static let selectionRestingOpacity = 0.62
    static let shelfShadowHeight: CGFloat = 12
    static let shelfShadowBlur: CGFloat = 7
    static let sleeveLabel = Font.caption.weight(.medium)
    static let songTitle = Font.title3.weight(.medium)
    static let discTitle = Font.system(size: 24, weight: .bold)
    static let songSpacing: CGFloat = 6
    static let songHeight: CGFloat = 70
    static let stageTopOffset: CGFloat = 56
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
    static let lightBlur: CGFloat = 58
    static let playingLightOpacity = 0.82
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
    }
}
