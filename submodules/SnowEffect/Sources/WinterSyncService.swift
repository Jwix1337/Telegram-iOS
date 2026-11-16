import Foundation
import Security
import UIKit

/// No provisioning/admin secret is ever requested or stored by the client.
private enum WinterSyncKeychain {
    static func read(_ account: Int64) -> WinterSyncCredentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.snoweffect.WinterSync", kSecAttrAccount as String: String(account),
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = try? JSONDecoder().decode(WinterSyncCredentials.self, from: data) else { return nil }
        return try? WinterSyncCredentials(endpoint: value.endpoint, deviceID: value.deviceID, token: value.token)
    }
    static func forget(_ account: Int64) -> Bool {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.snoweffect.WinterSync", kSecAttrAccount as String: String(account)] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    static func write(_ value: WinterSyncCredentials, account: Int64) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.snoweffect.WinterSync", kSecAttrAccount as String: String(account)]
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw WinterSyncError.invalidData }
        } else if status != errSecSuccess { throw WinterSyncError.invalidData }
    }
}

struct WinterSyncBinding: Codable {
    let peerID: Int64
    let deviceID: String
    let pairID: String
}
private struct WinterSyncPending: Codable {
    let peerID: Int64
    let body: WinterSyncRequest
    let createdAt: Double
    var blocked: Bool = false
}
private struct WinterSyncCache: Codable {
    var endpoint: String = ""
    var deviceID: String = ""
    var bindings: [WinterSyncBinding] = []
    var serverOnlyPeers: Set<Int64> = []
    var cursor: Int64 = 0
    var lastSnowballAt: Double = 0
    var snapshots: [String: WinterSyncSnapshot] = [:]
    var snowballs: [WinterEvent] = []
    var outgoing: [WinterSyncPending] = []
    var seenSnowballs: [String] = []
}

/// Retained per Telegram account, only active in the foreground. Mapping is consented locally,
/// never inferred from an unverified device UUID or sent to the service as a Telegram identity.
public final class WinterSyncHub: WinterServerTransport {
    public static let shared = WinterSyncHub()
    private var services: [Int64: WinterSyncService] = [:]
    private static func key(_ account: Int64) -> String { "SnowEffect.server.v1.\(account)" }
    fileprivate static func cache(_ account: Int64) -> WinterSyncCache {
        guard let data = UserDefaults.standard.data(forKey: key(account)), data.count <= 4_000_000,
              let cache = try? JSONDecoder().decode(WinterSyncCache.self, from: data),
              cache.bindings.count <= 32, cache.outgoing.count <= 64, cache.snowballs.count <= 20 else { return WinterSyncCache() }
        return cache
    }
    fileprivate static func save(_ cache: WinterSyncCache, account: Int64) -> Bool {
        guard let data = try? JSONEncoder().encode(cache), data.count <= 4_000_000 else { return false }
        UserDefaults.standard.set(data, forKey: key(account)); return true
    }
    fileprivate func service(_ account: Int64) -> WinterSyncService {
        precondition(Thread.isMainThread)
        if let service = services[account] { return service }
        let service = WinterSyncService(account: account)
        services[account] = service
        return service
    }
    public static func needsConnection(accountID: Int64) -> Bool {
        let settings = SnowEffectPreferences.shared.settings
        return settings.winterSnowballsEnabled || settings.winterReceiveSnowballs || settings.winterSnowmanEnabled
            || SnowHatStore.shared.configuration(accountID: accountID, peerID: accountID)?.enabled == true
            || cache(accountID).outgoing.contains { $0.body.type == .hat }
    }
    public func start(accountID: Int64) {
        WinterEventTransport.serverTransport = self
        guard Self.needsConnection(accountID: accountID) else { stop(accountID: accountID); return }
        service(accountID).start()
    }
    public func stop(accountID: Int64) { services.removeValue(forKey: accountID)?.stop() }
    public func owns(accountID: Int64, peerID: Int64) -> Bool {
        // Can also be called on Telegram's incoming-message queue.
        let cache = Self.cache(accountID)
        if cache.endpoint.isEmpty && UserDefaults.standard.bool(forKey: "SnowEffect.server.enabled.\(accountID)") { return true }
        return cache.serverOnlyPeers.contains(peerID) || cache.bindings.contains { $0.peerID == peerID }
    }
    public func record(_ event: WinterEvent, accountID: Int64) -> Bool {
        guard event.isValid, event.senderID == accountID else { return false }
        return service(accountID).enqueue(event)
    }
    public func session(accountID: Int64, peerID: Int64) -> WinterSnowmanSession? { service(accountID).session(peer: peerID) }
    public func snowballs(accountID: Int64, peerID: Int64, consume: Bool) -> [WinterEvent] { service(accountID).snowballs(peer: peerID, consume: consume) }

    @MainActor func configure(_ credentials: WinterSyncCredentials, account: Int64) async throws {
        let existing = Self.cache(account)
        var registrations = UserDefaults.standard.dictionary(forKey: "SnowEffect.server.deviceOwners") as? [String: String] ?? [:]
        let registration = credentials.endpoint.absoluteString + "|" + credentials.deviceID
        guard registrations[registration] == nil || registrations[registration] == String(account) else { throw WinterSyncError.invalidData }
        guard existing.bindings.isEmpty || (existing.endpoint == credentials.endpoint.absoluteString && existing.deviceID == credentials.deviceID) else { throw WinterSyncError.invalidData }
        let client = WinterSyncClient(credentials); defer { client.stop() }
        guard try await client.identity() == credentials.deviceID else { throw WinterSyncError.invalidData }
        try Task.checkCancellation()
        registrations = UserDefaults.standard.dictionary(forKey: "SnowEffect.server.deviceOwners") as? [String: String] ?? [:]
        guard registrations[registration] == nil || registrations[registration] == String(account) else { throw WinterSyncError.invalidData }
        try WinterSyncKeychain.write(credentials, account: account)
        UserDefaults.standard.set(true, forKey: "SnowEffect.server.enabled.\(account)")
        registrations[registration] = String(account)
        UserDefaults.standard.set(registrations, forKey: "SnowEffect.server.deviceOwners")
        let service = self.service(account)
        service.stop()
        service.cache.endpoint = credentials.endpoint.absoluteString; service.cache.deviceID = credentials.deviceID
        guard Self.save(service.cache, account: account) else { throw WinterSyncError.invalidData }
        service.start()
    }
    func credentials(_ account: Int64) throws -> WinterSyncCredentials {
        guard let credentials = WinterSyncKeychain.read(account) else { throw WinterSyncError.invalidData }
        return credentials
    }
    func bind(_ pair: WinterSyncPair, account: Int64, peer: Int64) throws {
        let service = self.service(account)
        guard account > 0, peer > 0, account != peer,
              let other = pair.other(service.cache.deviceID), pair.active,
              service.cache.bindings.count < 32,
              !service.cache.bindings.contains(where: { $0.pairID == pair.id || ($0.peerID == peer && service.cache.snapshots[$0.pairID] != nil) }),
              !WinterEventTransport.shared.pendingOutgoing(accountID: account).contains(where: { $0.recipientID == peer }) else { throw WinterSyncError.invalidData }
        service.cache.bindings.removeAll { $0.peerID == peer }
        service.cache.serverOnlyPeers.insert(peer)
        service.cache.cursor = 0 // replay newly bound pair; snowballs have a separate durable dedupe ledger
        service.cache.bindings.append(WinterSyncBinding(peerID: peer, deviceID: other, pairID: pair.id))
        guard Self.save(service.cache, account: account) else { service.cache.bindings.removeLast(); throw WinterSyncError.invalidData }
        service.restart()
    }
    @MainActor func revoke(account: Int64, peer: Int64) async throws {
        let service = self.service(account)
        guard let binding = service.cache.bindings.first(where: { $0.peerID == peer }) else { return }
        let client = WinterSyncClient(try credentials(account)); defer { client.stop() }
        try await client.revoke(binding.pairID)
        // Keep a local tombstone route: no stale Telegram outbox/hat may reactivate sharing.
        service.cache.outgoing.removeAll { $0.peerID == peer }
        service.cache.snapshots.removeValue(forKey: binding.pairID)
        service.cache.serverOnlyPeers.insert(peer)
        service.cache.bindings.removeAll { $0.peerID == peer }
        service.cache.snowballs.removeAll { $0.senderID == peer }
        service.hideHat(peer)
        _ = Self.save(service.cache, account: account)
        service.status = "Sharing revoked. No automatic Telegram fallback."
        service.notify(peer)
    }
    func forget(account: Int64) throws {
        let service = self.service(account)
        service.stop()
        guard WinterSyncKeychain.forget(account) else { throw WinterSyncError.invalidData }
        var registrations = UserDefaults.standard.dictionary(forKey: "SnowEffect.server.deviceOwners") as? [String: String] ?? [:]
        registrations = registrations.filter { $0.value != String(account) }
        UserDefaults.standard.set(registrations, forKey: "SnowEffect.server.deviceOwners")
        service.cache.outgoing.removeAll()
        service.cache.snapshots.removeAll()
        service.cache.bindings.forEach { service.hideHat($0.peerID); service.cache.serverOnlyPeers.insert($0.peerID) }
        service.cache.bindings.removeAll()
        service.cache.snowballs.removeAll()
        _ = Self.save(service.cache, account: account)
        service.status = "Credentials removed; server routes remain paused."
    }
    func status(_ account: Int64) -> String { service(account).status }
}

private final class WinterSyncService {
    let account: Int64
    var cache: WinterSyncCache
    var status = "Winter Sync: not connected"
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var client: WinterSyncClient?
    private var generation = UUID()
    private var activePairs = Set<String>()
    init(account: Int64) { self.account = account; cache = WinterSyncHub.cache(account) }
    func notify(_ peer: Int64) {
        NotificationCenter.default.post(name: WinterEventTransport.didChange, object: WinterEventTransport.shared, userInfo: ["accountID": account, "peerID": peer])
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        client?.stop(); client = nil
    }
    func restart() { stop(); start() }
    func start() {
        guard task == nil, WinterSyncHub.needsConnection(accountID: account), UIApplication.shared.applicationState == .active,
              let credentials = WinterSyncKeychain.read(account) else { return }
        let client = WinterSyncClient(credentials); self.client = client
        let generation = self.generation
        task = Task { @MainActor [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                do {
                    try await self.synchronize(client)
                    guard !Task.isCancelled, self.generation == generation else { return }
                    let socket = try await client.socket(after: self.cache.cursor)
                    self.socket = socket; self.status = self.cache.outgoing.contains(where: { $0.blocked }) ? "Winter Sync: action conflict, explicit retry required" : "Winter Sync: connected"; delay = 1
                    var refreshAt = Date().timeIntervalSince1970 + 30
                    while !Task.isCancelled {
                        guard WinterSyncHub.needsConnection(accountID: self.account) else { self.stop(); return }
                        let message = try await socket.receive()
                        guard self.generation == generation else { return }
                        let data: Data
                        switch message {
                        case let .data(value): data = value
                        case let .string(value): data = Data(value.utf8)
                        @unknown default: throw WinterSyncError.invalidData
                        }
                        try self.apply(JSONDecoder().decode(WinterSyncBatch.self, from: data))
                        if Date().timeIntervalSince1970 >= refreshAt {
                            try await self.synchronize(client)
                            refreshAt = Date().timeIntervalSince1970 + 30
                        }
                        try await self.flush(client)
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    self.socket?.cancel(with: .goingAway, reason: nil); self.socket = nil
                    self.status = "Winter Sync unavailable; Telegram fallback is disabled."
                    // Authentication failure is terminal until credentials are explicitly updated.
                    if case WinterSyncError.http(401) = error {
                        _ = WinterSyncKeychain.forget(self.account); client.stop()
                        self.status = "Winter Sync key rejected/revoked. Reconfigure credentials."
                        return
                    }
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    delay = min(60, delay * 2)
                }
            }
        }
    }
    @MainActor private func synchronize(_ client: WinterSyncClient) async throws {
        let pairs = try await client.pairs()
        try Task.checkCancellation()
        guard pairs.count <= 32 else { throw WinterSyncError.invalidData }
        activePairs.removeAll()
        for binding in cache.bindings {
            guard let pair = pairs.first(where: { $0.id == binding.pairID }), pair.active,
                  pair.other(cache.deviceID) == binding.deviceID else {
                cache.snapshots.removeValue(forKey: binding.pairID)
                cache.outgoing.removeAll { $0.peerID == binding.peerID }
                hideHat(binding.peerID)
                _ = WinterSyncHub.save(cache, account: account)
                notify(binding.peerID)
                continue
            }
            activePairs.insert(binding.pairID)
            let snapshot = try await client.snapshot(binding.pairID)
            try Task.checkCancellation()
            try applySnapshot(snapshot, binding: binding)
        }
        while !Task.isCancelled {
            let batch = try await client.events(after: cache.cursor)
            try Task.checkCancellation()
            try apply(batch)
            if batch.events.count < 100 { break }
        }
        try await flush(client)
    }
    private func applySnapshot(_ snapshot: WinterSyncSnapshot, binding: WinterSyncBinding, commit: Bool = true) throws {
        guard snapshot.version == 1, snapshot.cursor >= 0, snapshot.hats.count <= 2, snapshot.sessions.count <= 32,
              snapshot.sessions.allSatisfy({ $0.valid && ($0.creator_id == cache.deviceID || $0.creator_id == binding.deviceID) }),
              snapshot.hats.keys.allSatisfy({ $0 == cache.deviceID || $0 == binding.deviceID }),
              snapshot.hats.values.allSatisfy({ $0.configuration(owner: 1, timestamp: 1) != nil }) else { throw WinterSyncError.invalidData }
        if let old = cache.snapshots[binding.pairID], old.cursor > snapshot.cursor { return }
        cache.snapshots[binding.pairID] = snapshot
        guard commit else { return }
        guard WinterSyncHub.save(cache, account: account) else { throw WinterSyncError.invalidData }
        reconcileHats(snapshot, binding: binding)
        notify(binding.peerID)
    }
    private func reconcileHats(_ snapshot: WinterSyncSnapshot, binding: WinterSyncBinding) {
        for (device, hat) in snapshot.hats {
            let owner = device == cache.deviceID ? account : binding.peerID
            if let current = SnowHatStore.shared.configuration(accountID: account, peerID: owner), WinterSyncHat(current) == hat { continue }
            let previous = SnowHatStore.shared.configuration(accountID: account, peerID: owner)?.modifiedAt ?? 0
            guard let configuration = hat.configuration(owner: owner, timestamp: max(Int64(Date().timeIntervalSince1970 * 1000), previous < Int64.max ? previous + 1 : previous)) else { continue }
            if owner == account { _ = SnowHatStore.shared.saveLocal(configuration, accountID: account) }
            else if let text = configuration.messageText() {
                _ = SnowHatStore.shared.accept(messageText: text, authorID: owner, accountID: account, messageTimestamp: Int32(Date().timeIntervalSince1970))
            }
        }
    }
    private func apply(_ batch: WinterSyncBatch) throws {
        guard batch.events.count <= 100 else { throw WinterSyncError.invalidData }
        let previous = cache
        var committed = false
        defer { if !committed { cache = previous } }
        var previousCursor: Int64 = -1
        for envelope in batch.events {
            guard envelope.cursor > previousCursor else { throw WinterSyncError.invalidData }
            previousCursor = envelope.cursor
            guard envelope.cursor > cache.cursor else { continue }
            guard envelope.version == 1, envelope.event.valid, envelope.cursor > 0,
                  envelope.created_at.isFinite, envelope.created_at > 0, envelope.created_at < 4_000_000_000, envelope.created_at <= Date().timeIntervalSince1970 + 300 else { throw WinterSyncError.invalidData }
            if let binding = cache.bindings.first(where: { $0.pairID == envelope.event.pair_id }), activePairs.contains(binding.pairID) {
                guard envelope.sender_id == cache.deviceID || envelope.sender_id == binding.deviceID else { throw WinterSyncError.invalidData }
                let old = cache.snapshots[binding.pairID]
                if envelope.cursor > (old?.cursor ?? 0) {
                    var hats = old?.hats ?? [:]; var sessions = old?.sessions ?? []
                    if let hat = envelope.event.hat { hats[envelope.sender_id] = hat }
                    if let session = envelope.state {
                        sessions.removeAll { $0.session_id == session.session_id }; sessions.append(session)
                    }
                    try applySnapshot(WinterSyncSnapshot(version: 1, cursor: envelope.cursor, hats: hats, sessions: sessions), binding: binding, commit: false)
                }
                if envelope.event.type == .snowball, envelope.sender_id == binding.deviceID,
                   !cache.seenSnowballs.contains(envelope.event.event_id),
                   Date().timeIntervalSince1970 - envelope.created_at < 120 {
                    let event = WinterEvent(type: .snowball, senderID: binding.peerID, recipientID: account,
                        createdAt: Int64(envelope.created_at * 1000), eventID: envelope.event.event_id.uppercased())
                    cache.seenSnowballs.append(envelope.event.event_id)
                    cache.seenSnowballs = Array(cache.seenSnowballs.suffix(4096))
                    cache.snowballs.append(event)
                    cache.snowballs = Array(cache.snowballs.suffix(20))
                }
            }
            cache.cursor = envelope.cursor
        }
        guard WinterSyncHub.save(cache, account: account) else { throw WinterSyncError.invalidData }
        committed = true
        for binding in cache.bindings {
            if let snapshot = cache.snapshots[binding.pairID] { reconcileHats(snapshot, binding: binding) }
            notify(binding.peerID)
        }
    }
    func enqueue(_ event: WinterEvent) -> Bool {
        guard let binding = cache.bindings.first(where: { $0.peerID == event.recipientID }),
              cache.snapshots[binding.pairID] != nil, cache.outgoing.count < 64 else { return false }
        cache.outgoing.removeAll { $0.blocked && $0.peerID == binding.peerID && $0.body.session_id == event.sessionID?.lowercased() && $0.body.type == event.type }
        if event.type == .snowball && Date().timeIntervalSince1970 - cache.lastSnowballAt < 3 { return false }
        if event.type == .snowball && cache.outgoing.contains(where: { $0.body.type == .snowball && Date().timeIntervalSince1970 - $0.createdAt < 3 }) { return false }
        if let id = event.sessionID, cache.outgoing.contains(where: { $0.body.session_id == id.lowercased() }) { return false }
        let expected: Int64?
        if event.type == .snowman_invite { expected = 0 }
        else if let id = event.sessionID {
            guard let session = cache.snapshots[binding.pairID]?.sessions.first(where: { $0.session_id == id.lowercased() }) else { return false }
            expected = session.version
        } else { expected = nil }
        let oldSnowballTime = cache.lastSnowballAt
        if event.type == .snowball { cache.lastSnowballAt = Date().timeIntervalSince1970 }
        cache.outgoing.append(WinterSyncPending(peerID: binding.peerID, body: WinterSyncRequest(event, pair: binding.pairID, expected: expected), createdAt: Date().timeIntervalSince1970))
        guard WinterSyncHub.save(cache, account: account) else { cache.outgoing.removeLast(); cache.lastSnowballAt = oldSnowballTime; return false }
        // Wake the single foreground worker; never start a parallel publisher.
        socket?.cancel(with: .goingAway, reason: nil)
        start()
        return true
    }
    @MainActor private func flush(_ client: WinterSyncClient) async throws {
        while let pending = cache.outgoing.first(where: { !$0.blocked }) {
            if pending.body.type == .snowball && Date().timeIntervalSince1970 - pending.createdAt > 120 {
                cache.outgoing.removeAll { $0.body.event_id == pending.body.event_id }; _ = WinterSyncHub.save(cache, account: account); continue
            }
            do {
                let response = try await client.publish(pending.body)
                try Task.checkCancellation()
                guard response.event.event_id == pending.body.event_id, response.event.pair_id == pending.body.pair_id,
                      response.sender_id == cache.deviceID, response.version == 1 else { throw WinterSyncError.invalidData }
                // A POST response can leap over unseen events. Never advance the replay cursor here.
                if let binding = cache.bindings.first(where: { $0.pairID == pending.body.pair_id }) {
                    let snapshot = try await client.snapshot(binding.pairID)
                    try Task.checkCancellation()
                    try applySnapshot(snapshot, binding: binding)
                }
                cache.outgoing.removeAll { $0.body.event_id == pending.body.event_id }
                guard WinterSyncHub.save(cache, account: account) else { throw WinterSyncError.invalidData }
            } catch WinterSyncError.http(let code) where [403, 404, 409, 422, 507].contains(code) {
                if let index = cache.outgoing.firstIndex(where: { $0.body.event_id == pending.body.event_id }) { cache.outgoing[index].blocked = true }
                _ = WinterSyncHub.save(cache, account: account)
                if let binding = cache.bindings.first(where: { $0.pairID == pending.body.pair_id }), code == 409 {
                    let snapshot = try await client.snapshot(binding.pairID)
                    try Task.checkCancellation()
                    try applySnapshot(snapshot, binding: binding)
                }
                status = "Winter Sync conflict/access error. Refresh and explicitly retry; nothing sent to Telegram."
                notify(pending.peerID)
            }
        }
    }
    func session(peer: Int64) -> WinterSnowmanSession? {
        guard let binding = cache.bindings.first(where: { $0.peerID == peer }),
              let session = cache.snapshots[binding.pairID]?.sessions.max(by: { ($0.created_at, $0.session_id) < ($1.created_at, $1.session_id) }), session.valid else { return nil }
        let ownInvites = session.creator_id == cache.deviceID
        let parts = Dictionary(uniqueKeysWithValues: session.parts.compactMap { key, value in SnowmanPart(rawValue: key).map { ($0, value) } })
        return WinterSnowmanSession.serverSnapshot(id: session.session_id.uppercased(), inviter: ownInvites ? account : peer,
            invitee: ownInvites ? peer : account, createdAt: Int64(session.created_at * 1000),
            accepted: session.accepted, completed: session.completed, parts: parts, version: session.version)
    }
    func hideHat(_ peer: Int64) {
        guard var configuration = SnowHatStore.shared.configuration(accountID: account, peerID: peer), configuration.enabled else { return }
        configuration.enabled = false
        configuration.modifiedAt = max(Int64(Date().timeIntervalSince1970 * 1000), configuration.modifiedAt < Int64.max ? configuration.modifiedAt + 1 : configuration.modifiedAt)
        if let text = configuration.messageText() {
            _ = SnowHatStore.shared.accept(messageText: text, authorID: peer, accountID: account, messageTimestamp: Int32(Date().timeIntervalSince1970))
        }
    }
    func snowballs(peer: Int64, consume: Bool) -> [WinterEvent] {
        let pending = cache.snowballs.filter { $0.senderID == peer && Date().timeIntervalSince1970 * 1000 - Double($0.createdAt) < 120000 }
        if consume { cache.snowballs.removeAll { $0.senderID == peer }; _ = WinterSyncHub.save(cache, account: account) }
        return pending
    }
}
