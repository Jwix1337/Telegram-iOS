import Foundation

public enum SnowmanPart: String, Codable, CaseIterable, Hashable {
    case bottom, middle, head, eyes, nose, arms, scarf, hat, scarfColor, hatStyle

    public static let assembly: [SnowmanPart] = [.bottom, .middle, .head, .eyes, .nose, .arms, .scarf, .hat]
}

public struct SnowmanMutation: Codable, Equatable {
    public var part: SnowmanPart
    public var value: Int
    public var clock: Int64

    public init(part: SnowmanPart, value: Int, clock: Int64) {
        self.part = part
        self.value = value
        self.clock = clock
    }

    public var isValid: Bool {
        guard (1 ... 1_000_000_000).contains(self.clock) else { return false }
        switch self.part {
        case .scarfColor: return (0 ... 5).contains(self.value)
        case .hatStyle: return (1 ... 10).contains(self.value)
        default: return self.value == 1
        }
    }
}

/// Declarative data carried by an ordinary, explicitly confirmed Telegram message.
public struct WinterEvent: Codable, Equatable {
    public enum Kind: String, Codable {
        case hat, snowball, snowman_invite, snowman_accept, snowman_update, snowman_complete

        public var symbol: String { self == .snowball ? "❄️" : self == .hat ? "🎄" : "⛄" }

        public var label: String {
            switch self {
            case .hat: return "🎄 Шапка / Holiday hat"
            case .snowball: return "❄️ Снежок / Snowball"
            case .snowman_invite: return "⛄ Приглашение слепить снеговика / Snowman invitation"
            case .snowman_accept: return "⛄ Приглашение принято / Snowman invitation accepted"
            case .snowman_update: return "⛄ Деталь снеговика / Snowman part"
            case .snowman_complete: return "⛄ Снеговик готов / Snowman complete"
            }
        }
    }

    public var formatVersion: Int = 1
    public var eventID: String
    public var type: Kind
    public var senderID: Int64
    public var recipientID: Int64
    public var sessionID: String?
    public var createdAt: Int64
    public var hat: SnowHatConfiguration?
    public var mutation: SnowmanMutation?

    public init(type: Kind, senderID: Int64, recipientID: Int64, sessionID: String? = nil, mutation: SnowmanMutation? = nil, hat: SnowHatConfiguration? = nil, createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0), eventID: String = UUID().uuidString) {
        self.eventID = eventID
        self.type = type
        self.senderID = senderID
        self.recipientID = recipientID
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.hat = hat
        self.mutation = mutation
    }

    public var isValid: Bool {
        guard self.formatVersion == 1, UUID(uuidString: self.eventID)?.uuidString == self.eventID,
              self.senderID > 0, self.recipientID > 0, self.senderID != self.recipientID,
              self.createdAt > 0 else { return false }
        switch self.type {
        case .hat:
            return self.sessionID == nil && self.mutation == nil && self.hat?.isValid == true && self.hat?.ownerID == self.senderID
        case .snowball:
            return self.sessionID == nil && self.mutation == nil && self.hat == nil
        case .snowman_update:
            return self.sessionID != nil && self.sessionID.flatMap(UUID.init(uuidString:))?.uuidString == self.sessionID && self.hat == nil && self.mutation?.isValid == true
        default:
            return self.sessionID != nil && self.sessionID.flatMap(UUID.init(uuidString:))?.uuidString == self.sessionID && self.hat == nil && self.mutation == nil
        }
    }
}

public struct WinterSnowmanSession: Codable, Equatable {
    public struct Register: Codable, Equatable {
        public var value: Int
        public var clock: Int64
        public var authorID: Int64
        public var eventID: String
    }

    public let sessionID: String
    public let inviterID: Int64
    public let inviteeID: Int64
    public let createdAt: Int64
    public fileprivate(set) var accepted = false
    public fileprivate(set) var completed = false
    public fileprivate(set) var registers: [SnowmanPart: Register] = [:]

    public func contains(_ part: SnowmanPart) -> Bool {
        guard let index = SnowmanPart.assembly.firstIndex(of: part) else { return self.value(part) != nil }
        return SnowmanPart.assembly[...index].allSatisfy { self.value($0) != nil }
    }
    public func value(_ part: SnowmanPart) -> Int? { self.registers[part]?.value }
    public var nextClock: Int64 { min(1_000_000_000, (self.registers.values.map(\.clock).max() ?? 0) + 1) }
    public var isSolo: Bool { self.inviterID == self.inviteeID }
    public var isBuilt: Bool { SnowmanPart.assembly.allSatisfy { self.contains($0) } }

    static func serverSnapshot(id: String, inviter: Int64, invitee: Int64, createdAt: Int64,
                               accepted: Bool, completed: Bool, parts: [SnowmanPart: Int], version: Int64) -> WinterSnowmanSession {
        var result = WinterSnowmanSession(sessionID: id, inviterID: inviter, inviteeID: invitee, createdAt: createdAt)
        result.accepted = accepted; result.completed = completed
        for (part, value) in parts {
            result.registers[part] = Register(value: value, clock: version, authorID: inviter, eventID: id)
        }
        return result
    }

    fileprivate func matches(_ event: WinterEvent) -> Bool {
        return (event.senderID == self.inviterID && event.recipientID == self.inviteeID)
            || (event.senderID == self.inviteeID && event.recipientID == self.inviterID)
    }

    fileprivate mutating func merge(_ mutation: SnowmanMutation, event: WinterEvent) {
        let proposed = Register(value: mutation.value, clock: mutation.clock, authorID: event.senderID, eventID: event.eventID)
        if let current = self.registers[mutation.part] {
            let wins = proposed.clock > current.clock
                || (proposed.clock == current.clock && proposed.authorID > current.authorID)
                || (proposed.clock == current.clock && proposed.authorID == current.authorID && proposed.eventID > current.eventID)
            guard wins else { return }
        }
        self.registers[mutation.part] = proposed
    }
}

/// A server route is exclusive: failures never silently fall back to Telegram messages.
public protocol WinterServerTransport: AnyObject {
    func owns(accountID: Int64, peerID: Int64) -> Bool
    func record(_ event: WinterEvent, accountID: Int64) -> Bool
    func session(accountID: Int64, peerID: Int64) -> WinterSnowmanSession?
    func snowballs(accountID: Int64, peerID: Int64, consume: Bool) -> [WinterEvent]
}

/// One local transport boundary for hats and all winter actions. It does not send messages.
/// The Telegram bridge supplies authenticated authors and confirms every outgoing message.
public final class WinterEventTransport: NSObject {
    public static let shared = WinterEventTransport()
    public static weak var serverTransport: WinterServerTransport?
    public static let didChange = Notification.Name("WinterEventTransportDidChange")
    public static let messagePrefix = "Telegram Snow Winter v1\n"
    public static let maximumMessageBytes = 4096
    private static let storagePrefix = "SnowEffect.winter.v1."
    private static let sessionLifetime: Int64 = 7 * 24 * 60 * 60 * 1000

    private struct Seen: Codable {
        let id: String
        let time: Int64
    }

    private struct HatApplication: Codable, Equatable {
        let configuration: SnowHatConfiguration
        let messageTimestamp: Int32?
    }

    private struct AccountState: Codable {
        var seen: [Seen] = []
        var snowballs: [WinterEvent] = []
        var sessions: [String: WinterSnowmanSession] = [:]
        var deferred: [WinterEvent] = []
        var rateTimes: [String: [Int64]] = [:]
        var outgoing: [WinterEvent] = []
        var pendingHats: [String: HatApplication] = [:]
    }

    private enum Applied { case yes, deferred, rejected }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let hatStore: SnowHatStore
    private let lock = NSLock()
    private var accounts: [Int64: AccountState] = [:]

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }, hatStore: SnowHatStore = .shared) {
        self.defaults = defaults
        self.now = now
        self.hatStore = hatStore
        super.init()
    }

    public func makeEvent(type: WinterEvent.Kind, accountID: Int64, peerID: Int64, sessionID: String? = nil, mutation: SnowmanMutation? = nil, hat: SnowHatConfiguration? = nil) -> WinterEvent? {
        let id = type == .snowman_invite ? (sessionID ?? UUID().uuidString) : sessionID
        let event = WinterEvent(type: type, senderID: accountID, recipientID: peerID, sessionID: id, mutation: mutation, hat: hat, createdAt: self.milliseconds)
        return event.isValid ? event : nil
    }

    public func messageText(_ event: WinterEvent) -> String? {
        guard event.isValid, let data = try? JSONEncoder().encode(event), let json = String(data: data, encoding: .utf8) else { return nil }
        let text = Self.messagePrefix + event.type.label + "\n" + json
        return text.utf8.count <= Self.maximumMessageBytes ? text : nil
    }

    /// An ordinary visible emoji link, explicitly confirmed by its sender. The URL is
    /// app-local data, never a request to a third-party service or executable content.
    public func visibleMessage(_ event: WinterEvent) -> (text: String, url: String)? {
        guard let text = self.messageText(event) else { return nil }
        let payload = Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let url = "telegram-snow://winter/v1?payload=" + payload
        guard url.utf8.count <= 6000 else { return nil }
        return (event.type.symbol, url)
    }

    /// Decoding is not authentication: receive() must still verify the actual author,
    /// message timestamp, destination, state transitions and replay ledger.
    public func messageText(fromEventLink link: String, displayText: String? = nil) -> String? {
        guard link.utf8.count <= 6000, let url = URLComponents(string: link),
              url.scheme == "telegram-snow", url.host == "winter", url.path == "/v1",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let items = url.queryItems, items.count == 1, items[0].name == "payload",
              let payload = items[0].value, !payload.isEmpty,
              payload.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), data.count <= Self.maximumMessageBytes,
              let text = String(data: data, encoding: .utf8), text.hasPrefix(Self.messagePrefix) else { return nil }
        let body = text.dropFirst(Self.messagePrefix.count)
        guard let separator = body.firstIndex(of: "\n"),
              let event = try? JSONDecoder().decode(WinterEvent.self, from: Data(body[body.index(after: separator)...].utf8)),
              event.isValid, String(body[..<separator]) == event.type.label,
              displayText == nil || displayText == event.type.symbol else { return nil }
        return text
    }

    private func soloKey(accountID: Int64, peerID: Int64) -> String { "SnowEffect.soloSnowman.v1.\(accountID).\(peerID)" }

    /// Independent private game; never enters the shared event ledger or network outbox.
    private func readSolo(accountID: Int64, peerID: Int64) -> WinterSnowmanSession? {
        guard let data = self.defaults.data(forKey: soloKey(accountID: accountID, peerID: peerID)), data.count <= 16000,
              let session = try? JSONDecoder().decode(WinterSnowmanSession.self, from: data),
              session.isSolo, session.inviterID == accountID, session.accepted,
              UUID(uuidString: session.sessionID) != nil, session.createdAt > 0,
              session.registers.count <= 10, (!session.completed || session.isBuilt),
              session.registers.allSatisfy({ part, value in value.authorID == accountID && UUID(uuidString: value.eventID) != nil && SnowmanMutation(part: part, value: value.value, clock: value.clock).isValid }) else { return nil }
        return session
    }

    public func soloSession(accountID: Int64, peerID: Int64) -> WinterSnowmanSession? {
        guard accountID > 0, peerID > 0 else { return nil }
        self.lock.lock(); defer { self.lock.unlock() }
        return readSolo(accountID: accountID, peerID: peerID)
    }

    public func startSoloSession(accountID: Int64, peerID: Int64) -> WinterSnowmanSession? {
        guard accountID > 0, peerID > 0 else { return nil }
        self.lock.lock()
        if let current = readSolo(accountID: accountID, peerID: peerID) { self.lock.unlock(); return current }
        var session = WinterSnowmanSession(sessionID: UUID().uuidString, inviterID: accountID, inviteeID: accountID, createdAt: self.milliseconds)
        session.accepted = true
        guard let data = try? JSONEncoder().encode(session) else { self.lock.unlock(); return nil }
        self.defaults.set(data, forKey: soloKey(accountID: accountID, peerID: peerID))
        self.lock.unlock()
        self.notify(accountID: accountID, peerID: peerID)
        return session
    }

    @discardableResult public func updateSoloSession(accountID: Int64, peerID: Int64, sessionID: String, mutation: SnowmanMutation? = nil, complete: Bool = false) -> WinterSnowmanSession? {
        guard accountID > 0, peerID > 0 else { return nil }
        self.lock.lock()
        guard var session = readSolo(accountID: accountID, peerID: peerID), session.sessionID == sessionID else { self.lock.unlock(); return nil }
        if let mutation {
            guard !session.completed, mutation.isValid, mutation.clock == session.nextClock else { self.lock.unlock(); return nil }
            if SnowmanPart.assembly.contains(mutation.part) {
                guard SnowmanPart.assembly.first(where: { !session.contains($0) }) == mutation.part else { self.lock.unlock(); return nil }
            } else {
                guard session.contains(.head) else { self.lock.unlock(); return nil }
            }
            session.registers[mutation.part] = WinterSnowmanSession.Register(value: mutation.value, clock: mutation.clock, authorID: accountID, eventID: UUID().uuidString)
        }
        if complete {
            guard session.isBuilt else { self.lock.unlock(); return nil }
            session.completed = true
        }
        guard let data = try? JSONEncoder().encode(session), data.count <= 16000 else { self.lock.unlock(); return nil }
        self.defaults.set(data, forKey: soloKey(accountID: accountID, peerID: peerID))
        self.lock.unlock()
        self.notify(accountID: accountID, peerID: peerID)
        return session
    }

    /// The caller must already have confirmed a visible message to this particular recipient.
    @discardableResult
    public func recordOutgoing(_ event: WinterEvent, accountID: Int64) -> Bool {
        guard event.isValid, event.senderID == accountID, event.createdAt <= self.milliseconds + 300000,
              event.type != .snowball || event.createdAt >= self.milliseconds - 120000,
              event.hat == nil || event.hat!.modifiedAt <= self.milliseconds + 300000 else { return false }
        if let server = Self.serverTransport, server.owns(accountID: accountID, peerID: event.recipientID) {
            return server.record(event, accountID: accountID)
        }
        return self.record(event, accountID: accountID, incoming: false, messageTimestamp: nil)
    }

    @discardableResult
    public func receive(messageText: String, authorID: Int64, accountID: Int64, messageTimestamp: Int32) -> Bool {
        guard Self.serverTransport?.owns(accountID: accountID, peerID: authorID) != true else { return false }
        // Compatibility adapter: already released visible hat messages remain readable.
        if messageText.hasPrefix(SnowHatConfiguration.messagePrefix) {
            return self.hatStore.accept(messageText: messageText, authorID: authorID, accountID: accountID, messageTimestamp: messageTimestamp)
        }
        guard accountID > 0, authorID > 0, messageTimestamp > 0,
              messageText.utf8.count <= Self.maximumMessageBytes,
              messageText.hasPrefix(Self.messagePrefix) else { return false }
        let body = messageText.dropFirst(Self.messagePrefix.count)
        guard let separator = body.firstIndex(of: "\n") else { return false }
        let label = String(body[..<separator])
        let json = body[body.index(after: separator)...]
        guard let event = try? JSONDecoder().decode(WinterEvent.self, from: Data(json.utf8)), event.isValid,
              label == event.type.label, event.senderID == authorID, event.recipientID == accountID,
              event.createdAt <= Int64(messageTimestamp) * 1000 + 300000,
              event.hat == nil || event.hat!.modifiedAt <= Int64(messageTimestamp) * 1000 + 300000 else { return false }
        return self.record(event, accountID: accountID, incoming: true, messageTimestamp: messageTimestamp)
    }

    public func session(accountID: Int64, peerID: Int64) -> WinterSnowmanSession? {
        if let server = Self.serverTransport, server.owns(accountID: accountID, peerID: peerID) {
            return server.session(accountID: accountID, peerID: peerID)
        }
        guard accountID > 0, peerID > 0 else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.load(accountID)
        self.prune(&state)
        self.accounts[accountID] = state
        // Concurrent invitations select the same session on both clients, regardless of arrival order.
        return state.sessions.values.filter {
            ($0.inviterID == accountID && $0.inviteeID == peerID) || ($0.inviterID == peerID && $0.inviteeID == accountID)
        }.max {
            $0.createdAt == $1.createdAt ? $0.sessionID < $1.sessionID : $0.createdAt < $1.createdAt
        }
    }

    /// Consuming is persisted; history scrolling never replays an already seen snowball.
    public func pendingSnowballs(accountID: Int64, peerID: Int64, consume: Bool = true) -> [WinterEvent] {
        if let server = Self.serverTransport, server.owns(accountID: accountID, peerID: peerID) {
            return server.snowballs(accountID: accountID, peerID: peerID, consume: consume)
        }
        guard accountID > 0, peerID > 0 else { return [] }
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.load(accountID)
        self.prune(&state)
        let pending = state.snowballs.filter { $0.senderID == peerID && $0.recipientID == accountID }
        if consume { state.snowballs.removeAll { $0.senderID == peerID } }
        self.persist(state, accountID: accountID)
        return pending
    }

    /// These messages were explicitly confirmed before being persisted. The account's
    /// bridge enqueues them sequentially, including after an interrupted app launch.
    public func pendingOutgoing(accountID: Int64) -> [WinterEvent] {
        guard accountID > 0 else { return [] }
        self.reconcileHats(accountID: accountID)
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.load(accountID)
        self.prune(&state)
        state.outgoing.removeAll { $0.senderID != accountID }
        self.persist(state, accountID: accountID)
        return state.outgoing
    }

    public func markEnqueued(eventID: String, accountID: Int64) {
        guard accountID > 0 else { return }
        self.lock.lock()
        var state = self.load(accountID)
        let event = state.outgoing.first { $0.eventID == eventID }
        state.outgoing.removeAll { $0.eventID == eventID }
        let saved = self.persist(state, accountID: accountID)
        self.lock.unlock()
        if saved, let event { self.notify(accountID: accountID, peerID: event.recipientID) }
    }

    private var milliseconds: Int64 { Int64(self.now().timeIntervalSince1970 * 1000.0) }

    private func record(_ event: WinterEvent, accountID: Int64, incoming: Bool, messageTimestamp: Int32?) -> Bool {
        guard accountID > 0, event.createdAt >= self.milliseconds - Self.sessionLifetime else { return false }
        self.lock.lock()
        var state = self.load(accountID)
        self.prune(&state)
        if state.seen.contains(where: { $0.id == event.eventID }) {
            self.lock.unlock()
            self.reconcileHats(accountID: accountID)
            return false
        }
        guard (incoming || state.outgoing.count < 64), self.admit(event, incoming: incoming, state: &state) else {
            self.lock.unlock()
            return false
        }
        let result = self.apply(event, incoming: incoming, state: &state)
        if case .rejected = result {
            self.lock.unlock()
            return false
        }
        if case .deferred = result {
            guard incoming, state.deferred.count < 64 else {
                self.lock.unlock()
                return false
            }
            state.deferred.append(event)
        }
        state.seen.append(Seen(id: event.eventID, time: self.milliseconds))
        if !incoming { state.outgoing.append(event) }
        if let hat = event.hat {
            let key = String(hat.ownerID)
            if state.pendingHats[key] == nil || state.pendingHats[key]!.configuration.modifiedAt <= hat.modifiedAt {
                guard state.pendingHats[key] != nil || state.pendingHats.count < 64 else {
                    self.lock.unlock()
                    return false
                }
                state.pendingHats[key] = HatApplication(configuration: hat, messageTimestamp: incoming ? messageTimestamp : nil)
            }
        }
        if state.seen.count > 2048 { state.seen.removeFirst(state.seen.count - 2048) }
        self.replayDeferred(&state)
        guard self.persist(state, accountID: accountID) else {
            self.lock.unlock()
            return false
        }
        self.lock.unlock()

        self.reconcileHats(accountID: accountID)
        self.notify(accountID: accountID, peerID: incoming ? event.senderID : event.recipientID)
        return true
    }

    private func apply(_ event: WinterEvent, incoming: Bool, state: inout AccountState) -> Applied {
        if event.type == .hat { return .yes }
        if event.type == .snowball {
            if incoming, event.createdAt >= self.milliseconds - 120000 {
                state.snowballs.append(event)
                if state.snowballs.count > 20 { state.snowballs.removeFirst(state.snowballs.count - 20) }
            }
            return .yes
        }
        guard let sessionID = event.sessionID else { return .rejected }
        if event.type == .snowman_invite {
            if let current = state.sessions[sessionID] {
                return current.inviterID == event.senderID && current.inviteeID == event.recipientID && current.createdAt == event.createdAt ? .yes : .rejected
            }
            state.sessions[sessionID] = WinterSnowmanSession(sessionID: sessionID, inviterID: event.senderID, inviteeID: event.recipientID, createdAt: event.createdAt)
            if state.sessions.count > 32 {
                let oldest = state.sessions.values.min { $0.createdAt == $1.createdAt ? $0.sessionID < $1.sessionID : $0.createdAt < $1.createdAt }
                if let oldest { state.sessions.removeValue(forKey: oldest.sessionID) }
            }
            return .yes
        }
        guard var session = state.sessions[sessionID] else { return .deferred }
        guard session.matches(event), event.createdAt >= session.createdAt - 300000 else { return .rejected }
        switch event.type {
        case .snowman_accept:
            guard event.senderID == session.inviteeID else { return .rejected }
            session.accepted = true
        case .snowman_update:
            guard session.accepted else { return .deferred }
            guard let mutation = event.mutation else { return .rejected }
            session.merge(mutation, event: event)
        case .snowman_complete:
            guard session.accepted, session.isBuilt else { return .deferred }
            session.completed = true
        default:
            return .rejected
        }
        state.sessions[sessionID] = session
        return .yes
    }

    private func replayDeferred(_ state: inout AccountState) {
        // At most 64 entries and ten registers per session; never a per-frame operation.
        var changed = true
        while changed {
            changed = false
            let pending = state.deferred
            state.deferred = []
            for event in pending {
                switch self.apply(event, incoming: true, state: &state) {
                case .deferred: state.deferred.append(event)
                case .yes, .rejected: changed = true
                }
            }
        }
    }

    private func admit(_ event: WinterEvent, incoming: Bool, state: inout AccountState) -> Bool {
        let key = "\(event.senderID):\(event.recipientID):\(event.type.rawValue)"
        var times = state.rateTimes[key] ?? []
        times.removeAll { $0 < self.milliseconds - 120000 }
        let interval: Int64
        switch event.type {
        case .snowball: interval = 3000
        case .snowman_invite: interval = 30000
        case .hat, .snowman_accept, .snowman_complete: interval = incoming ? 0 : 500
        case .snowman_update: interval = incoming ? 0 : 500
        }
        guard !times.contains(where: { abs($0 - event.createdAt) < interval }) else { return false }
        if incoming, times.filter({ abs($0 - event.createdAt) < 10000 }).count >= 32 { return false }
        times.append(event.createdAt)
        state.rateTimes[key] = Array(times.suffix(64))
        if state.rateTimes.count > 512,
           let oldest = state.rateTimes.min(by: { ($0.value.max() ?? 0) < ($1.value.max() ?? 0) })?.key {
            state.rateTimes.removeValue(forKey: oldest)
        }
        return true
    }

    private func prune(_ state: inout AccountState) {
        let now = self.milliseconds
        state.snowballs.removeAll { !$0.isValid || $0.createdAt < now - 120000 }
        state.outgoing.removeAll { !$0.isValid || $0.createdAt < now - Self.sessionLifetime || ($0.type == .snowball && $0.createdAt < now - 120000) }
        state.seen.removeAll { UUID(uuidString: $0.id) == nil || $0.time < now - Self.sessionLifetime }
        state.sessions = state.sessions.filter { key, session in
            key == session.sessionID && UUID(uuidString: key)?.uuidString == key && session.inviterID > 0 && session.inviteeID > 0
                && session.inviterID != session.inviteeID && session.createdAt >= now - Self.sessionLifetime && session.createdAt <= now + 300000
                && (!session.completed || (session.accepted && session.isBuilt))
                && session.registers.count <= 10 && session.registers.allSatisfy { part, register in
                    SnowmanMutation(part: part, value: register.value, clock: register.clock).isValid
                        && (register.authorID == session.inviterID || register.authorID == session.inviteeID)
                        && UUID(uuidString: register.eventID) != nil
                }
        }
        state.deferred.removeAll { !$0.isValid || $0.createdAt < now - Self.sessionLifetime || $0.createdAt > now + 300000 }
        state.rateTimes = state.rateTimes.mapValues { $0.filter { $0 >= now - 120000 && $0 <= now + 300000 } }.filter { !$0.value.isEmpty }
    }

    private func load(_ accountID: Int64) -> AccountState {
        if let state = self.accounts[accountID] { return state }
        guard let data = self.defaults.data(forKey: Self.storagePrefix + String(accountID)), data.count <= 2_000_000,
              let state = try? JSONDecoder().decode(AccountState.self, from: data),
              state.sessions.count <= 32, state.seen.count <= 2048, state.snowballs.count <= 20, state.deferred.count <= 64,
              state.outgoing.count <= 64, state.pendingHats.count <= 64, state.rateTimes.count <= 512,
              state.rateTimes.values.allSatisfy({ $0.count <= 64 }) else { return AccountState() }
        return state
    }

    @discardableResult
    private func persist(_ state: AccountState, accountID: Int64) -> Bool {
        guard let data = try? JSONEncoder().encode(state), data.count <= 2_000_000 else { return false }
        self.defaults.set(data, forKey: Self.storagePrefix + String(accountID))
        self.accounts[accountID] = state
        return true
    }

    /// The journal closes the crash window between the common event ledger and the
    /// already-existing hat store. Reconciliation is idempotent and never holds this
    /// transport's lock while hat notifications can re-enter UI code.
    private func reconcileHats(accountID: Int64) {
        self.lock.lock()
        let applications = self.load(accountID).pendingHats
        self.lock.unlock()
        guard !applications.isEmpty else { return }
        var finished: [String: HatApplication] = [:]
        for (key, application) in applications {
            let configuration = application.configuration
            guard configuration.isValid, key == String(configuration.ownerID) else {
                finished[key] = application
                continue
            }
            if let timestamp = application.messageTimestamp, let text = configuration.messageText() {
                let _ = self.hatStore.accept(messageText: text, authorID: configuration.ownerID, accountID: accountID, messageTimestamp: timestamp)
            } else if configuration.ownerID == accountID {
                let _ = self.hatStore.saveLocal(configuration, accountID: accountID)
            }
            if let stored = self.hatStore.configuration(accountID: accountID, peerID: configuration.ownerID), stored.modifiedAt >= configuration.modifiedAt {
                finished[key] = application
            }
        }
        self.lock.lock()
        var state = self.load(accountID)
        for (key, application) in finished where state.pendingHats[key] == application {
            state.pendingHats.removeValue(forKey: key)
        }
        self.persist(state, accountID: accountID)
        self.lock.unlock()
    }

    private func notify(accountID: Int64, peerID: Int64) {
        let deliver = { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["accountID": accountID, "peerID": peerID])
        }
        if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
    }
}
