import Foundation
import CoreGraphics
import XCTest
@testable import SnowEffect

final class SnowHatPlacementTests: XCTestCase {
    func testSavedTransformIsIdenticalInEditorProfileChatAndRow() throws {
        for id in 1...10 {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            for angle in [0.0, Double.pi / 4, -Double.pi] {
                let config = SnowHatConfiguration(ownerID: 111, hatID: id, scale: 1.7, offsetX: 0.4, offsetY: -0.8, rotation: angle)
                var reference: SnowHatGeometry.Placement?
                for side in [CGFloat(244), 100, 60, 38] {
                    let photo = SnowHatLayout.photoFrame(in: CGRect(x: 0, y: 0, width: side, height: side), decorated: true)
                    let p = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: photo, imageSize: art.crop.size))
                    XCTAssertEqual(p.size.width / p.size.height, art.crop.width / art.crop.height, accuracy: 0.000001)
                    if let reference {
                        XCTAssertEqual(p.size.width / side, reference.size.width / 244, accuracy: 0.000001)
                        XCTAssertEqual(p.center.x / side, reference.center.x / 244, accuracy: 0.000001)
                        XCTAssertEqual(p.center.y / side, reference.center.y / 244, accuracy: 0.000001)
                    } else { reference = p }
                }
            }
        }
    }

    func testRectangularAllocationsKeepThePhotoCircular() {
        let frame = SnowHatLayout.photoFrame(in: CGRect(x: 11, y: 17, width: 90, height: 130), decorated: true)
        XCTAssertEqual(frame.width, frame.height)
        XCTAssertEqual(frame.midX, 56, accuracy: 0.000001)
        XCTAssertEqual(frame.maxY, 147, accuracy: 0.000001)
    }

    func testDragAndScaleAreHonouredWithoutHostDependentClamping() throws {
        let photo = CGRect(x: 20, y: 80, width: 100, height: 100)
        for id in 1...10 {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            var c = SnowHatConfiguration(ownerID: 111, hatID: id)
            let p = try XCTUnwrap(SnowHatGeometry.placement(configuration: c, avatarBounds: photo, imageSize: art.crop.size))
            c.offsetX += 0.6; c.offsetY -= 0.5
            let moved = try XCTUnwrap(SnowHatGeometry.placement(configuration: c, avatarBounds: photo, imageSize: art.crop.size))
            XCTAssertEqual(moved.center.x - p.center.x, 60, accuracy: 0.000001)
            XCTAssertEqual(moved.center.y - p.center.y, -50, accuracy: 0.000001)
            c.scale = 2
            let enlarged = try XCTUnwrap(SnowHatGeometry.placement(configuration: c, avatarBounds: photo, imageSize: art.crop.size))
            XCTAssertEqual(enlarged.size.width, p.size.width * 2, accuracy: 0.000001)
        }
    }

    func testDefaultsFitAboveTheActualPhotoWithBrimOnItsUpperArc() throws {
        let allocation = CGRect(x: 0, y: 0, width: 100, height: 100)
        let photo = SnowHatLayout.photoFrame(in: allocation, decorated: true)
        for id in 1...10 {
            let art = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            let p = try XCTUnwrap(SnowHatGeometry.placement(configuration: SnowHatConfiguration(ownerID: 111, hatID: id), avatarBounds: photo, imageSize: art.crop.size))
            XCTAssertGreaterThanOrEqual(p.center.y - p.size.height / 2, -2)
            XCTAssertLessThan(p.center.y - p.size.height / 2, photo.minY)
            XCTAssertGreaterThanOrEqual(p.center.x - p.size.width / 2, 0)
            XCTAssertLessThanOrEqual(p.center.x + p.size.width / 2, 100)
            let brim = p.center.y + (art.brim.y - 0.5) * p.size.height
            XCTAssertEqual(brim, photo.minY + photo.height * 0.15, accuracy: 0.000001)
        }
        XCTAssertEqual(SnowHatLayout.photoFrame(in: allocation, decorated: false), allocation)
    }
}
