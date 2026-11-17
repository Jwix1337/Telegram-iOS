import Foundation
import CoreGraphics

/// Rounded pill top, separate from its interior and from neighbouring controls.
enum SnowAccumulationSurface {
    /// A 40pt microphone needs a shallow dusting, not a scaled copy of the whole input bank.
    /// Keep compact caps centred instead of magnifying one random off-centre mound.
    static func depositedHeights(_ profile: [Double], width: CGFloat) -> [Double] {
        guard width.isFinite, width > 0, profile.count > 1 else { return [] }
        let scale = min(1, Double(width) / 140)
        guard width < 80 else { return profile }
        return profile.indices.map { index in
            (profile[index] + profile[profile.count - index - 1]) * 0.5 * scale
        }
    }

    static func samples(frame: CGRect, heights: [Double], cornerRadius: CGFloat? = nil, offsetY: CGFloat = 24) -> (upper: [CGPoint], lower: [CGPoint])? {
        guard frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite,
              frame.width > 0, frame.height > 0, heights.count >= 2,
              heights.allSatisfy({ $0.isFinite }) else { return nil }
        let requested = cornerRadius ?? min(frame.width, frame.height) / 2
        guard requested.isFinite, requested >= 0 else { return nil }
        let radius = min(requested, min(frame.width, frame.height) / 2)
        let inset = min(8, max(3, radius * 0.3))
        let width = frame.width - inset * 2
        guard width > 0 else { return nil }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for index in heights.indices {
            let x = inset + width * CGFloat(index) / CGFloat(heights.count - 1)
            let distance = max(0, radius - min(x, frame.width - x))
            let arc = radius - sqrt(max(0, radius * radius - distance * distance))
            let baseline = CGPoint(x: frame.minX + x, y: frame.minY + offsetY + arc + 0.5)
            lower.append(baseline)
            upper.append(CGPoint(x: baseline.x, y: baseline.y - CGFloat(max(0, heights[index]))))
        }
        return (upper, lower)
    }
}
