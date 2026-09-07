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
    var themeName: String
    var geometry = Geometry()
    var assets = Assets()

    static let silverMetal = CDPlayerConfiguration(
        brand: "BEFORESHOW",
        model: "BS-CD01",
        themeName: "铝合金银",
        geometry: Geometry(
            lcd: CGRect(x: 178, y: 641, width: 122, height: 56),
            controls: [
                .previous: CGRect(x: 84, y: 637, width: 44, height: 44),
                .next: CGRect(x: 133, y: 649, width: 44, height: 44),
                .playPause: CGRect(x: 308, y: 649, width: 44, height: 44),
                .stop: CGRect(x: 357, y: 637, width: 44, height: 44),
                .open: CGRect(x: 198, y: 720, width: 68, height: 32)
            ]
        ),
        assets: Assets(
            body: "listen_silver_body",
            lidOuter: "listen_silver_lid_outer",
            lidInner: "listen_03_lid_inner",
            disc: "listen_04_disc"
        )
    )

    static let translucentAqua = CDPlayerConfiguration(
        brand: "BEFORESHOW",
        model: "Y2K-CLEAR",
        themeName: "极光透明蓝",
        geometry: Geometry(
            lcd: CGRect(x: 178, y: 641, width: 122, height: 56),
            controls: [
                .previous: CGRect(x: 84, y: 637, width: 44, height: 44),
                .next: CGRect(x: 133, y: 649, width: 44, height: 44),
                .playPause: CGRect(x: 308, y: 649, width: 44, height: 44),
                .stop: CGRect(x: 357, y: 637, width: 44, height: 44),
                .open: CGRect(x: 198, y: 720, width: 68, height: 32)
            ]
        ),
        assets: Assets(
            body: "listen_aqua_body",
            lidOuter: "listen_aqua_lid_outer",
            lidInner: "listen_03_lid_inner",
            disc: "listen_04_disc"
        )
    )

    static let saddleLeather = CDPlayerConfiguration(
        brand: "BEFORESHOW",
        model: "RETRO-GOLD",
        themeName: "复古皮质金",
        geometry: Geometry(
            lcd: CGRect(x: 174, y: 672, width: 112, height: 44),
            controls: [
                .previous: CGRect(x: 94, y: 730, width: 44, height: 44),
                .next: CGRect(x: 146, y: 754, width: 44, height: 44),
                .playPause: CGRect(x: 208, y: 768, width: 48, height: 48),
                .stop: CGRect(x: 270, y: 754, width: 44, height: 44),
                .open: CGRect(x: 348, y: 326, width: 46, height: 46)
            ]
        )
    )

    static let sportRed = CDPlayerConfiguration(
        brand: "BEFORESHOW",
        model: "SPORT-RED",
        themeName: "机械运动红",
        geometry: Geometry(
            lcd: CGRect(x: 148, y: 670, width: 164, height: 46),
            controls: [
                .previous: CGRect(x: 144, y: 764, width: 48, height: 48),
                .next: CGRect(x: 268, y: 764, width: 48, height: 48),
                .playPause: CGRect(x: 204, y: 772, width: 56, height: 56),
                .stop: CGRect(x: 88, y: 694, width: 48, height: 48),
                .open: CGRect(x: 178, y: 262, width: 104, height: 34)
            ]
        )
    )

    static let standard = CDPlayerConfiguration(
        brand: "BEFORESHOW",
        model: "BS-CD01",
        themeName: "经典暗黑",
        geometry: Geometry()
    )

    static let allThemes: [CDPlayerConfiguration] = [
        .standard,
        .silverMetal,
        .translucentAqua,
        .saddleLeather,
        .sportRed
    ]
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
