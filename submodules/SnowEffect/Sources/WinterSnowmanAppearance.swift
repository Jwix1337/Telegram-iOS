import Foundation

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
