import XCTest
@testable import BeforeShow

final class FootprintYearPosterGridTests: XCTestCase {
    private let area = CGSize(width: 360, height: 480)

    func testOneShowTakesTheWholeWidth() {
        let grid = FootprintYearPosterGrid(count: 1, in: area, aspect: 0.75, gap: 2)

        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.cell.width, 360, accuracy: 0.01)
    }

    func testEveryShowGetsACellAndTheCellsFit() {
        for count in [2, 4, 7, 15, 38, 60] {
            let grid = FootprintYearPosterGrid(count: count, in: area, aspect: 0.75, gap: 2)

            XCTAssertGreaterThanOrEqual(grid.columns * grid.rows, count, "\(count)")
            XCTAssertLessThan(grid.columns * (grid.rows - 1), count, "\(count) leaves a whole empty row")
            XCTAssertLessThanOrEqual(CGFloat(grid.columns) * grid.cell.width + CGFloat(grid.columns - 1) * 2, area.width + 0.01, "\(count)")
            XCTAssertLessThanOrEqual(CGFloat(grid.rows) * grid.cell.height + CGFloat(grid.rows - 1) * 2, area.height + 0.01, "\(count)")
        }
    }

    func testPicksTheColumnCountWithTheLargestCells() {
        XCTAssertEqual(FootprintYearPosterGrid(count: 4, in: area, aspect: 0.75, gap: 2).columns, 2)
        XCTAssertEqual(FootprintYearPosterGrid(count: 15, in: area, aspect: 0.75, gap: 2).columns, 4)
    }

    func testExtraHeightPerRowIsLeftOverForTheFilmEdges() {
        let grid = FootprintYearPosterGrid(count: 10, in: CGSize(width: 360, height: 160), aspect: 0.75, gap: 2, rowExtra: 20)

        XCTAssertLessThanOrEqual(CGFloat(grid.rows) * (grid.cell.height + 20) + CGFloat(grid.rows - 1) * 2, 160.01)
    }
}
