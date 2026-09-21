import SwiftUI

/// All dimensions are measured in one immutable 460 × 740 model space.
/// Assets are UV textures, never independent layout-sized photographs.
struct CDPlayerConfiguration {
    struct Geometry {
        /// Fixed display crop; motion continues in the full model coordinate space.
        var viewportTop: CGFloat = 230
        var canvas = CGSize(width: 460, height: 800)

        // "body" remains the stable sizing reference used by the room, while
        // the visible hardware is split into an upper CD pod and a narrower
        // lower control deck.
        var body = CGRect(x: 32, y: 286, width: 396, height: 500)
        var discPod = CGRect(x: 38, y: 300, width: 384, height: 330)
        var lid = CGRect(x: 55, y: 302, width: 350, height: 310)
        var hingeY: CGFloat = 302
        var discCenter = CGPoint(x: 230, y: 462)
        var discDiameter: CGFloat = 296
        var parkedDisc = CGPoint(x: 230, y: 248)
        var tiltDegrees: Double = 18
        var maximumOpening: Double = 82
        var dragTravel: Double = 300

        // The display/control deck sits completely below the optical chamber.
        // It is deliberately narrower than the CD pod so the machine reads as
        // hardware, not as one full-height rounded card.
        var lowerDeck = CGRect(x: 66, y: 642, width: 328, height: 150)
        var lcd = CGRect(x: 84, y: 654, width: 292, height: 58)
        var controls: [CDControl: CGRect] = [
            .previous: CGRect(x: 84, y: 728, width: 48, height: 48),
            .playPause: CGRect(x: 154, y: 718, width: 68, height: 68),
            .next: CGRect(x: 244, y: 728, width: 48, height: 48),
            // Mechanical lid control follows the transport trio, matching the
            // physical reading order: previous → play/pause → next → open/close.
            .open: CGRect(x: 320, y: 731, width: 44, height: 44)
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
        // The machine shell, tray and lid are native SwiftUI materials. Only
        // the disc remains an image-backed texture because album artwork is
        // composited into that surface at runtime.
        var disc = "listen_04_disc"
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
