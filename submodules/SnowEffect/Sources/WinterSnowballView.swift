import Foundation
import QuartzCore
import UIKit

/// A bounded, noninteractive animation above a conversation. All motion runs in Core Animation.
public final class WinterSnowballView: UIView {
    private struct Random {
        var value: UInt64

        mutating func next(_ range: ClosedRange<CGFloat>) -> CGFloat {
            self.value = self.value &* 6364136223846793005 &+ 1442695040888963407
            let fraction = CGFloat(self.value >> 11) / CGFloat(UInt64(1) << 53)
            return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        }
    }

    private var particles: CALayer?
    private var cleanup: DispatchWorkItem?
    private var animationSize: CGSize = .zero
    private var incoming = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.isAccessibilityElement = false
        self.accessibilityElementsHidden = true
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            center.addObserver(self, selector: #selector(self.stop), name: name, object: nil)
        }
        for name in [SnowEffectPreferences.didChange, UIAccessibility.reduceMotionStatusDidChangeNotification,
                     .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            center.addObserver(self, selector: #selector(self.runtimeSettingsChanged), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        self.cleanup?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if self.particles != nil && self.animationSize != self.bounds.size {
            self.stop()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window == nil { self.stop() }
    }

    private func canAnimate(incoming: Bool) -> Bool {
        let settings = SnowEffectPreferences.shared.settings
        return self.window != nil && UIApplication.shared.applicationState == .active
            && self.bounds.width > 0.0 && self.bounds.height > 0.0
            && !UIAccessibility.isReduceMotionEnabled && settings.winterAnimationsEnabled
            && (incoming ? settings.winterReceiveSnowballs : settings.winterSnowballsEnabled)
            && ProcessInfo.processInfo.thermalState != .critical
    }

    @objc private func runtimeSettingsChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.runtimeSettingsChanged() }
            return
        }
        if !self.canAnimate(incoming: self.incoming) { self.stop() }
    }

    /// Call only after sending or consuming a current event. Replaying history never calls this.
    public func play(incoming: Bool, seed: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.play(incoming: incoming, seed: seed) }
            return
        }
        self.stop()
        guard self.canAnimate(incoming: incoming) else { return }
        self.incoming = incoming
        self.animationSize = self.bounds.size
        var random = Random(value: UInt64(truncatingIfNeeded: seed) ^ 0x534e4f5742414c4c)
        let width = self.bounds.width
        let height = self.bounds.height
        let left = random.next(0.0 ... 1.0) < 0.5
        let start = incoming
            ? CGPoint(x: left ? -24.0 : width + 24.0, y: height * random.next(0.12 ... 0.35))
            : CGPoint(x: width * random.next(0.72 ... 0.9), y: height * 0.72)
        let impact = CGPoint(x: width * random.next(0.25 ... 0.75), y: height * random.next(0.28 ... 0.55))
        let control = CGPoint(x: (start.x + impact.x) * 0.5 + random.next(-width * 0.18 ... width * 0.18), y: min(start.y, impact.y) - height * random.next(0.10 ... 0.24))
        let flight = Double(random.next(0.65 ... 0.76))
        let container = CALayer()
        container.frame = self.bounds
        self.layer.addSublayer(container)
        self.particles = container
        let time = container.convertTime(CACurrentMediaTime(), from: nil)

        let ball = CAGradientLayer()
        ball.bounds = CGRect(x: 0.0, y: 0.0, width: 25.0, height: 25.0)
        ball.position = impact
        ball.cornerRadius = 12.5
        ball.type = .radial
        ball.colors = [UIColor.white.cgColor, UIColor(red: 0.73, green: 0.84, blue: 0.92, alpha: 1.0).cgColor]
        ball.startPoint = CGPoint(x: 0.3, y: 0.25)
        ball.endPoint = CGPoint(x: 1.0, y: 1.0)
        ball.shadowColor = UIColor.black.cgColor
        ball.shadowOpacity = 0.14
        ball.shadowRadius = 2.0
        ball.shadowOffset = CGSize(width: 0.0, height: 2.0)
        ball.shadowPath = UIBezierPath(ovalIn: ball.bounds).cgPath
        ball.opacity = 0.0
        container.addSublayer(ball)
        for point in [CGPoint(x: 6.0, y: 8.0), CGPoint(x: 15.0, y: 17.0)] {
            let grain = CALayer()
            grain.frame = CGRect(origin: point, size: CGSize(width: 3.0, height: 2.0))
            grain.cornerRadius = 1.0
            grain.backgroundColor = UIColor(white: 1.0, alpha: 0.75).cgColor
            ball.addSublayer(grain)
        }
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: impact, controlPoint: control)
        let movement = CAKeyframeAnimation(keyPath: "position")
        movement.path = path.cgPath
        movement.calculationMode = .paced
        movement.duration = flight
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0.0
        rotation.toValue = random.next(-4.0 ... 4.0)
        rotation.duration = flight
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.0, 1.0, 1.0, 0.0]
        opacity.keyTimes = [0.0, 0.04, 0.98, 1.0]
        opacity.duration = flight
        let throwAnimation = CAAnimationGroup()
        throwAnimation.animations = [movement, rotation, opacity]
        throwAnimation.duration = flight
        throwAnimation.beginTime = time
        throwAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        ball.add(throwAnimation, forKey: "throw")

        let process = ProcessInfo.processInfo
        let budget = process.isLowPowerModeEnabled || process.thermalState == .serious ? 18 : 42
        for _ in 0 ..< budget {
            let particle = CALayer()
            let diameter = random.next(2.0 ... 5.0)
            particle.bounds = CGRect(x: 0.0, y: 0.0, width: diameter, height: diameter)
            particle.position = impact
            particle.cornerRadius = diameter * 0.5
            particle.backgroundColor = UIColor.white.cgColor
            particle.opacity = 0.0
            container.addSublayer(particle)
            let dx = random.next(-88.0 ... 88.0)
            let dy = random.next(-68.0 ... 44.0)
            let duration = Double(random.next(0.38 ... 0.55))
            let scatter = CAKeyframeAnimation(keyPath: "position")
            scatter.values = [NSValue(cgPoint: impact), NSValue(cgPoint: CGPoint(x: impact.x + dx * 0.5, y: impact.y + dy * 0.6)), NSValue(cgPoint: CGPoint(x: impact.x + dx, y: impact.y + dy + 55.0))]
            scatter.keyTimes = [0.0, 0.4, 1.0]
            scatter.calculationMode = .cubic
            scatter.duration = duration
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.9, 0.9, 0.0]
            fade.keyTimes = [0.0, 0.22, 1.0]
            fade.duration = duration
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.2
            shrink.duration = duration
            let group = CAAnimationGroup()
            group.animations = [scatter, fade, shrink]
            group.duration = duration
            group.beginTime = time + flight
            particle.add(group, forKey: "impact")
        }
        // Jolt only this snow layer, never the conversation, keyboard or controls.
        let jolt = CAKeyframeAnimation(keyPath: "transform.translation.x")
        jolt.values = [0.0, -2.0, 2.0, -1.0, 0.0]
        jolt.keyTimes = [0.0, 0.2, 0.45, 0.7, 1.0]
        jolt.duration = 0.2
        jolt.beginTime = time + flight
        container.add(jolt, forKey: "snowJolt")
        let cleanup = DispatchWorkItem { [weak self] in self?.stop() }
        self.cleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + flight + 0.6, execute: cleanup)
    }

    @objc public func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        self.cleanup?.cancel()
        self.cleanup = nil
        self.particles?.removeFromSuperlayer()
        self.particles = nil
    }
}
