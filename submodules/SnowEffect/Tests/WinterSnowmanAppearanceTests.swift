import XCTest
@testable import SnowEffect

final class WinterSnowmanAppearanceTests: XCTestCase {
    private func session(hat: Int, color: Int, count: Int = 8) -> WinterSnowmanSession {
        var parts = Dictionary(uniqueKeysWithValues: SnowmanPart.assembly.prefix(count).map { ($0, 1) })
        parts[.hatStyle] = hat; parts[.scarfColor] = color
        return .serverSnapshot(id: "11111111-1111-4111-8111-111111111111", inviter: 1, invitee: 2,
            createdAt: 1800000000000, accepted: true, completed: false, parts: parts, version: 10)
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
    func testBareHeadRequiresEveryPreviousAssemblyPartAndExactScarf() {
        for color in 0 ... 5 {
            XCTAssertEqual(WinterSnowmanReadyPreset.matching(session(hat: 8, color: color, count: 7)), color == 0 ? .redScarf : color == 1 ? .blueScarf : nil)
        }
        for count in 0 ... 6 {
            XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 1, color: 0, count: count)))
        }
    }
    func testNoBlueLightsOrNeonToTopHatSubstitutionAndNoFestivePresets() {
        XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 6, color: 1)))
        XCTAssertNil(WinterSnowmanReadyPreset.matching(session(hat: 10, color: 0)))
        XCTAssertEqual(WinterSnowmanReadyPreset.allCases.count, 4)
        XCTAssertFalse(WinterSnowmanReadyPreset.allCases.contains { $0.rawValue.contains("festive") })
    }
}
