import SwiftUI

/// All dimensions are measured in one immutable 460 × 740 model space.
/// Assets are UV textures, never independent layout-sized photographs.
struct CDPlayerConfiguration {
    struct Geometry {
        /// Fixed display crop; motion continues in the full model coordinate space.
        var viewportTop: CGFloat = 195
        var canvas = CGSize(width: 460, height: 740)
        var body = CGRect(x: 20, y: 278, width: 420, height: 466)
        var lid = CGRect(x: 30, y: 304, width: 400, height: 353)
        var hingeY: CGFloat = 304
        var discCenter = CGPoint(x: 230, y: 489)
        var discDiameter: CGFloat = 322
        var parkedDisc = CGPoint(x: 230, y: 245)
        var tiltDegrees: Double = 18
        var maximumOpening: Double = 118
        var dragTravel: Double = 300
        var lcd = CGRect(x: 150, y: 679, width: 122, height: 35)
        var controls: [CDControl: CGRect] = [
            .previous: CGRect(x: 44, y: 662, width: 43, height: 45),
            .next: CGRect(x: 87, y: 674, width: 43, height: 44),
            .playPause: CGRect(x: 285, y: 674, width: 43, height: 44),
            .stop: CGRect(x: 328, y: 666, width: 43, height: 44),
            .open: CGRect(x: 372, y: 641, width: 48, height: 50)
        ]
        func projectedY(_ y: CGFloat) -> CGFloat {
            hingeY + (y - hingeY) * cos(tiltDegrees * .pi / 180)
        }
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
    var geometry = Geometry()
    var assets = Assets()
    static let panasonic = CDPlayerConfiguration(brand: "Panasonic", model: "SL-S120")
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
