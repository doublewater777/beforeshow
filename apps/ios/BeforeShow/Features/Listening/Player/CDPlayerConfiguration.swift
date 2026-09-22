import SwiftUI

/// The calibrated machine uses a 360 × 580 stage and one fixed hinge.
/// Assets are UV textures, never independent layout-sized photographs.
struct CDPlayerConfiguration {
    struct Geometry {
        var viewportTop: CGFloat = 0
        var canvas = CGSize(width: 360, height: 580)
        // Fixed texture/display bounds. Moving discs and the lid use the camera
        // projection below so the closed and open poses share one hinge.
        var body = CGRect(x: 8, y: 102, width: 344, height: 469)
        var discPod = CGRect(x: 34, y: 110, width: 294, height: 294)
        var lid = CGRect(x: 34, y: 110, width: 294, height: 294)
        var hingeY: CGFloat = 110
        var discCenter = CGPoint(x: 180, y: 259)
        var discDiameter: CGFloat = 254
        var parkedDisc = CGPoint(x: 180, y: 0)
        var tiltDegrees: Double = 30
        var maximumOpening: Double = 78
        var dragTravel: Double = 300
        var lowerDeck = CGRect(x: 35, y: 369, width: 292, height: 184)
        var lcd = CGRect(x: 42.5, y: 374, width: 275, height: 65)
        var controls: [CDControl: CGRect] = [
            .previous: CGRect(x: 54.5, y: 471.5, width: 43, height: 43),
            .playPause: CGRect(x: 119.5, y: 462.5, width: 61, height: 61),
            .next: CGRect(x: 203.5, y: 471.5, width: 43, height: 43),
            .open: CGRect(x: 267.75, y: 473.75, width: 38.5, height: 38.5)
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
        var body = "cd_machine"
        var lidInner = "cd_lid_inside"
        var lidGlass = "cd_glass"
        var spindle = "cd_spindle"
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
