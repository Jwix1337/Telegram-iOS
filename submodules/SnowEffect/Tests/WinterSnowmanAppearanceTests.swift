import XCTest
import CoreGraphics
@testable import SnowEffect

final class WinterSnowmanAppearanceTests: XCTestCase {
    private func session(hat: Int, color: Int, count: Int = 8) -> WinterSnowmanSession {
        var parts = Dictionary(uniqueKeysWithValues: SnowmanPart.assembly.prefix(count).map { ($0, 1) })
        parts[.hatStyle] = hat; parts[.scarfColor] = color
        return .serverSnapshot(id: "11111111-1111-4111-8111-111111111111", inviter: 1, invitee: 2,
            createdAt: 1800000000000, accepted: true, completed: count == 8, parts: parts, version: 10)
    }
    func testAllTenSnowmanHatsFitHeadWithoutCroppingAndRetainAspect() throws {
        for style in WinterSnowmanHatStyle.allCases {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: style.rawValue))
            let p = try XCTUnwrap(WinterSnowmanGeometry.hat(style, imageSize: art.crop.size))
            let frame = CGRect(x: p.center.x - p.size.width / 2, y: p.center.y - p.size.height / 2, width: p.size.width, height: p.size.height)
            XCTAssertGreaterThan(frame.minY, 0)
            XCTAssertGreaterThan(frame.minX, 0)
            XCTAssertLessThan(frame.maxX, 1024)
            XCTAssertLessThan(frame.maxY, WinterSnowmanGeometry.middle.midY)
            XCTAssertEqual(p.size.width / p.size.height, art.crop.width / art.crop.height, accuracy: 0.000001)
        }
    }

    func testAllTenHatIDsAndAllSixScarfColorsRemainRepresentable() {
        XCTAssertEqual(WinterSnowmanHatStyle.allCases.map(\.rawValue), Array(1 ... 10))
        for hat in 1 ... 10 {
            for color in 0 ... 5 {
                let state = session(hat: hat, color: color)
                let preset = WinterSnowmanReadyPreset.matching(state)
                if hat == 1 && color < 2 {
                    XCTAssertEqual(preset, color == 0 ? .classicRed : .santaBlueScarf)
                } else { XCTAssertNil(preset) }
                XCTAssertEqual(state.value(.hatStyle), hat)
                XCTAssertEqual(state.value(.scarfColor), color)
            }
        }
    }
    func testNoWholePNGForUnfinishedSnowman() {
        for color in 0 ... 5 {
            XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 8, color: color, count: 7)))
        }
        for count in 0 ... 6 {
            XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 1, color: 0, count: count)))
        }
    }
    func testNoBlueLightsOrNeonToTopHatSubstitutionAndNoFestivePresets() {
        XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 6, color: 1)))
        XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 10, color: 0)))
        XCTAssertEqual(WinterSnowmanReadyPreset.allCases.count, 2)
        XCTAssertFalse(WinterSnowmanReadyPreset.allCases.contains { $0.rawValue.contains("festive") })
    }
}
