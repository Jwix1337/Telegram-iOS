import Foundation
import QuartzCore
import UIKit

/// A noninteractive decoration owned by a chat controller, below window-level presentations.
/// All motion runs in Core Animation; there is no display link or per-frame Swift work.
public final class SnowEffectView: UIView {
    public var isEffectVisible: Bool = false {
        didSet { self.refresh() }
    }

    public var isDark: Bool = false {
        didSet {
            if self.isDark != oldValue {
                self.appliedPlan = nil
                self.refresh()
            }
        }
    }

    private var applicationIsActive: Bool
    private var appliedPlan: SnowEffectRenderPlan?
    private var seasonTimer: Timer?

    public override init(frame: CGRect) {
        self.applicationIsActive = UIApplication.shared.applicationState == .active
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.isAccessibilityElement = false
        self.accessibilityElementsHidden = true
        self.isOpaque = false
        self.clipsToBounds = true
        self.backgroundColor = .clear

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(self.refresh), name: SnowEffectPreferences.didChange, object: SnowEffectPreferences.shared)
        center.addObserver(self, selector: #selector(self.refresh), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(self.refresh), name: .NSProcessInfoPowerStateDidChange, object: nil)
        center.addObserver(self, selector: #selector(self.refresh), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(self.refresh), name: UIApplication.significantTimeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(self.applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(self.applicationWillResignActive), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(self.applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        self.seasonTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// The parent owns the overlay frame; this only lays out its particle layers.
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.refresh()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        self.refresh()
    }

    @objc private func applicationWillResignActive() {
        self.applicationIsActive = false
        self.refresh()
    }

    @objc private func applicationDidBecomeActive() {
        self.applicationIsActive = true
        self.refresh()
    }

    @objc private func refresh() {
        // ProcessInfo notifications are not guaranteed to arrive on the UI thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
            return
        }
        self.seasonTimer?.invalidate()
        self.seasonTimer = nil
        let settings = SnowEffectPreferences.shared.settings
        let visible = self.isEffectVisible && self.window != nil
        let plan = SnowEffectRenderPlan(
            settings: settings, viewport: self.bounds.size,
            visible: visible, active: self.applicationIsActive,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )

        // One wake-up at the next local day boundary, only on a visible seasonal screen.
        // Also handles January -> February while the app stays in the foreground.
        if visible && self.applicationIsActive && settings.enabled && settings.seasonal {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) {
                let timer = Timer(fire: nextDay, interval: 0.0, repeats: false) { [weak self] _ in
                    self?.refresh()
                }
                timer.tolerance = 1.0
                RunLoop.main.add(timer, forMode: .common)
                self.seasonTimer = timer
            }
        }

        guard plan != self.appliedPlan else {
            return
        }
        self.appliedPlan = plan
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        if let plan {
            self.populate(plan)
        }
        CATransaction.commit()
    }

    private func populate(_ plan: SnowEffectRenderPlan) {
        let color = self.isDark ? UIColor.white : UIColor(red: 0.48, green: 0.58, blue: 0.67, alpha: 1.0)
        for _ in 0 ..< plan.particleCount {
            let diameter = CGFloat.random(in: 1.5 ... 3.5) * CGFloat(plan.size)
            let particle = CALayer()
            particle.bounds = CGRect(x: 0.0, y: 0.0, width: diameter, height: diameter)
            particle.cornerRadius = diameter * 0.5
            particle.backgroundColor = color.cgColor
            particle.opacity = 0.0
            self.layer.addSublayer(particle)

            let duration = Double(plan.viewport.height + 24.0) / (Double.random(in: 35.0 ... 68.0) * plan.speed)
            let startX = CGFloat.random(in: -20.0 ... plan.viewport.width + 20.0)
            let amplitude = CGFloat.random(in: 8.0 ... 22.0)
            let drift = CGFloat.random(in: -26.0 ... 26.0)
            let phase = Double.random(in: 0.0 ... (2.0 * .pi))
            let cycles = Double.random(in: 1.5 ... 3.5)

            let horizontal = CAKeyframeAnimation(keyPath: "position.x")
            horizontal.values = (0 ... 32).map { index -> NSNumber in
                let t = Double(index) / 32.0
                return NSNumber(value: Double(startX) + Double(drift) * t + Double(amplitude) * sin(phase + t * cycles * 2.0 * .pi))
            }
            horizontal.calculationMode = .cubic
            horizontal.duration = duration

            let vertical = CABasicAnimation(keyPath: "position.y")
            vertical.fromValue = -12.0
            vertical.toValue = plan.viewport.height + 12.0
            vertical.duration = duration

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            let peak = Float.random(in: 0.3 ... 0.8)
            opacity.values = [0.0, peak, peak, 0.0]
            opacity.keyTimes = [0.0, 0.06, 0.86, 1.0]
            opacity.duration = duration

            let group = CAAnimationGroup()
            group.animations = [horizontal, vertical, opacity]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.repeatCount = .greatestFiniteMagnitude
            group.beginTime = particle.convertTime(CACurrentMediaTime(), from: nil)
            // Random progress fills the viewport immediately and desynchronizes every flake.
            group.timeOffset = Double.random(in: 0.0 ..< duration)
            particle.add(group, forKey: "snowfall")
        }
    }
}
