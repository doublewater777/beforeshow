import SwiftUI

/// Optical materials and layout constants shared by the player and its loading pose.
enum CDPlayerSurfaceTokens {
    static let orderedControls: [CDControl] = [.previous, .playPause, .next, .open]
    static let ringWidth: CGFloat = 2
    static let bodyOpacity = 0.92
    static let bodyBrightness = -0.04
    static let chassisCorner: CGFloat = 16
    static let chassisWidthFraction: CGFloat = 0.94
    static let chassisMetal = LinearGradient(colors: [Color(white: 0.20), Color(white: 0.115), Color(white: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let discHubFraction = 0.17
    static let discHoleFraction = 0.08
    static let hubSize: CGFloat = 24
    static let rim = LinearGradient(colors: [.white.opacity(0.50), .black, BSColor.Stage.accent.opacity(0.40), .black, .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let discMetal = AngularGradient(colors: [.gray, .white.opacity(0.8), BSColor.Accent.info.opacity(0.7), .gray, .white, BSColor.Stage.accent, .gray], center: .center)
    static let glass = LinearGradient(colors: [BSColor.Stage.background, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let lcdGlow = BSColor.Accent.info.opacity(0.78)
    static let lcdTitle = Font.body.scaled(by: 1.05).weight(.medium)
    static let lcdArtist = Font.caption
    static let lcdMetadata = Font.caption2.monospaced()
    static let statusFont = Font.system(size: 7, weight: .medium, design: .monospaced)
    static let primaryIcon: CGFloat = 25
    static let secondaryIcon: CGFloat = 15
    static let openIcon: CGFloat = 12
    static let meterWidth: CGFloat = 3
    static let meterSpacing: CGFloat = 2
    static let meterHeight: CGFloat = 26
    static let meterBaseHeights: [CGFloat] = [6, 12, 21, 16, 26, 19, 11]

    static func scale(for size: CGSize) -> CGFloat {
        size.width * chassisWidthFraction / CDPlayerConfiguration.standard.geometry.body.width
    }
}
