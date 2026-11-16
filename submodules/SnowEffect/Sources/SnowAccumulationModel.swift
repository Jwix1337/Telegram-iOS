import Foundation

/// Small, resolution-independent bank. Layout and preference changes preserve deposited snow.
struct SnowAccumulationModel {
    private(set) var coverage: Double = 0.0
    private(set) var profile: [Double]

    init(profile: [Double]? = nil) {
        // Broad overlapping mounds with a little grain, rather than a straight strip.
        let centers = (0 ..< 7).map { _ in Double.random(in: 0.0 ... 1.0) }
        self.profile = profile ?? (0 ... 40).map { index in
            let x = Double(index) / 40.0
            let mounds = centers.reduce(0.0) { result, center in
                result + exp(-pow((x - center) / 0.12, 2.0)) * 0.22
            }
            let taper = min(1.0, min(x, 1.0 - x) * 12.0)
            return min(1.0, 0.35 + mounds + Double.random(in: 0.0 ... 0.12)) * taper
        }
    }

    var isFull: Bool { self.coverage >= 1.0 }

    mutating func advance(seconds: Double, settings: SnowEffectSettings, energyFactor: Double) {
        guard seconds.isFinite, seconds > 0.0, energyFactor > 0.0 else { return }
        let rate: Double
        switch settings.intensity {
        case .light: rate = 0.012
        case .medium: rate = 0.020
        case .heavy: rate = 0.030
        }
        self.coverage = min(1.0, self.coverage + seconds * rate * settings.accumulationSpeed.rawValue * settings.speed.rawValue * energyFactor)
    }

    func heights(maximum: Double) -> [Double] {
        return self.profile.map { min(maximum, max(0.0, $0 * self.coverage * maximum)) }
    }

    mutating func clear() {
        self.coverage = 0.0
    }
}
