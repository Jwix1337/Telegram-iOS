import UIKit
import XCTest
@testable import SnowEffect

final class SnowHatGeometryTests: XCTestCase {
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
