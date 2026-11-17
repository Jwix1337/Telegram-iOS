import UIKit

/// Snowman-only catalog. Reuses existing textures without reading avatar settings.
enum WinterSnowmanResources {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    static var bareBody: UIImage? {
        // Exactly the unadorned, three-ball illustration; no later stage is treated as a layer.
        UIImage(named: "SnowmanBodyReference", in: .main, compatibleWith: nil)
    }

    static func accessory(_ part: WinterSnowmanCutout.Part, color: Int = 0) -> UIImage? {
        let key = ("snowman-material-v1-" + part.rawValue + "-" + String(color)) as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = ready(.classicRed, full: true, traits: UITraitCollection(userInterfaceStyle: .light))?.cgImage else { return nil }
        let colors: [[CGFloat]] = [[0.89, 0.07, 0.13], [0.10, 0.44, 0.91], [0.12, 0.65, 0.36], [0.57, 0.26, 0.79], [0.95, 0.46, 0.10], [0.93, 0.30, 0.58]]
        let tint = part == .scarf && (1..<colors.count).contains(color) ? colors[color] : nil
        guard let sprite = WinterSnowmanCutout.image(from: source, part: part, tint: tint) else { return nil }
        let image = UIImage(cgImage: sprite)
        cache.setObject(image, forKey: key, cost: sprite.bytesPerRow * sprite.height)
        return image
    }

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
