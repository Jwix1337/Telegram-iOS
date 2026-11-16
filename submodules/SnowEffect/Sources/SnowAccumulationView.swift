import Foundation
import QuartzCore
import UIKit

/// One shape above the real composer background; only the visible snow accepts touches.
/// Growth uses a low-frequency timer, while all interpolation and debris run in Core Animation.
public final class SnowMoldTicket {
    public private(set) var pending = true
    private let finish: (Bool) -> Void
    init(finish: @escaping (Bool) -> Void) { self.finish = finish }
    public func resolve(commit: Bool) { guard pending else { return }; pending = false; finish(commit) }
    deinit { if pending { finish(false) } }
}

public final class SnowAccumulationView: UIView, UIGestureRecognizerDelegate {
    public var isEffectVisible: Bool = false {
        didSet { if oldValue != self.isEffectVisible { self.refresh() } }
    }

    private let bank = CAShapeLayer()
    private let debris = CALayer()
    private var model = SnowAccumulationModel()
    private var growthTimer: Timer?
    private var seasonTimer: Timer?
    private var lastGrowthTime: CFTimeInterval?
    private var applicationIsActive = UIApplication.shared.applicationState == .active
    private var running = false
    private var clearingUntil: CFTimeInterval = 0.0
    private var cleanupWork: DispatchWorkItem?
    private var drawnSize: CGSize = .zero
    private var drawnMaximum: Double = 0.0
    public var onMold: ((SnowMoldTicket) -> Void)? { didSet { mold.isEnabled = onMold != nil && running } }
    private var moldStart = CGPoint.zero
    private let hint = UILabel()
    private lazy var mold = UILongPressGestureRecognizer(target: self, action: #selector(self.molded(_:)))
    private lazy var swipe = UIPanGestureRecognizer(target: self, action: #selector(self.swiped(_:)))

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.clipsToBounds = false
        self.isAccessibilityElement = false
        self.accessibilityElementsHidden = true
        self.bank.fillColor = UIColor(white: 1.0, alpha: 0.94).cgColor
        self.bank.shadowColor = UIColor(white: 0.35, alpha: 1.0).cgColor
        self.bank.shadowOpacity = 0.12
        self.bank.shadowRadius = 1.0
        self.bank.shadowOffset = CGSize(width: 0.0, height: -0.5)
        self.layer.addSublayer(self.bank)
        self.layer.addSublayer(self.debris)
        self.swipe.delegate = self
        self.swipe.maximumNumberOfTouches = 1
        self.swipe.cancelsTouchesInView = false
        self.addGestureRecognizer(self.swipe)
        mold.minimumPressDuration = 0.45; mold.allowableMovement = 12; mold.delegate = self
        mold.cancelsTouchesInView = false
        addGestureRecognizer(mold)
        swipe.require(toFail: mold)
        hint.font = .systemFont(ofSize: 12); hint.textColor = .white
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.7); hint.textAlignment = .center
        hint.layer.cornerRadius = 8; hint.clipsToBounds = true; hint.isHidden = true
        hint.isUserInteractionEnabled = false; addSubview(hint)

        let center = NotificationCenter.default
        for name in [SnowEffectPreferences.didChange, UIAccessibility.reduceMotionStatusDidChangeNotification,
                     .NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification,
                     UIApplication.significantTimeChangeNotification] {
            center.addObserver(self, selector: #selector(self.refresh), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(self.resignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(self.resignActive), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(self.becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        self.growthTimer?.invalidate()
        self.seasonTimer?.invalidate()
        self.cleanupWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.refresh()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        self.refresh()
    }

    @objc private func resignActive() {
        self.applicationIsActive = false
        self.refresh()
    }

    @objc private func becomeActive() {
        self.applicationIsActive = true
        self.refresh()
    }

    @objc private func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        let settings = SnowEffectPreferences.shared.settings
        let process = ProcessInfo.processInfo
        let visible = self.isEffectVisible && self.window != nil && self.applicationIsActive
        self.running = visible && settings.isActive() && settings.accumulationEnabled
            && !UIAccessibility.isReduceMotionEnabled && process.thermalState != .critical
            && self.bounds.width > 0.0 && self.bounds.height > 0.0
        self.bank.isHidden = !self.running
        self.swipe.isEnabled = self.running && settings.swipeToClear
        self.mold.isEnabled = self.running && self.onMold != nil
        if !self.running {
            self.growthTimer?.invalidate()
            self.growthTimer = nil
            self.lastGrowthTime = nil
            self.bank.removeAllAnimations()
            self.removeDebris()
        } else {
            if self.drawnSize != self.bounds.size || self.drawnMaximum != settings.maximumSnowHeight.rawValue {
                self.draw(animated: false)
            }
            if !self.model.isFull && self.growthTimer == nil {
                self.lastGrowthTime = CACurrentMediaTime()
                let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.grow() }
                timer.tolerance = 0.2
                RunLoop.main.add(timer, forMode: .common)
                self.growthTimer = timer
            }
        }

        self.seasonTimer?.invalidate()
        self.seasonTimer = nil
        if visible && settings.enabled && settings.seasonal {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) {
                let timer = Timer(fire: nextDay, interval: 0.0, repeats: false) { [weak self] _ in self?.refresh() }
                timer.tolerance = 1.0
                RunLoop.main.add(timer, forMode: .common)
                self.seasonTimer = timer
            }
        }
    }

    private func grow() {
        guard self.running else { return }
        let now = CACurrentMediaTime()
        let elapsed = min(2.0, max(0.0, now - (self.lastGrowthTime ?? now)))
        self.lastGrowthTime = now
        guard now >= self.clearingUntil else { return }
        let process = ProcessInfo.processInfo
        let energy = process.isLowPowerModeEnabled || process.thermalState == .serious ? 0.45 : 1.0
        self.model.advance(seconds: elapsed, settings: SnowEffectPreferences.shared.settings, energyFactor: energy)
        self.draw(animated: true)
        if self.model.isFull {
            self.growthTimer?.invalidate()
            self.growthTimer = nil
        }
    }

    private func draw(animated: Bool) {
        let maximum = SnowEffectPreferences.shared.settings.maximumSnowHeight.rawValue
        let heights = self.model.heights(maximum: maximum)
        let baseline = self.bounds.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.0, y: baseline))
        let points = heights.enumerated().map { index, height in
            CGPoint(x: self.bounds.width * CGFloat(index) / CGFloat(heights.count - 1), y: baseline - CGFloat(height))
        }
        // Each control point is within the height cap; quadratic segments cannot overshoot it.
        if let first = points.first {
            path.addLine(to: first)
            for index in 1 ..< points.count {
                let previous = points[index - 1]
                let current = points[index]
                path.addQuadCurve(to: CGPoint(x: (previous.x + current.x) * 0.5, y: (previous.y + current.y) * 0.5), controlPoint: previous)
            }
            if let last = points.last { path.addLine(to: last) }
        }
        path.addLine(to: CGPoint(x: self.bounds.width, y: baseline))
        path.close()
        let oldPath = self.bank.presentation()?.path ?? self.bank.path
        let oldShadowPath = self.bank.presentation()?.shadowPath ?? self.bank.shadowPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.bank.path = path.cgPath
        self.bank.shadowPath = path.cgPath
        CATransaction.commit()
        if animated, let oldPath {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = oldPath
            animation.toValue = path.cgPath
            animation.duration = 1.0
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            self.bank.add(animation, forKey: "growth")
            let shadow = CABasicAnimation(keyPath: "shadowPath")
            shadow.fromValue = oldShadowPath
            shadow.toValue = path.cgPath
            shadow.duration = animation.duration
            shadow.timingFunction = animation.timingFunction
            self.bank.add(shadow, forKey: "shadowGrowth")
        } else {
            self.bank.removeAnimation(forKey: "growth")
            self.bank.removeAnimation(forKey: "shadowGrowth")
        }
        self.drawnSize = self.bounds.size
        self.drawnMaximum = maximum
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard self.running, (SnowEffectPreferences.shared.settings.swipeToClear || onMold != nil),
              self.bounds.contains(point),
              let path = self.bank.presentation()?.path ?? self.bank.path else { return false }
        // The chat forwards hits outside the composer's bounds. Respect hidden/fading
        // ancestors even on that direct path, so dismissed panels cannot capture a swipe.
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 || view.layer.presentation()?.opacity == 0.0 {
                return false
            }
            ancestor = view.superview
        }
        return path.contains(point) || (onMold != nil && point.y >= bounds.height - 4 && point.y < bounds.height)
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === mold {
            let point = gestureRecognizer.location(in: self)
            return onMold != nil && point.x >= 12 && point.x <= bounds.width - 12
        }
        guard gestureRecognizer === self.swipe else { return true }
        // UIKit already hit-tested the touch on the bank. At recognition the finger
        // may have travelled outside this narrow shape; that must still clear it.
        return self.running && self.model.coverage > 0.04
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer !== mold && otherGestureRecognizer !== mold
    }

    @objc private func molded(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began: moldStart = gesture.location(in: self)
        case .ended:
            let end = gesture.location(in: self)
            guard hypot(end.x - moldStart.x, end.y - moldStart.y) >= 12 else { return }
            guard let id = model.reserveBall() else {
                hint.text = "Ещё немного снега…"
                hint.frame = CGRect(x: max(0, bounds.midX - 90), y: -30, width: 180, height: 26)
                hint.isHidden = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.hint.isHidden = true }
                return
            }
            draw(animated: false)
            let ticket = SnowMoldTicket { [weak self] commit in
                guard let self else { return }
                self.model.finishBall(id, commit: commit)
                self.draw(animated: false); self.refresh()
            }
            onMold?(ticket)
        default: break // recognizer cancellation never reserves any snow
        }
    }

    @objc private func swiped(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        self.clear(velocity: gesture.velocity(in: self))
    }

    /// Called from the chat controller's responder chain, without taking keyboard focus.
    public func clearFromShake() {
        guard SnowEffectPreferences.shared.settings.shakeToClear else { return }
        self.clear(velocity: .zero)
    }

    private func clear(velocity: CGPoint) {
        guard self.running, self.model.coverage > 0.01, CACurrentMediaTime() >= self.clearingUntil else { return }
        self.removeDebris()
        self.clearingUntil = CACurrentMediaTime() + 1.0
        // Sample the visible bank before resetting its model, so no frame jumps ahead of growth.
        let visiblePath = self.bank.presentation()?.path ?? self.bank.path
        let heights = self.model.heights(maximum: SnowEffectPreferences.shared.settings.maximumSnowHeight.rawValue)
        let budget = ProcessInfo.processInfo.isLowPowerModeEnabled ? 26 : 52
        let count = min(budget, max(12, Int(self.bounds.width / 8.0)))
        for index in 0 ..< count {
            let x = self.bounds.width * (CGFloat(index) + CGFloat.random(in: 0.1 ... 0.9)) / CGFloat(count)
            let profileIndex = min(heights.count - 1, Int(x / max(1.0, self.bounds.width) * CGFloat(heights.count - 1)))
            let height = CGFloat(heights[profileIndex])
            let particle = CALayer()
            let size = CGFloat.random(in: 2.0 ... 5.0)
            particle.bounds = CGRect(x: 0.0, y: 0.0, width: size, height: size * CGFloat.random(in: 0.6 ... 1.0))
            particle.cornerRadius = size * 0.4
            particle.backgroundColor = UIColor.white.cgColor
            let start = CGPoint(x: x, y: self.bounds.height - CGFloat.random(in: 0.0 ... max(0.1, height)))
            particle.position = start
            particle.opacity = 0.0
            self.debris.addSublayer(particle)
            let duration = Double.random(in: 0.65 ... 1.05)
            let dx = min(180.0, max(-180.0, velocity.x * 0.12)) + CGFloat.random(in: -24.0 ... 24.0)
            let dy = min(60.0, max(-35.0, velocity.y * 0.06))
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = [NSValue(cgPoint: start), NSValue(cgPoint: CGPoint(x: x + dx * 0.45, y: start.y - 8.0 + dy)), NSValue(cgPoint: CGPoint(x: x + dx, y: start.y + CGFloat.random(in: 50.0 ... 100.0) + max(0.0, dy)))]
            movement.keyTimes = [0.0, 0.25, 1.0]
            movement.calculationMode = .cubic
            movement.duration = duration
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.9, 0.9, 0.0]
            opacity.keyTimes = [0.0, 0.35, 1.0]
            opacity.duration = duration
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0.0
            rotation.toValue = Double.random(in: -3.0 ... 3.0)
            rotation.duration = duration
            let group = CAAnimationGroup()
            group.animations = [movement, opacity, rotation]
            group.duration = duration
            particle.add(group, forKey: "scatter")
        }
        self.model.clear()
        self.draw(animated: false)
        if let visiblePath {
            let collapse = CABasicAnimation(keyPath: "path")
            collapse.fromValue = visiblePath
            collapse.toValue = self.bank.path
            collapse.duration = 0.22
            self.bank.add(collapse, forKey: "collapse")
        }
        let work = DispatchWorkItem { [weak self] in self?.removeDebris() }
        self.cleanupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
        self.lastGrowthTime = CACurrentMediaTime()
        self.refresh()
    }

    private func removeDebris() {
        self.cleanupWork?.cancel()
        self.cleanupWork = nil
        self.debris.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}
