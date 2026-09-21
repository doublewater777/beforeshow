import SwiftUI

/// Proportions of the approved production assets on the continuous stage.
enum ListeningStageTokens {
    static let discWidthFraction: CGFloat = 0.94
    static let surfaceWidthFraction: CGFloat = 1.24
    static let surfaceTopFraction: CGFloat = -0.08
    static let spindleFraction: CGFloat = 0.16
    // The PNGs include transparent margins around the visible hardware.
    static let primaryAssetScale: CGFloat = 1.8
    static let secondaryAssetScale: CGFloat = 3.0
    static let spindleAssetScale: CGFloat = 4.4
    static let pressTravel: CGFloat = 2
    static let glossOpacity = 0.28
    static let surfaceOpacity = 0.40
    static let primaryButton: CGFloat = 82
    static let secondaryButton: CGFloat = 62
    static let primarySymbol: CGFloat = 25
    static let secondarySymbol: CGFloat = 18
    static let status = BSColor.Accent.info
}
