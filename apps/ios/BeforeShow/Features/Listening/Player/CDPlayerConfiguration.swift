import SwiftUI

/// All dimensions are measured in one immutable 460 × 740 model space.
/// Assets are UV textures, never independent layout-sized photographs.
struct CDPlayerConfiguration {
    struct Geometry {
        /// Fixed display crop; motion continues in the full model coordinate space.
        var viewportTop: CGFloat = 225
        var canvas = CGSize(width: 460, height: 740)
        var body = CGRect(x: 20, y: 278, width: 420, height: 466)
        var lid = CGRect(x: 30, y: 304, width: 400, height: 353)
        var hingeY: CGFloat = 304
        var discCenter = CGPoint(x: 230, y: 489)
        var discDiameter: CGFloat = 322
        var parkedDisc = CGPoint(x: 230, y: 245)
        var tiltDegrees: Double = 18
        var maximumOpening: Double = 82
        var dragTravel: Double = 300

        // The lower deck is deliberately split into a readable display module
        // and a separate hardware transport row. Keep these in model space so
        // they share the same physical perspective as the player body.
        var lowerDeck = CGRect(x: 38, y: 575, width: 384, height: 169)
        var lcd = CGRect(x: 58, y: 592, width: 344, height: 70)
        var controls: [CDControl: CGRect] = [
            .previous: CGRect(x: 68, y: 682, width: 58, height: 58),
            .playPause: CGRect(x: 158, y: 671, width: 78, height: 78),
            .next: CGRect(x: 270, y: 682, width: 58, height: 58),
            // Mechanical lid control follows the transport trio, matching the
            // physical reading order: previous → play/pause → next → open/close.
            .open: CGRect(x: 354, y: 687, width: 50, height: 50)
        ]
        func projectedY(_ y: CGFloat) -> CGFloat {
            hingeY + (y - hingeY) * cos(tiltDegrees * .pi / 180)
        }
    }
    enum Motion {
        // Mechanical travel stays legible; subpixel tails must not delay playback.
        static let springFrequency = 24.0
        static let normalizedTolerance = 0.001
        static let positionTolerance = 0.25
    }

    struct Assets {
        var body = "listen_01_body_shell"
        var lidOuter = "listen_02_lid_outer"
        var lidInner = "listen_03_lid_inner"
        var disc = "listen_04_disc"
        // The body already contains its tray, controls and hinges. Do not stack
        // duplicate asset-board components over the same photographed features.
    }
    var brand: String
    var model: String
    var themeName: String
    var geometry = Geometry()
    var assets = Assets()

    static let standard = CDPlayerConfiguration(
        brand: "BEFORESHOW",
        model: "BS-CD01",
        themeName: "经典暗黑",
        geometry: Geometry()
    )
}

extension CDPlayerConfiguration: Equatable, Identifiable {
    var id: String { "\(brand)-\(model)-\(themeName)" }
    static func == (lhs: CDPlayerConfiguration, rhs: CDPlayerConfiguration) -> Bool {
        lhs.id == rhs.id
    }
}

enum CDControl: String, CaseIterable, Identifiable {
    case previous, next, playPause, stop, open
    var id: String { rawValue }
    var label: String {
        switch self {
        case .previous: "上一曲"
        case .next: "下一曲"
        case .playPause: "播放或暂停"
        case .stop: "停止"
        case .open: "打开或关闭上盖"
        }
    }
}
