import CoreGraphics
import Foundation

/// Bounds the work submitted to Core Animation, independently of the display refresh rate.
struct SnowEffectRenderPlan: Equatable {
    let viewport: CGSize
    let particleCount: Int
    let speed: Double
    let size: Double

    init?(settings: SnowEffectSettings, viewport: CGSize, visible: Bool, active: Bool, reduceMotion: Bool, lowPower: Bool, thermalState: ProcessInfo.ThermalState, date: Date = Date()) {
        guard visible, active, !reduceMotion, thermalState != .critical,
            viewport.width.isFinite, viewport.height.isFinite,
            viewport.width > 0.0, viewport.height > 0.0, settings.isActive(at: date) else {
            return nil
        }
        self.viewport = viewport
        let areaFactor = min(1.5, Double(viewport.width * viewport.height) / 340000.0)
        let energyFactor = lowPower || thermalState == .serious ? 0.45 : 1.0
        self.particleCount = min(96, max(8, Int(Double(settings.intensity.particleCount) * areaFactor * energyFactor)))
        self.speed = settings.speed.rawValue
        self.size = settings.size.rawValue
    }
}
