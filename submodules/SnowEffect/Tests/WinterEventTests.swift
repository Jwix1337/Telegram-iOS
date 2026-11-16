import Foundation
import XCTest
@testable import SnowEffect

final class WinterEventTests: XCTestCase {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1800000000)
        func advance(_ seconds: TimeInterval) { self.date.addTimeInterval(seconds) }
        var timestamp: Int32 { Int32(self.date.timeIntervalSince1970) }
    }

    private func withTransport(_ body: (WinterEventTransport, UserDefaults, Clock) throws -> Void) throws {
        let suite = "WinterEventTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        try body(WinterEventTransport(defaults: defaults, now: { clock.date }), defaults, clock)
    }

    private func event(_ transport: WinterEventTransport, _ type: WinterEvent.Kind, from: Int64 = 111, to: Int64 = 222, sessionID: String? = nil, mutation: SnowmanMutation? = nil) throws -> WinterEvent {
        return try XCTUnwrap(transport.makeEvent(type: type, accountID: from, peerID: to, sessionID: sessionID, mutation: mutation))
    }

    private func receive(_ event: WinterEvent, on transport: WinterEventTransport, timestamp: Int32, authorID: Int64? = nil, accountID: Int64? = nil) throws -> Bool {
        return transport.receive(messageText: try XCTUnwrap(transport.messageText(event)), authorID: authorID ?? event.senderID, accountID: accountID ?? event.recipientID, messageTimestamp: timestamp)
    }

    private func send(_ event: WinterEvent, through transport: WinterEventTransport, clock: Clock) throws {
        XCTAssertTrue(transport.recordOutgoing(event, accountID: event.senderID))
        XCTAssertTrue(try self.receive(event, on: transport, timestamp: clock.timestamp))
    }

    private func acceptedSession(_ transport: WinterEventTransport, clock: Clock) throws -> String {
        let invite = try self.event(transport, .snowman_invite)
        try self.send(invite, through: transport, clock: clock)
        let sessionID = try XCTUnwrap(invite.sessionID)
        clock.advance(1.0)
        let accept = try self.event(transport, .snowman_accept, from: 222, to: 111, sessionID: sessionID)
        try self.send(accept, through: transport, clock: clock)
        return sessionID
    }

    func testConcurrentInvitationsSelectSameSessionOnBothAccounts() throws {
        try self.withTransport { transport, _, clock in
            let a = try self.event(transport, .snowman_invite)
            let b = try self.event(transport, .snowman_invite, from: 222, to: 111)
            XCTAssertTrue(transport.recordOutgoing(a, accountID: 111))
            XCTAssertTrue(transport.recordOutgoing(b, accountID: 222))
            XCTAssertTrue(try self.receive(b, on: transport, timestamp: clock.timestamp))
            XCTAssertTrue(try self.receive(a, on: transport, timestamp: clock.timestamp))
            XCTAssertEqual(transport.session(accountID: 111, peerID: 222)?.sessionID,
                           transport.session(accountID: 222, peerID: 111)?.sessionID)
        }
    }

    func testNoncanonicalUUIDCannotBypassDeduplication() throws {
        try self.withTransport { transport, _, clock in
            var value = try self.event(transport, .snowball)
            value.eventID = "ABCDEFAB-1234-4321-ABCD-123456789ABC"
            XCTAssertTrue(try self.receive(value, on: transport, timestamp: clock.timestamp))
            value.eventID = value.eventID.lowercased()
            XCTAssertFalse(value.isValid)
            XCTAssertNil(transport.messageText(value))
            XCTAssertEqual(transport.pendingSnowballs(accountID: 222, peerID: 111).count, 1)
        }
    }

    func testHatApplicationJournalRecoversAfterRestart() throws {
        try self.withTransport { _, defaults, clock in
            let configuration = SnowHatConfiguration(ownerID: 111, hatID: 3, modifiedAt: Int64(clock.timestamp) * 1000)
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration))
            let state: [String: Any] = ["seen": [], "snowballs": [], "sessions": [:], "deferred": [],
                "rateTimes": [:], "outgoing": [], "pendingHats": ["111": ["configuration": encoded]]]
            defaults.set(try JSONSerialization.data(withJSONObject: state), forKey: "SnowEffect.winter.v1.111")
            let hats = SnowHatStore(defaults: defaults)
            let restored = WinterEventTransport(defaults: defaults, now: { clock.date }, hatStore: hats)
            XCTAssertTrue(restored.pendingOutgoing(accountID: 111).isEmpty)
            XCTAssertEqual(hats.configuration(accountID: 111, peerID: 111), configuration)
        }
    }

    func testServerRouteFailureCannotEnqueueTelegramFallback() throws {
        final class Route: WinterServerTransport {
            func owns(accountID: Int64, peerID: Int64) -> Bool { true }
            func record(_ event: WinterEvent, accountID: Int64) -> Bool { false }
            func session(accountID: Int64, peerID: Int64) -> WinterSnowmanSession? { nil }
            func snowballs(accountID: Int64, peerID: Int64, consume: Bool) -> [WinterEvent] { [] }
        }
        let previous = WinterEventTransport.serverTransport
        let route = Route()
        WinterEventTransport.serverTransport = route
        defer { WinterEventTransport.serverTransport = previous }
        try self.withTransport { transport, _, clock in
            let event = try self.event(transport, .snowball)
            XCTAssertFalse(transport.recordOutgoing(event, accountID: 111))
            XCTAssertTrue(transport.pendingOutgoing(accountID: 111).isEmpty)
            XCTAssertFalse(try self.receive(event, on: transport, timestamp: clock.timestamp))
        }
    }

    func testVisibleVersionedEnvelopeRejectsInvalidAndOversizedData() throws {
        try self.withTransport { transport, _, clock in
            let event = try self.event(transport, .snowball)
            let text = try XCTUnwrap(transport.messageText(event))
            XCTAssertTrue(text.hasPrefix("Telegram Snow Winter v1\n"))
            XCTAssertLessThanOrEqual(text.utf8.count, 4096)
            var invalid = event
            invalid.formatVersion = 2
            XCTAssertNil(transport.messageText(invalid))
            invalid = event
            invalid.eventID = "not-a-uuid"
            XCTAssertNil(transport.messageText(invalid))
            for text in ["{}", "Telegram Snow Winter v1\nnot JSON", String(repeating: "x", count: 4097)] {
                XCTAssertFalse(transport.receive(messageText: text, authorID: 111, accountID: 222, messageTimestamp: clock.timestamp))
            }
        }
    }

    func testAuthenticatedSenderAndRecipientCannotBeSpoofed() throws {
        try self.withTransport { transport, _, clock in
            let event = try self.event(transport, .snowball)
            XCTAssertFalse(try self.receive(event, on: transport, timestamp: clock.timestamp, authorID: 333))
            XCTAssertFalse(try self.receive(event, on: transport, timestamp: clock.timestamp, accountID: 333))
            XCTAssertFalse(transport.recordOutgoing(event, accountID: 333))
            var future = event
            future.createdAt += 300001
            XCTAssertFalse(try self.receive(future, on: transport, timestamp: clock.timestamp))
            XCTAssertTrue(transport.pendingSnowballs(accountID: 222, peerID: 111).isEmpty)
        }
    }

    func testPendingSnowballAndConsumptionSurviveRestartWithoutReplay() throws {
        try self.withTransport { transport, defaults, clock in
            let event = try self.event(transport, .snowball)
            XCTAssertTrue(try self.receive(event, on: transport, timestamp: clock.timestamp))
            XCTAssertFalse(try self.receive(event, on: transport, timestamp: clock.timestamp))
            let restarted = WinterEventTransport(defaults: defaults, now: { clock.date })
            XCTAssertEqual(restarted.pendingSnowballs(accountID: 222, peerID: 111, consume: false).map(\.eventID), [event.eventID])
            XCTAssertTrue(restarted.pendingSnowballs(accountID: 333, peerID: 111, consume: false).isEmpty)
            XCTAssertEqual(restarted.pendingSnowballs(accountID: 222, peerID: 111).count, 1)
            let again = WinterEventTransport(defaults: defaults, now: { clock.date })
            XCTAssertTrue(again.pendingSnowballs(accountID: 222, peerID: 111).isEmpty)
            XCTAssertFalse(try self.receive(event, on: again, timestamp: clock.timestamp))
        }
    }

    func testIncomingRateLimitAndSnowballExpiry() throws {
        try self.withTransport { transport, _, clock in
            let first = try self.event(transport, .snowball)
            XCTAssertTrue(try self.receive(first, on: transport, timestamp: clock.timestamp))
            clock.advance(1.0)
            let tooSoon = try self.event(transport, .snowball)
            XCTAssertFalse(try self.receive(tooSoon, on: transport, timestamp: clock.timestamp))
            clock.advance(2.1)
            let allowed = try self.event(transport, .snowball)
            XCTAssertTrue(try self.receive(allowed, on: transport, timestamp: clock.timestamp))
            XCTAssertEqual(transport.pendingSnowballs(accountID: 222, peerID: 111, consume: false).count, 2)
            clock.advance(121.0)
            XCTAssertTrue(transport.pendingSnowballs(accountID: 222, peerID: 111).isEmpty)
        }
    }

    func testOutgoingRateLimitPersistsAndRecovers() throws {
        try self.withTransport { transport, defaults, clock in
            let first = try self.event(transport, .snowball)
            XCTAssertTrue(transport.recordOutgoing(first, accountID: 111))
            clock.advance(1.0)
            let restarted = WinterEventTransport(defaults: defaults, now: { clock.date })
            let tooSoon = try self.event(restarted, .snowball)
            XCTAssertFalse(restarted.recordOutgoing(tooSoon, accountID: 111))
            clock.advance(2.1)
            let allowed = try self.event(restarted, .snowball)
            XCTAssertTrue(restarted.recordOutgoing(allowed, accountID: 111))
        }
    }

    func testConfirmedOutboxAndSessionPersistAtomicallyUntilEnqueued() throws {
        try self.withTransport { transport, defaults, clock in
            let invite = try self.event(transport, .snowman_invite)
            XCTAssertTrue(transport.recordOutgoing(invite, accountID: 111))
            XCTAssertEqual(transport.pendingOutgoing(accountID: 111).map(\.eventID), [invite.eventID])
            XCTAssertEqual(transport.session(accountID: 111, peerID: 222)?.sessionID, invite.sessionID)
            let restarted = WinterEventTransport(defaults: defaults, now: { clock.date })
            XCTAssertEqual(restarted.pendingOutgoing(accountID: 111).map(\.eventID), [invite.eventID])
            XCTAssertEqual(restarted.session(accountID: 111, peerID: 222)?.sessionID, invite.sessionID)
            XCTAssertFalse(restarted.recordOutgoing(invite, accountID: 111))
            restarted.markEnqueued(eventID: invite.eventID, accountID: 111)
            let again = WinterEventTransport(defaults: defaults, now: { clock.date })
            XCTAssertTrue(again.pendingOutgoing(accountID: 111).isEmpty)
            XCTAssertEqual(again.session(accountID: 111, peerID: 222)?.sessionID, invite.sessionID)
            XCTAssertFalse(again.recordOutgoing(invite, accountID: 111))
            let unaccepted = try self.event(again, .snowman_update, sessionID: invite.sessionID, mutation: SnowmanMutation(part: .bottom, value: 1, clock: 1))
            XCTAssertFalse(again.recordOutgoing(unaccepted, accountID: 111))
            XCTAssertTrue(again.pendingOutgoing(accountID: 111).isEmpty)
            XCTAssertFalse(try XCTUnwrap(again.session(accountID: 111, peerID: 222)).contains(.bottom))
        }
    }

    func testOutboxDoesNotSendExpiredSnowballsAfterRestart() throws {
        try self.withTransport { transport, defaults, clock in
            let event = try self.event(transport, .snowball)
            XCTAssertTrue(transport.recordOutgoing(event, accountID: 111))
            XCTAssertEqual(transport.pendingOutgoing(accountID: 111).count, 1)
            clock.advance(121.0)
            let restarted = WinterEventTransport(defaults: defaults, now: { clock.date })
            XCTAssertTrue(restarted.pendingOutgoing(accountID: 111).isEmpty)
            XCTAssertFalse(restarted.recordOutgoing(event, accountID: 111))
        }
    }

    func testOnlyInvitedParticipantCanAcceptAndMutationsAreValidated() throws {
        try self.withTransport { transport, _, clock in
            let invite = try self.event(transport, .snowman_invite)
            try self.send(invite, through: transport, clock: clock)
            let sessionID = try XCTUnwrap(invite.sessionID)
            let forgedAccept = try self.event(transport, .snowman_accept, sessionID: sessionID)
            XCTAssertFalse(try self.receive(forgedAccept, on: transport, timestamp: clock.timestamp))
            let outsider = try self.event(transport, .snowman_accept, from: 333, to: 111, sessionID: sessionID)
            XCTAssertFalse(try self.receive(outsider, on: transport, timestamp: clock.timestamp))
            XCTAssertFalse(try XCTUnwrap(transport.session(accountID: 111, peerID: 222)).accepted)
            XCTAssertNil(transport.makeEvent(type: .snowman_update, accountID: 111, peerID: 222, sessionID: sessionID, mutation: SnowmanMutation(part: .hatStyle, value: 11, clock: 1)))
            XCTAssertNil(transport.makeEvent(type: .snowman_update, accountID: 111, peerID: 222, sessionID: sessionID, mutation: SnowmanMutation(part: .bottom, value: 0, clock: 1)))
            XCTAssertNil(transport.makeEvent(type: .snowman_update, accountID: 111, peerID: 222, sessionID: sessionID, mutation: SnowmanMutation(part: .scarfColor, value: 6, clock: 1)))
        }
    }

    func testUpdateBeforeAuthenticatedAcceptIsBufferedAcrossRestart() throws {
        try self.withTransport { transport, defaults, clock in
            let invite = try self.event(transport, .snowman_invite)
            try self.send(invite, through: transport, clock: clock)
            let sessionID = try XCTUnwrap(invite.sessionID)
            clock.advance(1.0)
            let accept = try self.event(transport, .snowman_accept, from: 222, to: 111, sessionID: sessionID)
            XCTAssertTrue(transport.recordOutgoing(accept, accountID: 222))
            clock.advance(0.6)
            let update = try self.event(transport, .snowman_update, from: 222, to: 111, sessionID: sessionID, mutation: SnowmanMutation(part: .bottom, value: 1, clock: 1))
            XCTAssertTrue(transport.recordOutgoing(update, accountID: 222))
            XCTAssertTrue(try self.receive(update, on: transport, timestamp: clock.timestamp))
            XCTAssertFalse(try XCTUnwrap(transport.session(accountID: 111, peerID: 222)).contains(.bottom))
            let restarted = WinterEventTransport(defaults: defaults, now: { clock.date })
            XCTAssertTrue(try self.receive(accept, on: restarted, timestamp: clock.timestamp))
            let session = try XCTUnwrap(restarted.session(accountID: 111, peerID: 222))
            XCTAssertTrue(session.accepted)
            XCTAssertTrue(session.contains(.bottom))
        }
    }

    func testConcurrentRegistersConvergeWithOppositeDeliveryOrder() throws {
        try self.withTransport { transport, _, clock in
            let sessionID = try self.acceptedSession(transport, clock: clock)
            clock.advance(1.0)
            let a = try self.event(transport, .snowman_update, sessionID: sessionID, mutation: SnowmanMutation(part: .scarfColor, value: 1, clock: 1))
            let b = try self.event(transport, .snowman_update, from: 222, to: 111, sessionID: sessionID, mutation: SnowmanMutation(part: .scarfColor, value: 4, clock: 1))
            XCTAssertTrue(transport.recordOutgoing(a, accountID: 111))
            XCTAssertTrue(transport.recordOutgoing(b, accountID: 222))
            XCTAssertTrue(try self.receive(a, on: transport, timestamp: clock.timestamp))
            XCTAssertTrue(try self.receive(b, on: transport, timestamp: clock.timestamp))
            let stateA = try XCTUnwrap(transport.session(accountID: 111, peerID: 222))
            let stateB = try XCTUnwrap(transport.session(accountID: 222, peerID: 111))
            XCTAssertEqual(stateA.value(.scarfColor), 4)
            XCTAssertEqual(stateA.value(.scarfColor), stateB.value(.scarfColor))
            XCTAssertGreaterThan(stateA.nextClock, 1)
        }
    }

    func testCompletionWaitsForAllPartsAndReverseDeliveryConverges() throws {
        try self.withTransport { transport, _, clock in
            let sessionID = try self.acceptedSession(transport, clock: clock)
            let parts: [SnowmanPart] = [.bottom, .middle, .head, .eyes, .nose, .arms, .scarf, .hat]
            var updates: [WinterEvent] = []
            for (index, part) in parts.enumerated() {
                clock.advance(0.6)
                let update = try self.event(transport, .snowman_update, sessionID: sessionID, mutation: SnowmanMutation(part: part, value: 1, clock: Int64(index + 1)))
                XCTAssertTrue(transport.recordOutgoing(update, accountID: 111))
                updates.append(update)
            }
            // B's concurrent styling was valid before completion, but its network
            // delivery to A is delayed until after both replicas process complete.
            let delayedStyle = try self.event(transport, .snowman_update, from: 222, to: 111, sessionID: sessionID, mutation: SnowmanMutation(part: .scarfColor, value: 5, clock: 8))
            XCTAssertTrue(transport.recordOutgoing(delayedStyle, accountID: 222))
            let complete = try self.event(transport, .snowman_complete, sessionID: sessionID)
            XCTAssertTrue(transport.recordOutgoing(complete, accountID: 111))
            XCTAssertTrue(try self.receive(complete, on: transport, timestamp: clock.timestamp))
            XCTAssertFalse(try XCTUnwrap(transport.session(accountID: 222, peerID: 111)).completed)
            for update in updates.reversed() {
                XCTAssertTrue(try self.receive(update, on: transport, timestamp: clock.timestamp))
            }
            let stateA = try XCTUnwrap(transport.session(accountID: 111, peerID: 222))
            let stateB = try XCTUnwrap(transport.session(accountID: 222, peerID: 111))
            XCTAssertTrue(stateB.accepted)
            XCTAssertTrue(stateB.isBuilt)
            XCTAssertTrue(stateB.completed)
            XCTAssertTrue(parts.allSatisfy { stateA.contains($0) && stateB.contains($0) })
            XCTAssertTrue(try self.receive(delayedStyle, on: transport, timestamp: clock.timestamp))
            XCTAssertEqual(transport.session(accountID: 111, peerID: 222)?.value(.scarfColor), 5)
            XCTAssertEqual(transport.session(accountID: 111, peerID: 222)?.registers, transport.session(accountID: 222, peerID: 111)?.registers)
        }
    }
}
