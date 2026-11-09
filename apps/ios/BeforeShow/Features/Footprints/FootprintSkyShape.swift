import CoreGraphics
import Foundation

/// 星星怎么排：默认按同场演出自由排开；Pro 可以排成天上真实的星座。
enum FootprintSkyShape: String, CaseIterable, Identifiable {
    case free
    case bigDipper
    case orion
    case cassiopeia
    case scorpius

    static let storageKey = "footprintSkyShape"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: BSLocalization.text("自由星空")
        case .bigDipper: BSLocalization.text("北斗七星")
        case .orion: BSLocalization.text("猎户座")
        case .cassiopeia: BSLocalization.text("仙后座")
        case .scorpius: BSLocalization.text("天蝎座")
        }
    }

    var isPro: Bool { self != .free }

    static func effective(_ rawValue: String, isPro: Bool) -> FootprintSkyShape {
        guard let shape = FootprintSkyShape(rawValue: rawValue), !shape.isPro || isPro else { return .free }
        return shape
    }

    /// 星座的星，最亮的在前（单位坐标，y 向下），连线用下标。
    var figure: (points: [CGPoint], lines: [(Int, Int)])? {
        switch self {
        case .free:
            return nil
        case .bigDipper:
            // 玉衡、天枢、摇光、开阳、天璇、天玑、天权
            return ([
                CGPoint(x: 0.40, y: 0.42), CGPoint(x: 0.84, y: 0.38), CGPoint(x: 0.12, y: 0.26), CGPoint(x: 0.26, y: 0.34),
                CGPoint(x: 0.83, y: 0.62), CGPoint(x: 0.58, y: 0.64), CGPoint(x: 0.56, y: 0.45)
            ], [(2, 3), (3, 0), (0, 6), (6, 1), (1, 4), (4, 5), (5, 6)])
        case .orion:
            // 参宿七、参宿四、参宿五、参宿二、参宿一、参宿六、参宿三、觜宿一
            return ([
                CGPoint(x: 0.74, y: 0.80), CGPoint(x: 0.26, y: 0.24), CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.50, y: 0.52),
                CGPoint(x: 0.36, y: 0.57), CGPoint(x: 0.30, y: 0.82), CGPoint(x: 0.64, y: 0.47), CGPoint(x: 0.50, y: 0.12)
            ], [(7, 1), (7, 2), (1, 4), (2, 6), (4, 3), (3, 6), (4, 5), (6, 0)])
        case .cassiopeia:
            // 策、王良一、王良四、阁道三、阁道二
            return ([
                CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.33, y: 0.60), CGPoint(x: 0.14, y: 0.36), CGPoint(x: 0.67, y: 0.60),
                CGPoint(x: 0.86, y: 0.38)
            ], [(2, 1), (1, 0), (0, 3), (3, 4)])
        case .scorpius:
            // 心宿二、尾宿八、尾宿五、房宿三、尾宿二、房宿四、心宿三、房宿一、心宿一、尾宿一、尾宿三、尾宿四
            return ([
                CGPoint(x: 0.54, y: 0.37), CGPoint(x: 0.14, y: 0.70), CGPoint(x: 0.20, y: 0.85), CGPoint(x: 0.72, y: 0.20),
                CGPoint(x: 0.46, y: 0.56), CGPoint(x: 0.88, y: 0.10), CGPoint(x: 0.50, y: 0.46), CGPoint(x: 0.88, y: 0.30),
                CGPoint(x: 0.60, y: 0.27), CGPoint(x: 0.44, y: 0.67), CGPoint(x: 0.42, y: 0.78), CGPoint(x: 0.31, y: 0.87)
            ], [(5, 3), (3, 7), (3, 8), (8, 0), (0, 6), (6, 4), (4, 9), (9, 10), (10, 11), (11, 2), (2, 1)])
        }
    }

    /// 看得最多的艺人放到星座最亮的星上，连线画星座；其余的星让开星座，留在原处附近。
    func apply(to sky: FootprintConstellation) -> FootprintConstellation {
        guard let figure, !sky.stars.isEmpty else { return sky }
        let ranked = sky.stars.enumerated()
            .sorted { $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count }
            .map(\.element.name)
        let placed = Dictionary(uniqueKeysWithValues: zip(ranked, figure.points))
        let figurePoints = Array(placed.values)
        let stars = sky.stars.map { star in
            FootprintConstellation.Star(
                name: star.name,
                count: star.count,
                position: placed[star.name] ?? Self.clear(star.position, of: figurePoints),
                isLone: star.isLone
            )
        }
        let count = placed.count
        let edges = figure.lines
            .filter { $0.0 < count && $0.1 < count }
            .map { FootprintConstellation.Edge(from: ranked[$0.0], to: ranked[$0.1]) }
        let anchor = CGPoint(
            x: figurePoints.map(\.x).reduce(0, +) / CGFloat(max(1, count)),
            // A little below the figure's lowest star, clear of that star's own name.
            y: min(0.9, (figurePoints.map(\.y).max() ?? 0.5) + 0.08)
        )
        return FootprintConstellation(
            stars: stars,
            edges: edges,
            groups: [.init(brightest: ranked[0], labelAnchor: anchor, title: title)],
            dustCount: sky.dustCount
        )
    }

    /// Stars not on the figure step out of its way so the shape reads clearly.
    private static let clearance: CGFloat = 0.14

    private static func clear(_ point: CGPoint, of figure: [CGPoint]) -> CGPoint {
        guard let nearest = figure.min(by: { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) }) else { return point }
        let dx = point.x - nearest.x, dy = point.y - nearest.y
        let distance = hypot(dx, dy)
        guard distance < clearance else { return point }
        let direction = distance > 0.0001 ? CGPoint(x: dx / distance, y: dy / distance) : CGPoint(x: 0, y: 1)
        return CGPoint(
            x: min(0.94, max(0.06, nearest.x + direction.x * clearance)),
            y: min(0.94, max(0.06, nearest.y + direction.y * clearance))
        )
    }
}
