import UIKit
import XCTest
@testable import SnowEffect

final class WinterMiniSnowmanTests: XCTestCase {
    func testReservedSpaceAndVisibleHeightLimits() {
        XCTAssertEqual(WinterMiniSnowmanLayout.reservedHeight(available: 219, width: 390), 0)
        for width in [CGFloat(200), 390, 1024] {
            let height = WinterMiniSnowmanLayout.reservedHeight(available: 400, width: width) - 8
            XCTAssertGreaterThanOrEqual(height, 48)
            XCTAssertLessThanOrEqual(height, 72)
        }
    }
    func testIndependentPreferenceRoundTripAndLegacyDefault() throws {
        var settings = try JSONDecoder().decode(SnowEffectSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.showMiniSnowman)
        settings.enabled = true; settings.winterSnowmanEnabled = true; settings.showMiniSnowman = false
        let saved = try JSONDecoder().decode(SnowEffectSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(saved.showMiniSnowman)
        XCTAssertTrue(saved.enabled)
        XCTAssertTrue(saved.winterSnowmanEnabled)
    }
    func testAlphaBoundsUseBottomOfCharacterNotSquareCanvas() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 160, y: 80, width: 160, height: 320))
        }
        let bounds = try XCTUnwrap(WinterMiniSnowmanView.alphaBounds(try XCTUnwrap(image.cgImage)))
        XCTAssertEqual(bounds.minY, 80, accuracy: 8)
        XCTAssertEqual(bounds.maxY, 400, accuracy: 8)
        XCTAssertLessThan(bounds.height, 512)
    }
}
