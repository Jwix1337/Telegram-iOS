import UIKit

public enum WinterMiniSnowmanLayout {
    public static func reservedHeight(available: CGFloat, width: CGFloat) -> CGFloat {
        guard available >= 220, width.isFinite, width > 0 else { return 0 }
        return min(72, max(48, width * 0.15)) + 8
    }
}

/// One static control, containing only the alpha-cropped character. No idle animation/timer.
public final class WinterMiniSnowmanView: UIButton {
    public var onOpen: (() -> Void)?
    private var visualKey = ""
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12; cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    public override init(frame: CGRect) {
        super.init(frame: frame)
        imageView?.contentMode = .scaleAspectFit
        accessibilityLabel = "Общий снеговик"
        accessibilityHint = "Открывает совместное украшение снеговика"
        addTarget(self, action: #selector(openSnowman), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { preconditionFailure("init(coder:) has not been implemented") }
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 { return false }
            ancestor = view.superview
        }
        return super.point(inside: point, with: event)
    }
    @objc private func openSnowman() { onOpen?() }

    public func update(_ session: WinterSnowmanSession?, dark: Bool) {
        guard let session, session.isBuilt, session.completed else {
            visualKey = ""; setImage(nil, for: .normal); return
        }
        let details = SnowmanPart.allCases.map { $0.rawValue + "=" + String(session.value($0) ?? -1) }.joined(separator: ",")
        let key = "snowman-v4|\(dark)|" + details
        guard key != visualKey else { return }
        visualKey = key
        if let image = Self.cache.object(forKey: key as NSString) { setImage(image, for: .normal); return }
        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            let canvas = WinterSnowmanCanvas(frame: CGRect(x: 0, y: 0, width: 512, height: 512), transparent: true)
            canvas.overrideUserInterfaceStyle = dark ? .dark : .light
            canvas.update(session: session, animated: false); canvas.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            rendered = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { canvas.layer.render(in: $0.cgContext) }
        }
        guard let source = rendered?.cgImage, let rect = Self.alphaBounds(source), let cropped = source.cropping(to: rect) else { setImage(nil, for: .normal); return }
        let result = UIImage(cgImage: cropped)
        Self.cache.setObject(result, forKey: key as NSString, cost: cropped.width * cropped.height * 4)
        setImage(result, for: .normal)
    }

    /// Sample alpha at 128px, expand one sample to retain anti-aliased accessory tips.
    /// Only 16K samples per changed visual state; never scan full-resolution PNG per frame.
    static func alphaBounds(_ image: CGImage) -> CGRect? {
        let size = 128
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        var minX = size, minY = size, maxX = -1, maxY = -1
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
            let pixels = buffer.bindMemory(to: UInt8.self)
            for y in 0 ..< size { for x in 0 ..< size where pixels[(y * size + x) * 4 + 3] > 0 {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            } }
        }
        guard maxX >= minX else { return nil }
        let x = max(0, minX - 1), y = max(0, minY - 1)
        let right = min(size, maxX + 2), bottom = min(size, maxY + 2)
        return CGRect(x: CGFloat(x) * CGFloat(image.width) / CGFloat(size), y: CGFloat(y) * CGFloat(image.height) / CGFloat(size), width: CGFloat(right - x) * CGFloat(image.width) / CGFloat(size), height: CGFloat(bottom - y) * CGFloat(image.height) / CGFloat(size)).integral
    }
}
