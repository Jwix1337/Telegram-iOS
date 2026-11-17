import Foundation
import CoreGraphics
import ImageIO
import XCTest
@testable import SnowEffect

/// Static CoreGraphics inspection of the real resources/shared geometry. This is not a UIKit screenshot.
final class WinterArtworkInspectionTests: XCTestCase {
    func testInspectTenStylesInBothThemesAndThreeAvatarSizes() throws {
        guard ProcessInfo.processInfo.environment["SNOW_RENDER_INSPECTION"] == "1",
              let root = ProcessInfo.processInfo.environment["SNOW_WINTER_ASSET_ROOT"] else { return }
        func load(_ path: String) throws -> CGImage {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: root).appendingPathComponent(path) as CFURL, nil))
            return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let atlas = try load("SnowHatSprite.imageset/SnowHatSprite.png")
        let body = try load("SnowmanBodyReference.imageset/snow_body.png")
        let original = try load("SnowmanReady_01_classic_red_Full.imageset/01_classic_red.png")
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 2440, height: 820, bitsPerComponent: 8, bytesPerRow: 2440 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.translateBy(x: 0, y: 820); canvas.scaleBy(x: 1, y: -1)
        func draw(_ image: CGImage, _ frame: CGRect) {
            canvas.saveGState()
            canvas.translateBy(x: frame.minX, y: frame.maxY)
            canvas.scaleBy(x: frame.width / CGFloat(image.width), y: -frame.height / CGFloat(image.height))
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            canvas.restoreGState()
        }
        let limbs = try XCTUnwrap(WinterSnowmanCutout.image(from: original, part: .arms))
        let face = try [WinterSnowmanCutout.Part.eyes, .nose, .smile, .buttons].map { try XCTUnwrap(WinterSnowmanCutout.image(from: original, part: $0)) }
        for theme in 0..<2 {
            canvas.setFillColor(CGColor(gray: theme == 0 ? 0.94 : 0.08, alpha: 1))
            canvas.fill(CGRect(x: 0, y: theme * 410, width: 2440, height: 410))
            for id in 1...10 {
                let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
                let hat = try XCTUnwrap(atlas.cropping(to: art.crop))
                let x = CGFloat((id - 1) * 244), y = CGFloat(theme * 410)
                canvas.saveGState()
                canvas.translateBy(x: x, y: y)
                canvas.saveGState()
                canvas.scaleBy(x: 244.0 / 1024, y: 244.0 / 1024)
                let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
                draw(limbs, rect); draw(body, rect)
                face.forEach { draw($0, rect) }
                let color: [CGFloat]? = id % 2 == 0 ? [0.10, 0.44, 0.91] : nil
                draw(try XCTUnwrap(WinterSnowmanCutout.image(from: original, part: .scarf, tint: color)), rect)
                let placement = try XCTUnwrap(WinterSnowmanGeometry.hat(try XCTUnwrap(WinterSnowmanHatStyle(rawValue: id)), imageSize: CGSize(width: hat.width, height: hat.height)))
                draw(hat, CGRect(x: placement.center.x - placement.size.width / 2, y: placement.center.y - placement.size.height / 2, width: placement.size.width, height: placement.size.height))
                canvas.restoreGState()
                for (offset, side) in [(CGFloat(6), CGFloat(112)), (124, 60), (194, 38)] {
                    canvas.saveGState(); canvas.translateBy(x: offset, y: 268)
                    let photo = SnowHatLayout.photoFrame(in: CGRect(x: 0, y: 0, width: side, height: side), decorated: true)
                    canvas.setFillColor(CGColor(gray: theme == 0 ? 0.65 : 0.35, alpha: 1)); canvas.fillEllipse(in: photo)
                    let placement = try XCTUnwrap(SnowHatGeometry.placement(configuration: SnowHatConfiguration(ownerID: 1, hatID: id), avatarBounds: photo, imageSize: CGSize(width: hat.width, height: hat.height)))
                    draw(hat, CGRect(x: placement.center.x - placement.size.width / 2, y: placement.center.y - placement.size.height / 2, width: placement.size.width, height: placement.size.height))
                    canvas.restoreGState()
                }
                canvas.restoreGState()
            }
        }
        let png = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(canvas.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let encoded = Array((png as Data).base64EncodedString())
        for start in stride(from: 0, to: encoded.count, by: 256) {
            let line = "SNOW_ARTWORK_PNG_" + String(start / 256) + ":" + String(encoded[start..<min(encoded.count, start + 256)]) + "\n"
            FileHandle.standardOutput.write(Data(line.utf8))
        }
    }
}
