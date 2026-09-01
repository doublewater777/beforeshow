import Foundation
import SwiftUI

enum FootprintDetailTokens {
    static let backgroundGlowRadius: CGFloat = 260
    static let backgroundAccentRadius: CGFloat = 240
    static let heroCornerRadius = BSRadius.sheet
    static let heroCoverWidth: CGFloat = 112
    static let heroCoverHeight: CGFloat = 154
    static let emptyMemoryHeight: CGFloat = 132
    static let avatarSize: CGFloat = 48
    static let infoIconSize: CGFloat = 32
    static let infoTitleWidth: CGFloat = 36
    static let infoRowHeight: CGFloat = 58
    static let memoryTileHeight: CGFloat = 168
    static let memoryMediaHeight: CGFloat = 132
    static let memoryInfoHeight: CGFloat = 36
    static let keepsakeTileHeight: CGFloat = 156
    static let keepsakeMediaHeight: CGFloat = 96
    static let keepsakeInfoHeight: CGFloat = 60

    static let eyebrowFont = BSFont.V3.caption.weight(.semibold)
    static let identityDetailFont = BSFont.V3.caption
    static let iconFont = BSFont.caption.weight(.medium)
    static let sectionFont = BSFont.headline
    static let memoryPlayFont = BSFont.heroTitle.weight(.semibold)
    static let memoryBadgeFont = BSFont.V3.caption.weight(.semibold)
    static let memoryMetadataColor = Color.white.opacity(0.68)
    static let memoryDurationColor = Color.white.opacity(0.74)

    static let backgroundGlow = BSColor.Stage.glowBlue.opacity(0.14)
    static let backgroundAccent = BSColor.Stage.accent.opacity(0.08)
    static let heroSecondarySurface = BSColor.Stage.surface.opacity(0.84)
    static let heroBorder = BSColor.Stage.accent.opacity(0.15)
    static let companionAccent = BSColor.Stage.accent.opacity(0.38)
    static let companionGlow = BSColor.Stage.glowBlue.opacity(0.32)
    static let infoIconFill = Color.white.opacity(0.05)
    static let memoryScrim = Color.black.opacity(0.72)
    static let keepsakeScrim = Color.black.opacity(0.74)
    static let savedKeepsakeText = Color.white.opacity(0.74)
}

struct FootprintMemoryTarget: Identifiable {
    let fragment: MemoryFragment
    let initialIndex: Int

    var id: UUID { fragment.id }
}

enum FootprintPlaybackPolicy {
    static func isActive(
        sceneIsActive: Bool,
        hasMemoryOverlay: Bool,
        hasAssetOverlay: Bool,
        hasShareOverlay: Bool
    ) -> Bool {
        sceneIsActive && !hasMemoryOverlay && !hasAssetOverlay && !hasShareOverlay
    }
}
