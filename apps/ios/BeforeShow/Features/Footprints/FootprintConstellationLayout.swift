import CoreGraphics
import Foundation

/// The artist sky: one star per artist worth naming, lines for shared bills.
struct FootprintConstellation: Equatable {
    struct Star: Equatable, Identifiable {
        let name: String
        let count: Int
        /// Unit-square position; the view scales it into its own frame.
        let position: CGPoint
        /// Seen more than once but never on a shared bill with another star.
        let isLone: Bool

        var id: String { name }
    }

    struct Edge: Equatable, Hashable {
        let from: String
        let to: String
    }

    struct Group: Equatable {
        /// Named after its brightest star.
        let brightest: String
        /// Below the group's lowest star, centred on the group, so the name never sits on a star.
        let labelAnchor: CGPoint
    }

    let stars: [Star]
    let edges: [Edge]
    let groups: [Group]
    /// Artists not drawn as named stars; each is one point of background dust.
    let dustCount: Int
}

@MainActor
enum FootprintConstellationBuilder {
    static let maxRepeatStars = 14
    static let maxStars = 22

    static func make(shows: [Show]) -> FootprintConstellation {
        let ordered = FootprintArchiveRankingBuilder.chronological(shows)
        let lineups: [[String]] = ordered.map { show in
            var seen = Set<String>()
            return show.artistNames
                .compactMap(FootprintTextNormalizer.nonEmptyTrimmed)
                .filter { seen.insert($0).inserted }
        }
        let counts = lineups.reduce(into: [String: Int]()) { result, lineup in
            for name in lineup { result[name, default: 0] += 1 }
        }

        let repeats = counts.filter { $0.value > 1 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(maxRepeatStars)
            .map(\.key)
        var chosen = Set(repeats)
        var order = repeats
        // Single-show artists earn a star only when they shared a bill with a repeat star.
        for lineup in lineups where lineup.contains(where: chosen.contains) {
            for name in lineup where !chosen.contains(name) && order.count < maxStars {
                chosen.insert(name)
                order.append(name)
            }
        }

        var edges: [FootprintConstellation.Edge] = []
        var edgeKeys = Set<String>()
        for lineup in lineups {
            let onSky = lineup.filter(chosen.contains)
            guard onSky.count > 1 else { continue }
            for (a, b) in zip(onSky, onSky.dropFirst()) {
                let key = [a, b].sorted().joined(separator: "\u{1F}")
                guard edgeKeys.insert(key).inserted else { continue }
                edges.append(FootprintConstellation.Edge(from: a, to: b))
            }
        }

        let connected = Set(edges.flatMap { [$0.from, $0.to] })
        let positions = layout(names: order, edges: edges)
        let stars = order.map { name in
            FootprintConstellation.Star(
                name: name,
                count: counts[name] ?? 1,
                position: positions[name] ?? CGPoint(x: 0.5, y: 0.5),
                isLone: !connected.contains(name)
            )
        }
        return FootprintConstellation(
            stars: stars,
            edges: edges,
            groups: groups(stars: stars, edges: edges),
            dustCount: max(0, counts.count - stars.count)
        )
    }

    /// Connected components of three or more stars become named constellations.
    private static func groups(
        stars: [FootprintConstellation.Star],
        edges: [FootprintConstellation.Edge]
    ) -> [FootprintConstellation.Group] {
        var neighbours: [String: Set<String>] = [:]
        for edge in edges {
            neighbours[edge.from, default: []].insert(edge.to)
            neighbours[edge.to, default: []].insert(edge.from)
        }
        let byName = Dictionary(uniqueKeysWithValues: stars.map { ($0.name, $0) })
        var visited = Set<String>()
        var result: [FootprintConstellation.Group] = []
        for star in stars where !visited.contains(star.name) && neighbours[star.name] != nil {
            var component: [FootprintConstellation.Star] = []
            var queue = [star.name]
            visited.insert(star.name)
            while let name = queue.popLast() {
                if let member = byName[name] { component.append(member) }
                for next in neighbours[name] ?? [] where visited.insert(next).inserted {
                    queue.append(next)
                }
            }
            guard component.count >= 3,
                  let brightest = component.max(by: {
                      $0.count == $1.count ? $0.name > $1.name : $0.count < $1.count
                  }) else { continue }
            let anchor = CGPoint(
                x: component.map(\.position.x).reduce(0, +) / CGFloat(component.count),
                y: component.map(\.position.y).max() ?? 0.5
            )
            result.append(FootprintConstellation.Group(brightest: brightest.name, labelAnchor: anchor))
        }
        return result
    }

    /// Deterministic force layout: same archive, same sky.
    static func layout(names: [String], edges: [FootprintConstellation.Edge]) -> [String: CGPoint] {
        guard !names.isEmpty else { return [:] }
        var points = names.map(seedPoint)
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        let links = edges.compactMap { edge -> (Int, Int)? in
            guard let a = index[edge.from], let b = index[edge.to] else { return nil }
            return (a, b)
        }
        let ideal = 0.9 / sqrt(Double(names.count))
        for step in 0..<240 {
            let cooling = 0.08 * (1 - Double(step) / 240)
            var forces = Array(repeating: (x: 0.0, y: 0.0), count: names.count)
            for i in names.indices {
                for j in names.indices where j > i {
                    let dx = points[i].x - points[j].x
                    let dy = points[i].y - points[j].y
                    let distance = max(0.01, (dx * dx + dy * dy).squareRoot())
                    let push = ideal * ideal / distance
                    forces[i].x += dx / distance * push
                    forces[i].y += dy / distance * push
                    forces[j].x -= dx / distance * push
                    forces[j].y -= dy / distance * push
                }
            }
            for (a, b) in links {
                let dx = points[a].x - points[b].x
                let dy = points[a].y - points[b].y
                let distance = max(0.01, (dx * dx + dy * dy).squareRoot())
                let pull = distance * distance / ideal
                forces[a].x -= dx / distance * pull
                forces[a].y -= dy / distance * pull
                forces[b].x += dx / distance * pull
                forces[b].y += dy / distance * pull
            }
            for i in names.indices {
                forces[i].x += (0.5 - points[i].x) * 0.6
                forces[i].y += (0.5 - points[i].y) * 0.6
                let length = max(0.0001, (forces[i].x * forces[i].x + forces[i].y * forces[i].y).squareRoot())
                let move = min(length, cooling)
                points[i].x += forces[i].x / length * move
                points[i].y += forces[i].y / length * move
            }
        }
        return Dictionary(uniqueKeysWithValues: zip(names, normalized(points)))
    }

    private static func seedPoint(for name: String) -> (x: Double, y: Double) {
        let hash = name.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        return (
            x: 0.2 + Double(hash % 1000) / 1000 * 0.6,
            y: 0.2 + Double((hash / 1000) % 1000) / 1000 * 0.6
        )
    }

    /// Stretch the result to fill the sky with a margin for labels.
    private static func normalized(_ points: [(x: Double, y: Double)]) -> [CGPoint] {
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let margin = 0.1
        func scale(_ value: Double, _ low: Double, _ high: Double) -> Double {
            high - low < 0.0001 ? 0.5 : margin + (value - low) / (high - low) * (1 - margin * 2)
        }
        return points.map { CGPoint(x: scale($0.x, minX, maxX), y: scale($0.y, minY, maxY)) }
    }
}
