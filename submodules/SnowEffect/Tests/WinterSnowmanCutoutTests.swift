import Foundation
import CoreGraphics
import ImageIO
import XCTest
@testable import SnowEffect

final class WinterSnowmanCutoutTests: XCTestCase {
    private func source() throws -> CGImage {
        guard let root = ProcessInfo.processInfo.environment["SNOW_WINTER_ASSET_ROOT"] else { throw XCTSkip("Run test_winter_models.py to supply immutable reference artwork") }
        let url = URL(fileURLWithPath: root).appendingPathComponent("SnowmanReady_01_classic_red_Full.imageset/01_classic_red.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        Array(try XCTUnwrap(image.dataProvider?.data) as Data)
    }

    func testAuthenticPartsHaveTransparentBackgroundAndNeverIncludeTheBodyOrHat() throws {
        let source = try self.source()
        for part in [WinterSnowmanCutout.Part.scarf, .arms, .nose] {
            let image = try XCTUnwrap(WinterSnowmanCutout.image(from: source, part: part))
            let data = try bytes(image)
            var visible = 0
            for y in 0..<512 { for x in 0..<512 where data[(y * 512 + x) * 4 + 3] > 0 {
                visible += 1
                XCTAssertGreaterThanOrEqual(y, part == .nose ? 163 : 198)
                XCTAssertLessThan(y, part == .scarf ? 390 : (part == .nose ? 208 : 294))
                XCTAssertGreaterThanOrEqual(x, 90)
                XCTAssertLessThan(x, 422)
                if part == .arms { XCTAssertTrue(x < 185 || x > 325, "Arms must not reveal the scarf before it is added") }
            } }
            XCTAssertGreaterThan(visible, part == .scarf ? 5000 : (part == .arms ? 600 : 40))
            XCTAssertEqual(data[(430 * 512 + 250) * 4 + 3], 0)  // Bottom ball.
            XCTAssertEqual(data[(80 * 512 + 250) * 4 + 3], 0)   // Hat.
            let png = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                if CGImageDestinationFinalize(destination) {
                    // Inspection aid in CI logs; decode to a local PNG without dumping the log in chat.
                    let encoded = Array((png as Data).base64EncodedString())
                    for start in stride(from: 0, to: encoded.count, by: 8000) {
                        print("SNOW_PART_PNG_" + part.rawValue + "_" + String(start / 8000) + ":" + String(encoded[start..<min(encoded.count, start + 8000)]))
                    }
                }
            }
        }
    }

    func testTintPreservesTheWholeClothSilhouetteAndNeutralEmbroidery() throws {
        let source = try self.source()
        let red = try XCTUnwrap(WinterSnowmanCutout.image(from: source, part: .scarf))
        let blue = try XCTUnwrap(WinterSnowmanCutout.image(from: source, part: .scarf, tint: [0.1, 0.44, 0.91]))
        let a = try bytes(red), b = try bytes(blue)
        var changed = 0, highlights = 0
        for pixel in stride(from: 0, to: a.count, by: 4) {
            XCTAssertEqual(a[pixel + 3], b[pixel + 3])
            guard a[pixel + 3] > 0 else { continue }
            if a[pixel] != b[pixel] { changed += 1 }
            if min(a[pixel], a[pixel + 1], a[pixel + 2]) > 200 {
                highlights += 1
                XCTAssertGreaterThan(min(b[pixel], b[pixel + 1], b[pixel + 2]), 190)
            }
        }
        XCTAssertGreaterThan(changed, 1000)
        XCTAssertGreaterThan(highlights, 10)
    }
}
