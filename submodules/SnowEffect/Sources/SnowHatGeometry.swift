import Foundation
import CoreGraphics

public enum SnowHatLayout {
    public static let photoScale: CGFloat = 0.68
    public static func photoFrame(in allocation: CGRect, decorated: Bool) -> CGRect {
        guard decorated else { return allocation }
        let side = min(allocation.width, allocation.height) * self.photoScale
        return CGRect(x: allocation.midX - side / 2, y: allocation.maxY - side, width: side, height: side)
    }
}

/// Geometry is relative to the actual avatar square, never the atlas or a screen.
/// The alpha bounds ignore <=16/255 encoding noise; a 3px guard retains soft fur edges.
enum SnowHatGeometry {
    struct Artwork {
        let crop: CGRect
        let brim: CGPoint
        let width: CGFloat
    }
    struct Placement {
        let size: CGSize
        let center: CGPoint
    }

    static func artwork(hatID: Int) -> Artwork? {
        // Absolute alpha bounds measured from the existing 1536x1024 atlas.
        let bounds: [CGRect] = [
            CGRect(x: 11, y: 152, width: 298, height: 264),
            CGRect(x: 317, y: 118, width: 300, height: 260),
            CGRect(x: 629, y: 155, width: 279, height: 293),
            CGRect(x: 922, y: 113, width: 288, height: 306),
            CGRect(x: 1219, y: 162, width: 295, height: 218),
            CGRect(x: 15, y: 611, width: 294, height: 251),
            CGRect(x: 322, y: 599, width: 296, height: 225),
            CGRect(x: 621, y: 579, width: 282, height: 248),
            CGRect(x: 911, y: 608, width: 301, height: 213),
            CGRect(x: 1224, y: 597, width: 299, height: 283)
        ]
        // The inner brim's centre differs from the full accessory's centre (pompoms/antlers).
        let brims: [CGPoint] = [
            CGPoint(x: 0.57, y: 0.53), CGPoint(x: 0.50, y: 0.60),
            CGPoint(x: 0.50, y: 0.44), CGPoint(x: 0.44, y: 0.57),
            CGPoint(x: 0.50, y: 0.66), CGPoint(x: 0.58, y: 0.53),
            CGPoint(x: 0.48, y: 0.68), CGPoint(x: 0.50, y: 0.66),
            CGPoint(x: 0.53, y: 0.64), CGPoint(x: 0.45, y: 0.53)
        ]
        let widths: [CGFloat] = [1.20, 1.12, 1.18, 1.05, 1.12, 1.18, 1.18, 1.10, 1.14, 1.12]
        guard (1...10).contains(hatID) else { return nil }
        return Artwork(crop: bounds[hatID - 1].insetBy(dx: -3, dy: -3), brim: brims[hatID - 1], width: widths[hatID - 1])
    }

    static func placement(configuration: SnowHatConfiguration, avatarBounds: CGRect, imageSize: CGSize) -> Placement? {
        guard configuration.isValid, imageSize.width > 0, imageSize.height > 0,
              let artwork = artwork(hatID: configuration.hatID) else { return nil }
        let diameter = min(avatarBounds.width, avatarBounds.height)
        guard diameter > 0 else { return nil }
        // Resolve exactly the same normalized transform in the editor and every host.
        // A per-host fit/clamp silently changed saved scale and position on small avatars.
        let angle = CGFloat(configuration.rotation)
        let cosine = cos(angle), sine = sin(angle)
        let width = diameter * artwork.width * CGFloat(configuration.scale)
        let height = width * imageSize.height / imageSize.width
        let anchor = CGPoint(x: (artwork.brim.x - 0.5) * width, y: (artwork.brim.y - 0.5) * height)
        // -0.4 remains the v1 neutral Y; existing saved transforms need no migration.
        let center = CGPoint(x: avatarBounds.midX + CGFloat(configuration.offsetX) * diameter - (anchor.x * cosine - anchor.y * sine), y: avatarBounds.minY + diameter * 0.15 + CGFloat(configuration.offsetY + 0.4) * diameter - (anchor.x * sine + anchor.y * cosine))
        return Placement(size: CGSize(width: width, height: height), center: center)
    }
}
