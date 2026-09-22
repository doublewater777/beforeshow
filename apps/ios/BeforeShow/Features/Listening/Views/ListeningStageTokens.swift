import SwiftUI

/// Proportions of the approved production assets on the continuous stage.
enum ListeningStageTokens {
    static let discWidthFraction: CGFloat = 0.907
    static let surfaceWidthFraction: CGFloat = 1.24
    static let surfaceTopFraction: CGFloat = -0.08
    static let spindleFraction: CGFloat = 0.18
    // The PNGs include transparent margins around the visible hardware.
    static let primaryAssetScale: CGFloat = 1.8
    static let secondaryAssetScale: CGFloat = 3.0
    static let spindleAssetScale: CGFloat = 4.4
    static let pressTravel: CGFloat = 2
    static let glossOpacity = 0.36
    static let surfaceOpacity = 0.82
    static let primaryButton: CGFloat = 74
    static let secondaryButton: CGFloat = 56
    static let primarySymbol: CGFloat = 23
    static let secondarySymbol: CGFloat = 16
    static let primaryBrightness = -0.06
    static let secondaryBrightness = -0.20
    static let primaryContrast = 0.92
    static let secondaryContrast = 0.72
    static let informationInset: CGFloat = 32
    static let compilationTile: CGFloat = 300
    static let compilationCrop: CGFloat = 0.82
    static let compilationBlend: CGFloat = 0.018
    static let discRim: CGFloat = 1.5
    static let hubFraction: CGFloat = 0.245
    static let contactShadow = Color.black.opacity(0.65)
    static let metal = LinearGradient(colors: [Color(white: 0.62), Color(white: 0.18), Color(white: 0.42), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let stageMetal = Color(white: 0.16)
    static let status = BSColor.Accent.info
}

extension EnvironmentValues {
    @Entry var listeningSurfaceLight: Color = .clear
}
