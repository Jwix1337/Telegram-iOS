import Foundation
import UIKit

/// Original reference artwork, without the example avatar circles, in the app's asset catalog.
public enum SnowHatAssets {
    private static let cache: NSCache<NSNumber, UIImage> = {
        let cache = NSCache<NSNumber, UIImage>()
        cache.countLimit = 10
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    private static let sheet = UIImage(named: "SnowHatSprite", in: .main, compatibleWith: nil)?.cgImage

    public static func image(for hatID: Int) -> UIImage? {
        guard (1 ... 10).contains(hatID) else { return nil }
        let key = NSNumber(value: hatID)
        if let cached = self.cache.object(forKey: key) { return cached }
        guard let sheet else { return nil }
        // Each rectangle includes the complete pompom/antlers and transparent edge padding.
        // The supplied collection's reading order is part of format v1, shared by all clients.
        guard let artwork = SnowHatGeometry.artwork(hatID: hatID) else { return nil }
        let region = artwork.crop
        let scaleX = CGFloat(sheet.width) / 1536.0
        let scaleY = CGFloat(sheet.height) / 1024.0
        let crop = CGRect(x: region.minX * scaleX, y: region.minY * scaleY, width: region.width * scaleX, height: region.height * scaleY).integral
        guard let cgImage = sheet.cropping(to: crop) else { return nil }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        self.cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}

/// A single noninteractive overlay. Its layer also works in layer-backed AvatarNodes.
/// Peer photos remain untouched; size and normalized transforms are resolved at presentation time.
public final class SnowHatOverlayView: UIView {
    public var avatarFrame: CGRect? { didSet { self.setNeedsLayout() } }
    public var confinementBounds: CGRect? { didSet { self.setNeedsLayout() } }
    public var onConfigurationChanged: ((Bool) -> Void)?
    public var hasDecoration: Bool { self.configuration != nil }
    private let imageLayer = CALayer()
    private var accountID: Int64?
    private var peerID: Int64?
    private var configuration: SnowHatConfiguration?
    private var showingPreview = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = false
        self.accessibilityElementsHidden = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.clipsToBounds = false
        self.imageLayer.contentsGravity = .resizeAspect
        self.layer.addSublayer(self.imageLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(self.preferencesChanged(_:)), name: SnowHatStore.didChange, object: SnowHatStore.shared)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func configure(accountID: Int64?, peerID: Int64?) {
        guard self.showingPreview || self.accountID != accountID || self.peerID != peerID else { return }
        self.showingPreview = false
        self.accountID = accountID
        self.peerID = peerID
        self.reload()
    }

    /// Editor drafts never alter the published/shared store until the user chooses Save.
    public func preview(_ configuration: SnowHatConfiguration?) {
        self.showingPreview = true
        self.apply(configuration)
    }

    @objc private func preferencesChanged(_ notification: Notification) {
        guard !self.showingPreview,
              let accountID = self.accountID, let peerID = self.peerID,
              (notification.userInfo?["accountID"] as? Int64) == accountID,
              (notification.userInfo?["peerID"] as? Int64) == peerID else { return }
        self.reload()
    }

    private func reload() {
        guard let accountID = self.accountID, let peerID = self.peerID else {
            self.apply(nil)
            return
        }
        self.apply(SnowHatStore.shared.displayConfiguration(accountID: accountID, peerID: peerID))
    }

    private func apply(_ configuration: SnowHatConfiguration?) {
        let valid = configuration.flatMap { $0.isValid && $0.enabled ? $0 : nil }
        guard self.configuration != valid else { return }
        self.configuration = valid
        self.onConfigurationChanged?(valid != nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.imageLayer.contents = valid.flatMap { SnowHatAssets.image(for: $0.hatID)?.cgImage }
        self.imageLayer.isHidden = valid == nil
        CATransaction.commit()
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration = self.configuration,
              let image = SnowHatAssets.image(for: configuration.hatID), image.size.width > 0.0 else { return }
        guard let placement = SnowHatGeometry.placement(configuration: configuration, avatarBounds: self.avatarFrame ?? self.bounds, imageSize: image.size, confinement: self.confinementBounds) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.imageLayer.bounds = CGRect(origin: .zero, size: placement.size)
        self.imageLayer.position = placement.center
        self.imageLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(configuration.rotation)))
        CATransaction.commit()
    }
}
