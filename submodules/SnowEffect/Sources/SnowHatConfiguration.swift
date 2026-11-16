import Foundation

/// A declarative decoration, never a replacement for the Telegram profile photograph.
public struct SnowHatConfiguration: Codable, Equatable {
    public static let messagePrefix = "Telegram Snow Hat v1\n"
    public static let maximumMessageBytes = 2048

    public var formatVersion: Int = 1
    public var ownerID: Int64
    public var hatID: Int
    public var enabled: Bool
    public var scale: Double
    /// Offsets are measured in avatar widths/heights, independently of screen size.
    public var offsetX: Double
    public var offsetY: Double
    public var rotation: Double
    public var modifiedAt: Int64

    public init(ownerID: Int64, hatID: Int = 1, enabled: Bool = true, scale: Double = 1.0, offsetX: Double = 0.0, offsetY: Double = -0.4, rotation: Double = 0.0, modifiedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)) {
        self.ownerID = ownerID
        self.hatID = hatID
        self.enabled = enabled
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotation = rotation
        self.modifiedAt = modifiedAt
    }

    public var isValid: Bool {
        return self.formatVersion == 1 && self.ownerID > 0 && (1 ... 10).contains(self.hatID)
            && self.scale.isFinite && (0.35 ... 2.0).contains(self.scale)
            && self.offsetX.isFinite && (-1.0 ... 1.0).contains(self.offsetX)
            && self.offsetY.isFinite && (-1.0 ... 1.0).contains(self.offsetY)
            && self.rotation.isFinite && (-Double.pi ... Double.pi).contains(self.rotation)
            && self.modifiedAt > 0
    }

    /// The caller must show the recipient and confirm sending this ordinary visible message.
    public func messageText() -> String? {
        guard self.isValid, let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let text = Self.messagePrefix + json
        return text.utf8.count <= Self.maximumMessageBytes ? text : nil
    }
}

/// Account-isolated preferences learned only from authenticated Telegram message authors.
/// This store does not send messages. Delivery and explicit publication belong to TelegramUI.
public final class SnowHatStore: NSObject {
    public static let shared = SnowHatStore()
    public static let didChange = Notification.Name("SnowHatStoreDidChange")
    private static let keyPrefix = "SnowEffect.hats.v1."

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var accounts: [Int64: [String: SnowHatConfiguration]] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    /// Disabled entries are retained as tombstones so delayed messages cannot restore a hat.
    public func configuration(accountID: Int64, peerID: Int64) -> SnowHatConfiguration? {
        guard accountID > 0, peerID > 0 else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadAccount(accountID)[String(peerID)]
    }

    /// Private decoration for this viewer. A disabled override deliberately masks a published hat.
    public func displayConfiguration(accountID: Int64, peerID: Int64) -> SnowHatConfiguration? {
        guard accountID > 0, peerID > 0 else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        let key = "SnowEffect.hatOverrides.v1.\(accountID).\(peerID)"
        if let data = self.defaults.data(forKey: key),
           let value = try? JSONDecoder().decode(SnowHatConfiguration.self, from: data),
           value.isValid, value.ownerID == peerID {
            return value
        }
        return self.loadAccount(accountID)[String(peerID)]
    }

    /// Never enters the publication store or WinterEventTransport.
    @discardableResult
    public func saveOverride(_ configuration: SnowHatConfiguration, accountID: Int64, peerID: Int64) -> Bool {
        guard accountID > 0, peerID > 0, configuration.ownerID == peerID,
              configuration.isValid, let data = try? JSONEncoder().encode(configuration) else { return false }
        self.lock.lock()
        self.defaults.set(data, forKey: "SnowEffect.hatOverrides.v1.\(accountID).\(peerID)")
        self.lock.unlock()
        if Thread.isMainThread {
            self.notify(accountID: accountID, peerID: peerID)
        } else {
            DispatchQueue.main.async { [weak self] in self?.notify(accountID: accountID, peerID: peerID) }
        }
        return true
    }

    @discardableResult
    public func saveLocal(_ configuration: SnowHatConfiguration, accountID: Int64) -> Bool {
        guard configuration.isValid, accountID > 0, configuration.ownerID == accountID else { return false }
        return self.store(configuration, accountID: accountID, allowIdentical: true)
    }

    /// Transport must supply the real author and server timestamp, and reject forwards and
    /// non-user sources. A sender cannot assign a decoration to a different Telegram user.
    @discardableResult
    public func accept(messageText: String, authorID: Int64, accountID: Int64, messageTimestamp: Int32) -> Bool {
        guard accountID > 0, authorID > 0, messageTimestamp > 0,
              messageText.utf8.count <= SnowHatConfiguration.maximumMessageBytes,
              messageText.hasPrefix(SnowHatConfiguration.messagePrefix) else { return false }
        let json = messageText.dropFirst(SnowHatConfiguration.messagePrefix.count)
        guard let configuration = try? JSONDecoder().decode(SnowHatConfiguration.self, from: Data(json.utf8)),
              configuration.isValid, configuration.ownerID == authorID else { return false }
        // Reject future revisions that could lock out later updates. There is deliberately
        // no age limit: an explicitly confirmed message may remain queued offline for hours.
        let sentAt = Int64(messageTimestamp) * 1000
        guard configuration.modifiedAt <= sentAt + 300000 else { return false }
        return self.store(configuration, accountID: accountID, allowIdentical: false)
    }

    /// Called with the lock held; old persisted values are validated before reaching a renderer.
    private func loadAccount(_ accountID: Int64) -> [String: SnowHatConfiguration] {
        if let cached = self.accounts[accountID] { return cached }
        let decoded = self.defaults.data(forKey: Self.keyPrefix + String(accountID)).flatMap {
            try? JSONDecoder().decode([String: SnowHatConfiguration].self, from: $0)
        } ?? [:]
        let validated = decoded.filter { key, configuration in
            configuration.isValid && key == String(configuration.ownerID)
        }
        self.accounts[accountID] = validated
        return validated
    }

    private func store(_ configuration: SnowHatConfiguration, accountID: Int64, allowIdentical: Bool) -> Bool {
        self.lock.lock()
        var account = self.loadAccount(accountID)
        let peerKey = String(configuration.ownerID)
        if let current = account[peerKey], configuration.modifiedAt <= current.modifiedAt {
            self.lock.unlock()
            return allowIdentical && current == configuration
        }
        account[peerKey] = configuration
        guard let data = try? JSONEncoder().encode(account) else {
            self.lock.unlock()
            return false
        }
        self.defaults.set(data, forKey: Self.keyPrefix + String(accountID))
        self.accounts[accountID] = account
        self.lock.unlock()

        if Thread.isMainThread {
            self.notify(accountID: accountID, peerID: configuration.ownerID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.notify(accountID: accountID, peerID: configuration.ownerID)
            }
        }
        return true
    }

    private func notify(accountID: Int64, peerID: Int64) {
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["accountID": accountID, "peerID": peerID])
    }
}
