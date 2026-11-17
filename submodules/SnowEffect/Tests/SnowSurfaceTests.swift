import Foundation
import CoreGraphics
import XCTest
@testable import SnowEffect

final class SnowSurfaceTests: XCTestCase {
    func testMicrophoneDustingIsShallowAndCentredAndRecordingCanRemoveItsSurface() {
        let profile = [0.0, 8, 16, 4, 0]
        let compact = SnowAccumulationSurface.depositedHeights(profile, width: 40)
        XCTAssertEqual(compact, Array(compact.reversed()))
        XCTAssertLessThan(compact.max() ?? 100, 5)
        XCTAssertEqual(compact.first, 0)
        XCTAssertEqual(SnowAccumulationSurface.depositedHeights(profile, width: 240), profile)
        XCTAssertTrue(SnowAccumulationSurface.depositedHeights(profile, width: 0).isEmpty)
    }

    func testThreePillSurfacesStayInsideTheirOwnHorizontalBoundsAndFollowCurvedTops() throws {
        let surfaces = [CGRect(x: 8, y: 10, width: 40, height: 40), CGRect(x: 54, y: 10, width: 258, height: 90), CGRect(x: 318, y: 60, width: 40, height: 40)]
        let heights = (0...40).map { sin(Double($0) / 40 * .pi) * 6.5 }
        for surface in surfaces {
            let samples = try XCTUnwrap(SnowAccumulationSurface.samples(frame: surface, heights: heights, cornerRadius: 20))
            for (upper, lower) in zip(samples.upper, samples.lower) {
                XCTAssertGreaterThan(upper.x, surface.minX)
                XCTAssertLessThan(upper.x, surface.maxX)
                XCTAssertEqual(upper.x, lower.x)
                XCTAssertLessThanOrEqual(upper.y, lower.y + 0.000001)
                XCTAssertLessThanOrEqual(lower.y - upper.y, 6.5 + 0.000001)
                XCTAssertLessThan(lower.y - surface.minY - 24, 8)
            }
            XCTAssertGreaterThan(try XCTUnwrap(samples.lower.first).y, samples.lower[20].y)
            XCTAssertEqual(try XCTUnwrap(samples.upper.first), try XCTUnwrap(samples.lower.first))
        }
        XCTAssertNil(SnowAccumulationSurface.samples(frame: .zero, heights: heights))
        XCTAssertNil(SnowAccumulationSurface.samples(frame: surfaces[0], heights: [.nan, 1]))
    }
}
