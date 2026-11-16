import Foundation
import XCTest
@testable import SnowEffect

final class SnowHatTests: XCTestCase {
    private let messageTimestamp: Int32 = 1800000000

    private func configuration(ownerID: Int64 = 222, hatID: Int = 1, revision: Int64 = 0) -> SnowHatConfiguration {
        return SnowHatConfiguration(ownerID: ownerID, hatID: hatID, modifiedAt: Int64(self.messageTimestamp) * 1000 + revision)
    }

    private func withStore(_ body: (SnowHatStore, UserDefaults) throws -> Void) throws {
        let suite = "SnowHatTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SnowHatStore(defaults: defaults), defaults)
    }

    func testAllTenHatsRoundTripNormalizedGeometry() throws {
        for hat in 1 ... 10 {
            var configuration = self.configuration(hatID: hat)
            configuration.scale = 1.5
            configuration.offsetX = -0.25
            configuration.offsetY = 0.5
            configuration.rotation = Double.pi * 0.5
            let encoded = try JSONEncoder().encode(configuration)
            XCTAssertEqual(try JSONDecoder().decode(SnowHatConfiguration.self, from: encoded), configuration)
            XCTAssertTrue(try XCTUnwrap(configuration.messageText()).hasPrefix(SnowHatConfiguration.messagePrefix))
        }
    }

    func testInvalidFieldsCannotBeExported() {
        var invalid: [SnowHatConfiguration] = []
        var configuration = self.configuration()
        configuration.formatVersion = 2; invalid.append(configuration)
        configuration = self.configuration(ownerID: 0); invalid.append(configuration)
        configuration = self.configuration(hatID: 0); invalid.append(configuration)
        configuration = self.configuration(hatID: 11); invalid.append(configuration)
        for scale in [0.34, 2.01, .nan, .infinity] {
            configuration = self.configuration(); configuration.scale = scale; invalid.append(configuration)
        }
        configuration = self.configuration(); configuration.offsetX = -1.01; invalid.append(configuration)
        configuration = self.configuration(); configuration.offsetY = .nan; invalid.append(configuration)
        configuration = self.configuration(); configuration.rotation = Double.pi + 0.01; invalid.append(configuration)
        configuration = self.configuration(); configuration.modifiedAt = 0; invalid.append(configuration)
        for value in invalid {
            XCTAssertFalse(value.isValid)
            XCTAssertNil(value.messageText())
        }
    }

    func testSpoofedOwnerMalformedAndOversizedMessagesAreRejected() throws {
        try self.withStore { store, _ in
            let text = try XCTUnwrap(self.configuration(ownerID: 222).messageText())
            XCTAssertFalse(store.accept(messageText: text, authorID: 333, accountID: 111, messageTimestamp: self.messageTimestamp))
            for invalid in ["{}", SnowHatConfiguration.messagePrefix + "{}", SnowHatConfiguration.messagePrefix + "not JSON", String(repeating: "x", count: 2049)] {
                XCTAssertFalse(store.accept(messageText: invalid, authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            }
            XCTAssertNil(store.configuration(accountID: 111, peerID: 222))
        }
    }

    func testUntrustedDecodedGeometryAndVersionCannotBypassExportValidation() throws {
        try self.withStore { store, _ in
            var invalid: [SnowHatConfiguration] = []
            var configuration = self.configuration()
            configuration.formatVersion = 2; invalid.append(configuration)
            configuration = self.configuration(hatID: 11); invalid.append(configuration)
            configuration = self.configuration(); configuration.scale = 3.0; invalid.append(configuration)
            configuration = self.configuration(); configuration.rotation = 100.0; invalid.append(configuration)
            for value in invalid {
                let json = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
                XCTAssertFalse(store.accept(messageText: SnowHatConfiguration.messagePrefix + json, authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            }
            XCTAssertNil(store.configuration(accountID: 111, peerID: 222))
        }
    }

    func testForgedFuturePublicationTimeIsRejected() throws {
        try self.withStore { store, _ in
            for revision in [300001, 3600000] as [Int64] {
                let text = try XCTUnwrap(self.configuration(revision: revision).messageText())
                XCTAssertFalse(store.accept(messageText: text, authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            }
            let valid = try XCTUnwrap(self.configuration(revision: 300000).messageText())
            XCTAssertTrue(store.accept(messageText: valid, authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
        }
    }

    func testOfflineQueuedPublicationIsAcceptedWithoutOverridingNewerChanges() throws {
        try self.withStore { store, _ in
            let queued = self.configuration(revision: -86400000)
            let text = try XCTUnwrap(queued.messageText())
            XCTAssertTrue(store.accept(messageText: text, authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            XCTAssertEqual(store.configuration(accountID: 111, peerID: 222), queued)
            let newer = self.configuration(hatID: 5)
            XCTAssertTrue(store.accept(messageText: try XCTUnwrap(newer.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            XCTAssertFalse(store.accept(messageText: text, authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            XCTAssertEqual(store.configuration(accountID: 111, peerID: 222), newer)
        }
    }

    func testNewerUpdatesAndDisabledTombstoneSurviveRestartWithoutReplay() throws {
        try self.withStore { store, defaults in
            let initial = self.configuration()
            XCTAssertTrue(store.accept(messageText: try XCTUnwrap(initial.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            var updated = self.configuration(hatID: 8, revision: 1000)
            XCTAssertTrue(store.accept(messageText: try XCTUnwrap(updated.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            updated.enabled = false
            updated.modifiedAt += 1000
            XCTAssertTrue(store.accept(messageText: try XCTUnwrap(updated.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            let restored = SnowHatStore(defaults: defaults)
            XCTAssertEqual(restored.configuration(accountID: 111, peerID: 222), updated)
            XCTAssertFalse(restored.accept(messageText: try XCTUnwrap(initial.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            XCTAssertFalse(restored.accept(messageText: try XCTUnwrap(updated.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            XCTAssertFalse(try XCTUnwrap(restored.configuration(accountID: 111, peerID: 222)).enabled)
        }
    }

    func testAccountsRemainIsolatedAndLocalSaveCannotChangeAnotherOwner() throws {
        try self.withStore { store, defaults in
            let local = self.configuration(ownerID: 111, hatID: 3)
            XCTAssertTrue(store.saveLocal(local, accountID: 111))
            XCTAssertTrue(store.saveLocal(local, accountID: 111))
            XCTAssertFalse(store.saveLocal(local, accountID: 333))
            let remote = self.configuration(ownerID: 222, hatID: 9)
            XCTAssertTrue(store.accept(messageText: try XCTUnwrap(remote.messageText()), authorID: 222, accountID: 111, messageTimestamp: self.messageTimestamp))
            let restored = SnowHatStore(defaults: defaults)
            XCTAssertEqual(restored.configuration(accountID: 111, peerID: 111), local)
            XCTAssertEqual(restored.configuration(accountID: 111, peerID: 222), remote)
            XCTAssertNil(restored.configuration(accountID: 333, peerID: 111))
            XCTAssertNil(restored.configuration(accountID: 333, peerID: 222))
        }
    }
}
