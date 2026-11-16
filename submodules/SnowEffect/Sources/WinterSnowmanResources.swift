import UIKit

/// Snowman-only catalog. Reuses existing textures without reading avatar settings.
enum WinterSnowmanResources {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    static func hat(_ style: WinterSnowmanHatStyle) -> UIImage? {
        // Explicit artwork mapping, not a conversion between the two features' state IDs.
        let texture: Int
        switch style {
        case .santa: texture = 1
        case .reindeer: texture = 2
        case .cat: texture = 3
        case .snowman: texture = 4
        case .elf: texture = 5
        case .lights: texture = 6
        case .gold: texture = 7
        case .knitted: texture = 8
        case .pink: texture = 9
        case .neon: texture = 10
        }
        return SnowHatAssets.image(for: texture)
    }

    static func ready(_ preset: WinterSnowmanReadyPreset, full: Bool, traits: UITraitCollection) -> UIImage? {
        let name = "SnowmanReady_" + preset.rawValue + (full ? "_Full" : "")
        let key = (name + "@" + String(describing: traits.displayScale)) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = UIImage(named: name, in: .main, compatibleWith: traits) else { return nil }
        let cost = (image.cgImage?.width ?? 0) * (image.cgImage?.height ?? 0) * 4
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
