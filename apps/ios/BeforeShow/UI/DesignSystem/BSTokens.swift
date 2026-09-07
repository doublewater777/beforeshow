import SafariServices
import UIKit
import SwiftUI

enum BSColor {
    /// True black stage floor.
    static let background = Color.black
    /// Elevated cards and sheets, just above black.
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.11)
    /// Slightly lifted surfaces for hover/pressed states.
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.15)

    /// Primary text on dark backgrounds.
    static let textPrimary = Color.white
    /// Secondary text: dates, venues, subtitles.
    static let textSecondary = Color.white.opacity(0.72)
    /// Tertiary text: hints, footnotes.
    static let textTertiary = Color.white.opacity(0.48)

    /// Subtle divider and card strokes.
    static let border = Color.white.opacity(0.08)
    /// Slightly more visible divider when needed.
    static let borderProminent = Color.white.opacity(0.14)

    /// Brand gradient from the SplashView: cyan → purple → amber.
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0),
            Color(red: 0.70, green: 0.53, blue: 1.0),
            Color(red: 1.0, green: 0.70, blue: 0.28)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Soft gradient used for hero text and countdown numbers.
    static let brandGradientSoft = LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0).opacity(0.9),
            Color(red: 0.70, green: 0.53, blue: 1.0).opacity(0.9),
            Color(red: 1.0, green: 0.70, blue: 0.28).opacity(0.9)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Functional accent tints for feature icons.
    enum Accent {
        static let warm = Color(red: 1.0, green: 0.70, blue: 0.28)       // amber
        static let info = Color(red: 0.49, green: 0.81, blue: 1.0)       // cyan
        static let violet = Color(red: 0.70, green: 0.53, blue: 1.0)     // purple
        static let prepare = Color(red: 0.34, green: 0.84, blue: 0.56)   // mint
        static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)    // coral
    }

    /// Home V3 palette from the 2026-07 feature-cards design: warm tungsten gold
    /// on a blue-tinged stage. Scoped to the current-show home surface; other
    /// surfaces keep the tokens above. Mirrored in DESIGN.md «Home 功能卡色板».
    enum Stage {
        /// Root stage background (#05070D).
        static let background = Color(red: 0.020, green: 0.027, blue: 0.051)
        /// Feature card surface (#0D111B).
        static let surface = Color(red: 0.051, green: 0.067, blue: 0.106)
        /// Raised surface under the floating countdown card (#151A27).
        static let surfaceRaised = Color(red: 0.082, green: 0.102, blue: 0.153)
        /// Primary foreground (#F2F3F7).
        static let foreground = Color(red: 0.949, green: 0.953, blue: 0.969)
        /// Supporting copy (#9399AA).
        static let muted = Color(red: 0.576, green: 0.600, blue: 0.667)
        /// Tertiary copy (#646B7D).
        static let dim = Color(red: 0.392, green: 0.420, blue: 0.490)
        /// Hairline on dark (white 9%).
        static let border = Color.white.opacity(0.09)

        /// Warm tungsten gold — home primary accent (#E8C78E).
        static let accent = Color(red: 0.910, green: 0.780, blue: 0.557)
        /// Countdown hero 色温递进:远场奶白 (#F5EFE2) → 当天暖金 (#F0DCB6) → <1h 用 accent。
        static let heroIvory = Color(red: 0.961, green: 0.937, blue: 0.886)
        static let heroWarmGold = Color(red: 0.941, green: 0.863, blue: 0.714)
        /// Cool blue stage-light tone (#527FC9).
        static let glowBlue = Color(red: 0.322, green: 0.498, blue: 0.788)
        /// 出门清单 card tone (#7B678F).
        static let prepare = Color(red: 0.482, green: 0.404, blue: 0.561)
        /// Badge text: card tone pre-mixed toward white (design color-mix).
        static let prepareBadge = Color(red: 0.627, green: 0.573, blue: 0.682)

        /// Live pulse red (#FF6B75), live status title (#FFD0D3).
        static let live = Color(red: 1.000, green: 0.420, blue: 0.459)
        static let liveTitle = Color(red: 1.000, green: 0.816, blue: 0.827)
        /// Checked state (#A7C9B5).
        static let success = Color(red: 0.655, green: 0.788, blue: 0.710)
        static let danger = Color(red: 0.851, green: 0.537, blue: 0.569)
    }

}


// MARK: - Typography
// Matches the SplashView: light weights, generous tracking, cinematic spacing.

enum BSFont {
    static let pageTitle = Font.system(size: 32, weight: .bold)
    /// Massive countdown / hero numbers.
    static let display = Font.system(size: 80, weight: .light, design: .default)
    /// Screen titles (current show name, large headings).
    static let heroTitle = Font.system(size: 32, weight: .light, design: .default)
    /// Section headings.
    static let title = Font.system(size: 22, weight: .regular, design: .default)
    /// Card titles and primary labels.
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    /// Body copy.
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    /// Captions, metadata, footnotes.
    static let caption = Font.system(size: 13, weight: .medium, design: .default)
    /// Small pills and tags.
    static let tag = Font.system(size: 12, weight: .semibold, design: .default)

    /// Letter spacing used for splash-style large text.
    static let splashTracking: CGFloat = 6
    static let titleTracking: CGFloat = 2

    enum V3 {
        static let display = Font.system(size: 40, weight: .light)
        static let title1 = Font.system(size: 28, weight: .semibold)
        static let title2 = Font.system(size: 22, weight: .semibold)
        static let title3 = Font.system(size: 17, weight: .medium)
        static let body = Font.system(size: 15, weight: .regular)
        static let small = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 11, weight: .medium)
    }
}

// MARK: - Spacing

enum BSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let compact: CGFloat = 12
    static let roomy: CGFloat = 20
}

// MARK: - Radius

enum BSRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let v3Medium: CGFloat = 16
    static let lg: CGFloat = 20
    static let sheet: CGFloat = 24
    static let pill: CGFloat = 999
}

enum BSMotion {
    static let micro: TimeInterval = 0.16
    static let interface: TimeInterval = 0.22
    static let emphasis: TimeInterval = 0.60
}

enum BSLayout {
    /// Reserved space above the floating glass tab bar.
    static let floatingTabBarClearance: CGFloat = 108
    /// Extra scroll room so the last row clears the floating system tab bar.
    static let tabBarContentInset: CGFloat = 96
    /// Minimum tap target edge per HIG.
    static let minTouchTarget: CGFloat = 44
    /// Shared top inset for primary page headers across the two root tabs.
    static let pageHeaderTopPadding: CGFloat = 4
    static let emptyStateActionWidth: CGFloat = 180
    static let emptyStateActionHeight: CGFloat = 49
    /// Visible circle for sheet/page chrome (close, back). Hit target stays `minTouchTarget`.
    static let chromeButtonSize: CGFloat = 32
    static let chromeIconSize: CGFloat = 13
}

enum BSSettingsStyle {
    static let rowMinimumHeight: CGFloat = 68
    static let rowVerticalPadding: CGFloat = 14
    static let rowDividerInset: CGFloat = 62
    static let iconContainerSize: CGFloat = 34
    static let iconSize: CGFloat = 15
    static let iconCornerRadius: CGFloat = 10
    static let iconSurfaceOpacity: Double = 0.12
    static let pressedOpacity: Double = 0.72
    static let membershipGlowRadius: CGFloat = 180
    static let membershipGlowOpacity: Double = 0.13
    static let membershipBorderOpacity: Double = 0.20
}

// MARK: - Reusable View Modifiers
