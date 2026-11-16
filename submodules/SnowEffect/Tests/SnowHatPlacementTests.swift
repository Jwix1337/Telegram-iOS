import Foundation
import CoreGraphics
import XCTest
@testable import SnowEffect

final class SnowHatPlacementTests: XCTestCase {
    func testTenHatsKeepAspectAndStayInReservedCrownAtEverySize() throws {
        for id in 1...10 {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            for diameter in [CGFloat(38), 60, 100, 280] {
                let allocation = CGRect(x: 7, y: 11, width: diameter, height: diameter)
                let photo = SnowHatLayout.photoFrame(in: allocation, decorated: true)
                let crown = SnowHatLayout.crownBounds(in: allocation)
                for rotation in [0.0, Double.pi / 4, -Double.pi] {
                    for scale in [0.35, 1.0, 2.0] {
                        for offset in [-1.0, 0.0, 1.0] {
                            let config = SnowHatConfiguration(ownerID: 111, hatID: id, scale: scale, offsetX: offset, offsetY: offset, rotation: rotation)
                            let p = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: photo, imageSize: art.crop.size, confinement: crown))
                            XCTAssertEqual(p.size.width / p.size.height, art.crop.width / art.crop.height, accuracy: 0.000001)
                            let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height).applying(CGAffineTransform(rotationAngle: CGFloat(rotation))).offsetBy(dx: p.center.x, dy: p.center.y)
                            XCTAssertGreaterThanOrEqual(rect.minX, crown.minX - 0.000001)
                            XCTAssertGreaterThanOrEqual(rect.minY, crown.minY - 0.000001)
                            XCTAssertLessThanOrEqual(rect.maxX, crown.maxX + 0.000001)
                            XCTAssertLessThanOrEqual(rect.maxY, crown.maxY + 0.000001)
                        }
                    }
                }
            }
        }
    }

    func testDefaultHatsExtendAbovePhotoInsteadOfCoveringItsCentre() throws {
        let allocation = CGRect(x: 0, y: 0, width: 100, height: 100)
        let photo = SnowHatLayout.photoFrame(in: allocation, decorated: true)
        for id in 1...10 {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            let p = try XCTUnwrap(SnowHatGeometry.placement(configuration: SnowHatConfiguration(ownerID: 111, hatID: id), avatarBounds: photo, imageSize: art.crop.size, confinement: SnowHatLayout.crownBounds(in: allocation)))
            XCTAssertLessThan(p.center.y - p.size.height / 2, photo.minY - 10)
            let brim = p.center.y + (art.brim.y - 0.5) * p.size.height
            XCTAssertLessThan(brim, photo.minY + photo.height * 0.25)
        }
        XCTAssertEqual(SnowHatLayout.photoFrame(in: allocation, decorated: false), allocation)
    }

    func testPreviewHasRoomAboveOriginalPhotoAndResizesProportionally() throws {
        for id in 1...10 {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            let config = SnowHatConfiguration(ownerID: 111, hatID: id)
            let small = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: CGRect(x: 0, y: 0, width: 38, height: 38), imageSize: art.crop.size))
            let large = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: CGRect(x: 0, y: 0, width: 280, height: 280), imageSize: art.crop.size))
            XCTAssertLessThan(small.center.y - small.size.height / 2, 0)
            XCTAssertEqual(small.center.y / 38, large.center.y / 280, accuracy: 0.000001)
            XCTAssertEqual(small.size.width / 38, large.size.width / 280, accuracy: 0.000001)
        }
    }
}
