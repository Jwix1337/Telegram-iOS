import Foundation
import XCTest
@testable import SnowEffect

final class WinterSoloAndLinkTests: XCTestCase {
    private func withStore(_ body: (WinterEventTransport, UserDefaults, Int32) throws -> Void) throws {
        let name = "WinterSoloTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let date = Date(timeIntervalSince1970: 1800000000)
        try body(WinterEventTransport(defaults: defaults, now: { date }), defaults, Int32(date.timeIntervalSince1970))
    }

    func testVisibleEmojiLinkRoundtripAuthenticationAndReplay() throws {
        try withStore { store, _, timestamp in
            let event = try XCTUnwrap(store.makeEvent(type: .snowball, accountID: 111, peerID: 222))
            let visible = try XCTUnwrap(store.visibleMessage(event))
            XCTAssertEqual(visible.text, "❄️")
            XCTAssertFalse(visible.text.contains("{"))
            let payload = try XCTUnwrap(store.messageText(fromEventLink: visible.url, displayText: visible.text))
            XCTAssertNil(store.messageText(fromEventLink: visible.url, displayText: "⛄"))
            XCTAssertFalse(store.receive(messageText: payload, authorID: 333, accountID: 222, messageTimestamp: timestamp))
            XCTAssertTrue(store.receive(messageText: payload, authorID: 111, accountID: 222, messageTimestamp: timestamp))
            XCTAssertFalse(store.receive(messageText: payload, authorID: 111, accountID: 222, messageTimestamp: timestamp))
            XCTAssertEqual(store.pendingSnowballs(accountID: 222, peerID: 111).count, 1)
            XCTAssertTrue(store.pendingSnowballs(accountID: 222, peerID: 111).isEmpty)
        }
    }

    func testMalformedAndExternalLinksCannotBecomeEvents() throws {
        try withStore { store, _, _ in
            let event = try XCTUnwrap(store.makeEvent(type: .snowman_invite, accountID: 111, peerID: 222))
            let link = try XCTUnwrap(store.visibleMessage(event)).url
            for bad in [link.replacingOccurrences(of: "telegram-snow:", with: "https:"), link.replacingOccurrences(of: "/v1?", with: "/v2?"), link + "#anything", link + "&extra=1", "telegram-snow://winter/v1?payload=%%%", String(repeating: "x", count: 6001)] {
                XCTAssertNil(store.messageText(fromEventLink: bad))
            }
            XCTAssertEqual(try XCTUnwrap(store.visibleMessage(event)).text, "⛄")
        }
    }

    func testSoloPersistsAndNeverCreatesSharedEvents() throws {
        try withStore { store, defaults, _ in
            let session = try XCTUnwrap(store.startSoloSession(accountID: 111, peerID: 222))
            XCTAssertTrue(session.isSolo)
            XCTAssertTrue(session.accepted)
            XCTAssertEqual(store.startSoloSession(accountID: 111, peerID: 222), session)
            XCTAssertNil(store.soloSession(accountID: 333, peerID: 222))
            XCTAssertNil(store.soloSession(accountID: 111, peerID: 333))
            XCTAssertNil(store.session(accountID: 111, peerID: 222))
            XCTAssertTrue(store.pendingOutgoing(accountID: 111).isEmpty)
            XCTAssertEqual(WinterEventTransport(defaults: defaults).soloSession(accountID: 111, peerID: 222), session)
            XCTAssertNil(store.makeEvent(type: .snowman_invite, accountID: 111, peerID: 111))
        }
    }

    func testSoloBuildOrderDuplicateActionsAndCompletion() throws {
        try withStore { store, defaults, _ in
            var session = try XCTUnwrap(store.startSoloSession(accountID: 111, peerID: 111))
            XCTAssertNil(store.updateSoloSession(accountID: 111, peerID: 111, sessionID: session.sessionID, mutation: SnowmanMutation(part: .head, value: 1, clock: 1)))
            XCTAssertNil(store.updateSoloSession(accountID: 111, peerID: 111, sessionID: session.sessionID, complete: true))
            for part in SnowmanPart.assembly {
                let mutation = SnowmanMutation(part: part, value: 1, clock: session.nextClock)
                session = try XCTUnwrap(store.updateSoloSession(accountID: 111, peerID: 111, sessionID: session.sessionID, mutation: mutation))
                XCTAssertNil(store.updateSoloSession(accountID: 111, peerID: 111, sessionID: session.sessionID, mutation: mutation))
            }
            session = try XCTUnwrap(store.updateSoloSession(accountID: 111, peerID: 111, sessionID: session.sessionID, mutation: SnowmanMutation(part: .hatStyle, value: 10, clock: session.nextClock)))
            session = try XCTUnwrap(store.updateSoloSession(accountID: 111, peerID: 111, sessionID: session.sessionID, complete: true))
            XCTAssertTrue(session.completed)
            XCTAssertEqual(session.value(.hatStyle), 10)
            XCTAssertEqual(WinterEventTransport(defaults: defaults).soloSession(accountID: 111, peerID: 111), session)
            XCTAssertTrue(store.pendingOutgoing(accountID: 111).isEmpty)
        }
    }
}
