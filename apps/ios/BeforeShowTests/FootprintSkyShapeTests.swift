import CoreGraphics
import XCTest
@testable import BeforeShow

@MainActor
final class FootprintSkyShapeTests: XCTestCase {
    private func sky(_ counts: [(String, Int)]) -> FootprintConstellation {
        FootprintConstellation(
            stars: counts.enumerated().map { index, item in
                .init(name: item.0, count: item.1, position: CGPoint(x: 0.1 + Double(index) * 0.08, y: 0.5), isLone: false)
            },
            edges: [.init(from: counts[0].0, to: counts[1].0)],
            groups: [],
            dustCount: 3
        )
    }

    func testTheFreeSkyIsLeftAsItIs() {
        let free = sky([("A", 3), ("B", 1)])
        XCTAssertEqual(FootprintSkyShape.free.apply(to: free), free)
    }

    func testTheMostSeenArtistsTakeTheConstellationsBrightestStars() throws {
        let figure = try XCTUnwrap(FootprintSkyShape.bigDipper.figure)
        let result = FootprintSkyShape.bigDipper.apply(to: sky((1...9).map { ("\($0)", $0) }))
        let byName = Dictionary(uniqueKeysWithValues: result.stars.map { ($0.name, $0.position) })
        // 看得最多的 9 → 最亮的玉衡，8 → 天枢。
        XCTAssertEqual(byName["9"], figure.points[0])
        XCTAssertEqual(byName["8"], figure.points[1])
        XCTAssertEqual(result.edges.count, figure.lines.count, "lines draw the figure, not shared bills")
        XCTAssertEqual(result.groups.first?.title, FootprintSkyShape.bigDipper.title)
        XCTAssertEqual(result.dustCount, 3)
        for name in ["1", "2"] {
            let point = try XCTUnwrap(byName[name])
            XCTAssert(figure.points.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= 0.139 }, "\(name) steps out of the figure")
        }
    }

    func testASmallSkyDrawsOnlyThePartOfTheFigureItCanFill() {
        let result = FootprintSkyShape.orion.apply(to: sky([("A", 2), ("B", 1), ("C", 1)]))
        let names = Set(result.stars.map(\.name))
        XCTAssert(result.edges.allSatisfy { names.contains($0.from) && names.contains($0.to) })
    }

    func testEveryFigureFitsTheSkyAndItsLinesPointAtItsStars() {
        for shape in FootprintSkyShape.allCases {
            guard let figure = shape.figure else { continue }
            XCTAssert(figure.points.allSatisfy { (0.05...0.95).contains($0.x) && (0.05...0.95).contains($0.y) }, shape.title)
            XCTAssert(figure.lines.allSatisfy { figure.points.indices.contains($0.0) && figure.points.indices.contains($0.1) }, shape.title)
        }
    }

    func testProShapesFallBackToTheFreeSkyWithoutPro() {
        XCTAssertEqual(FootprintSkyShape.effective("orion", isPro: true), .orion)
        XCTAssertEqual(FootprintSkyShape.effective("orion", isPro: false), .free)
    }
}
