import UIKit
import XCTest
@testable import SnowEffect

final class SnowHatGeometryTests: XCTestCase {
    func testAllHatsAtThreeSizesPreserveAspectAndStayInsideAllocation() throws {
        for id in 1...10 {
            let artwork = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            for diameter in [CGFloat(38), 60, 100, 280] {
                for rotation in [0.0, Double.pi / 4, -Double.pi] {
                    for scale in [0.35, 1.0, 2.0] {
                        var config = SnowHatConfiguration(ownerID: 123, hatID: id, scale: scale, rotation: rotation)
                        for offset in [-1.0, 0.0, 1.0] {
                            config.offsetX = offset
                            config.offsetY = offset
                            let placement = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: CGRect(x: 7, y: 11, width: diameter, height: diameter), imageSize: artwork.crop.size))
                            XCTAssertEqual(placement.size.width / placement.size.height, artwork.crop.width / artwork.crop.height, accuracy: 0.00001)
                            let extent = CGRect(origin: CGPoint(x: -placement.size.width / 2, y: -placement.size.height / 2), size: placement.size).applying(CGAffineTransform(rotationAngle: CGFloat(rotation))).offsetBy(dx: placement.center.x, dy: placement.center.y)
                            XCTAssertGreaterThanOrEqual(extent.minX, 7 + diameter * 0.04 - 0.00001)
                            XCTAssertLessThanOrEqual(extent.maxX, 7 + diameter * 0.96 + 0.00001)
                            XCTAssertGreaterThanOrEqual(extent.minY, 11 + diameter * 0.02 - 0.00001)
                            XCTAssertLessThanOrEqual(extent.maxY, 11 + diameter * 0.68 + 0.00001)
                        }
                    }
                }
            }
        }
    }

    func testResizeDoesNotChangeNormalizedPlacement() throws {
        for id in 1...10 {
            let artwork = try XCTUnwrap(SnowHatGeometry.artwork(hatID: id))
            let config = SnowHatConfiguration(ownerID: 123, hatID: id)
            let small = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: CGRect(x: 0, y: 0, width: 38, height: 38), imageSize: artwork.crop.size))
            let large = try XCTUnwrap(SnowHatGeometry.placement(configuration: config, avatarBounds: CGRect(x: 0, y: 0, width: 280, height: 280), imageSize: artwork.crop.size))
            XCTAssertEqual(small.size.width / 38, large.size.width / 280, accuracy: 0.00001)
            XCTAssertEqual(small.center.x / 38, large.center.x / 280, accuracy: 0.00001)
            XCTAssertEqual(small.center.y / 38, large.center.y / 280, accuracy: 0.00001)
        }
    }

    func testRebindingAndLiveRemovalClearExistingLayer() {
        let check = {
            let account: Int64 = 888000111, peer: Int64 = 888000222
            defer { UserDefaults.standard.removeObject(forKey: "SnowEffect.hatOverrides.v1.\(account).\(peer)") }
            let config = SnowHatConfiguration(ownerID: peer, hatID: 2)
            XCTAssertTrue(SnowHatStore.shared.saveOverride(config, accountID: account, peerID: peer))
            let view = SnowHatOverlayView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
            view.configure(accountID: account, peerID: peer)
            XCTAssertEqual(view.layer.sublayers?.first?.isHidden, false)
            view.configure(accountID: account, peerID: peer + 1)
            XCTAssertEqual(view.layer.sublayers?.first?.isHidden, true)
            view.configure(accountID: account, peerID: peer)
            XCTAssertEqual(view.layer.sublayers?.first?.isHidden, false)
            var removed = config
            removed.enabled = false
            XCTAssertTrue(SnowHatStore.shared.saveOverride(removed, accountID: account, peerID: peer))
            XCTAssertEqual(view.layer.sublayers?.first?.isHidden, true)
            view.configure(accountID: account + 1, peerID: peer)
            XCTAssertEqual(view.layer.sublayers?.first?.isHidden, true)
            XCTAssertFalse(view.isUserInteractionEnabled)
        }
        if Thread.isMainThread { check() } else { DispatchQueue.main.sync(execute: check) }
    }
}
