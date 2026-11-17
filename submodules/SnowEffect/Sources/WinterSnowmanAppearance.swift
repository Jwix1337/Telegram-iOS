import Foundation
import CoreGraphics

/// Snowman session IDs, frozen independently of avatar SnowHatConfiguration.hatID.
/// Texture artwork is currently shared; user preferences/state are never shared.
enum WinterSnowmanHatStyle: Int, CaseIterable {
    case santa = 1, reindeer, cat, snowman, elf, lights, gold, knitted, pink, neon
}

/// Full images are only an optimization for an exact represented accessory combination.
/// Blue-with-lights is not a plain blue hat; neon is not a black top hat.
enum WinterSnowmanReadyPreset: String, CaseIterable {
    case classicRed = "01_classic_red"
    case santaBlueScarf = "05_santa_blue_scarf"

    static func matching(_ session: WinterSnowmanSession) -> WinterSnowmanReadyPreset? {
        guard session.completed, session.isBuilt else { return nil }
        guard SnowmanPart.assembly.dropLast().allSatisfy({ session.contains($0) }) else { return nil }
        let color = session.value(.scarfColor) ?? 0
        guard color == 0 || color == 1 else { return nil }
        guard WinterSnowmanHatStyle(rawValue: session.value(.hatStyle) ?? 1) == .santa else { return nil }
        return color == 0 ? .classicRed : .santaBlueScarf
    }
}

/// Independent snowman anchors, measured on the unchanged 512px bare-body reference.
/// Only the three-ball state can show the whole body; earlier construction uses individual shapes.
enum WinterSnowmanGeometry {
    static let bottom = CGRect(x: 268, y: 610, width: 476, height: 354)
    static let middle = CGRect(x: 314, y: 420, width: 382, height: 260)
    static let head = CGRect(x: 352, y: 238, width: 306, height: 226)

    static func hat(_ style: WinterSnowmanHatStyle, imageSize: CGSize) -> (size: CGSize, center: CGPoint)? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        // Geometry belongs to the snowman's head, never an avatar's editor configuration.
        let brim: CGPoint
        let width: CGFloat
        switch style {
        case .santa: brim = CGPoint(x: 0.57, y: 0.53); width = 1.20
        case .reindeer: brim = CGPoint(x: 0.50, y: 0.60); width = 1.12
        case .cat: brim = CGPoint(x: 0.50, y: 0.44); width = 1.18
        case .snowman: brim = CGPoint(x: 0.44, y: 0.57); width = 1.05
        case .elf: brim = CGPoint(x: 0.50, y: 0.66); width = 1.12
        case .lights: brim = CGPoint(x: 0.58, y: 0.53); width = 1.18
        case .gold: brim = CGPoint(x: 0.48, y: 0.68); width = 1.18
        case .knitted: brim = CGPoint(x: 0.50, y: 0.66); width = 1.10
        case .pink: brim = CGPoint(x: 0.53, y: 0.64); width = 1.14
        case .neon: brim = CGPoint(x: 0.45, y: 0.53); width = 1.12
        }
        let size = CGSize(width: head.width * width, height: head.width * width * imageSize.height / imageSize.width)
        return (size, CGPoint(x: head.midX - (brim.x - 0.5) * size.width, y: head.minY + head.height * 0.12 - (brim.y - 0.5) * size.height))
    }
}
