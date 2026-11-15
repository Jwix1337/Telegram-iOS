import Foundation

/// Local, device-wide appearance preferences. No account or network data is stored.
public struct SnowEffectSettings: Codable, Equatable {
    public enum Intensity: Int, Codable, CaseIterable {
        case light, medium, heavy

        var particleCount: Int {
            switch self {
            case .light: return 24
            case .medium: return 44
            case .heavy: return 68
            }
        }
    }

    public enum Speed: Double, Codable, CaseIterable {
        case slow = 0.65
        case normal = 1.0
        case fast = 1.4
    }

    public enum Size: Double, Codable, CaseIterable {
        case small = 0.75
        case normal = 1.0
        case large = 1.35
    }

    public var enabled: Bool = false
    public var seasonal: Bool = false
    public var intensity: Intensity = .medium
    public var speed: Speed = .normal
    public var size: Size = .normal

    public init() {
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, seasonal, intensity, speed, size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.seasonal = try container.decodeIfPresent(Bool.self, forKey: .seasonal) ?? false
        self.intensity = try container.decodeIfPresent(Intensity.self, forKey: .intensity) ?? .medium
        self.speed = try container.decodeIfPresent(Speed.self, forKey: .speed) ?? .normal
        self.size = try container.decodeIfPresent(Size.self, forKey: .size) ?? .normal
    }

    /// Gregorian months, in the user's time zone, regardless of their preferred calendar.
    public func isActive(at date: Date = Date(), timeZone: TimeZone = .current) -> Bool {
        guard self.enabled else {
            return false
        }
        guard self.seasonal else {
            return true
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let month = calendar.component(.month, from: date)
        return month == 12 || month == 1
    }
}

/// Read and update on the main thread, like the appearance UI that consumes it.
public final class SnowEffectPreferences: NSObject {
    public static let shared = SnowEffectPreferences()
    public static let didChange = Notification.Name("SnowEffectPreferencesDidChange")
    private static let key = "SnowEffect.settings.v1"

    private let defaults: UserDefaults
    public private(set) var settings: SnowEffectSettings

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = defaults.data(forKey: Self.key).flatMap {
            try? JSONDecoder().decode(SnowEffectSettings.self, from: $0)
        } ?? SnowEffectSettings()
        super.init()
    }

    public func update(_ transform: (inout SnowEffectSettings) -> Void) {
        precondition(Thread.isMainThread)
        var updated = self.settings
        transform(&updated)
        guard updated != self.settings, let data = try? JSONEncoder().encode(updated) else {
            return
        }
        self.defaults.set(data, forKey: Self.key)
        self.settings = updated
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
