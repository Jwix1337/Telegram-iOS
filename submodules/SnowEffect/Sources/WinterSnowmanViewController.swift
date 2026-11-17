import Foundation
import QuartzCore
import UIKit

/// A shared-state editor: controls request a visible Telegram event and render only committed state.
public final class WinterSnowmanViewController: UIViewController {
    public var onClose: (() -> Void)?

    private var session: WinterSnowmanSession
    private let onMutation: (SnowmanMutation) -> Void
    private let onComplete: () -> Void
    private let onExport: (UIImage) -> Void
    private let russian = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
    private let canvas = WinterSnowmanCanvas(frame: .zero)
    private let status = UILabel()
    private let addButton = UIButton(type: .system)
    private let completeButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private var colorButtons: [UIButton] = []
    private var boxViews: [UIView] = []
    private var detailButtons: [UIButton] = []
    private var hatButtons: [UIButton] = []
    private let stages: [SnowmanPart] = [.bottom, .middle, .head, .eyes, .nose, .arms, .scarf, .hat]

    public init(session: WinterSnowmanSession, onMutation: @escaping (SnowmanMutation) -> Void, onComplete: @escaping () -> Void, onExport: @escaping (UIImage) -> Void) {
        self.session = session
        self.onMutation = onMutation
        self.onComplete = onComplete
        self.onExport = onExport
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .formSheet
        NotificationCenter.default.addObserver(self, selector: #selector(self.stopAnimations), name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func update(session: WinterSnowmanSession) {
        self.session = session
        if self.isViewLoaded { self.refresh(animated: true) }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scroll)
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14.0
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20.0),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20.0),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16.0),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24.0),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40.0)
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 12.0
        header.addArrangedSubview(self.label(self.session.isSolo ? self.text("Мой снеговик", "My Snowman") : self.text("Наш снеговик", "Our Snowman"), style: .title2))
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.accessibilityLabel = self.text("Закрыть", "Close")
        close.widthAnchor.constraint(equalToConstant: 44.0).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        close.addTarget(self, action: #selector(self.close), for: .touchUpInside)
        header.addArrangedSubview(close)
        content.addArrangedSubview(header)

        self.canvas.heightAnchor.constraint(equalTo: self.canvas.widthAnchor).isActive = true
        self.canvas.layer.cornerRadius = 20.0
        self.canvas.clipsToBounds = true
        self.canvas.isAccessibilityElement = true
        content.addArrangedSubview(self.canvas)
        self.status.numberOfLines = 0
        self.status.font = .preferredFont(forTextStyle: .subheadline)
        self.status.adjustsFontForContentSizeCategory = true
        self.status.textColor = .secondaryLabel
        content.addArrangedSubview(self.status)

        self.style(self.addButton)
        self.addButton.addTarget(self, action: #selector(self.addPart), for: .touchUpInside)
        content.addArrangedSubview(self.addButton)
        let boxTitle = self.label("Бесплатная Зимняя коробка", style: .headline)
        let boxNote = self.label("Улыбка и пуговицы появляются вместе с головой. Добавьте глаза, морковку, веточки, шарф и шапку.", style: .footnote)
        content.addArrangedSubview(boxTitle); content.addArrangedSubview(boxNote)
        boxViews += [boxTitle, boxNote]
        for (index, title) in ["Глаза", "Морковка", "Две веточки", "Шарф", "Шапка"].enumerated() {
            let button = UIButton(type: .system); self.style(button)
            button.tag = index; button.setTitle(title, for: .normal)
            button.addTarget(self, action: #selector(self.addDecoration(_:)), for: .touchUpInside)
            detailButtons.append(button); boxViews.append(button); content.addArrangedSubview(button)
        }
        let colorTitle = self.label(self.text("Цвет шарфа", "Scarf Color"), style: .headline)
        content.addArrangedSubview(colorTitle); boxViews.append(colorTitle)
        let colors = UIStackView()
        colors.axis = .horizontal
        colors.spacing = 10.0
        colors.distribution = .fillEqually
        let colorNames = self.russian ? ["Красный", "Синий", "Зелёный", "Фиолетовый", "Оранжевый", "Розовый"] : ["Red", "Blue", "Green", "Purple", "Orange", "Pink"]
        for (index, color) in WinterSnowmanCanvas.scarfColors.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.backgroundColor = color
            button.layer.cornerRadius = 12.0
            button.layer.borderWidth = 3.0
            button.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
            button.accessibilityLabel = colorNames[index]
            button.addTarget(self, action: #selector(self.chooseColor(_:)), for: .touchUpInside)
            colors.addArrangedSubview(button)
            self.colorButtons.append(button)
        }
        content.addArrangedSubview(colors); boxViews.append(colors)
        content.addArrangedSubview(self.label(self.text("Шапка снеговика", "Snowman's Hat"), style: .headline))

        let hatScroll = UIScrollView()
        hatScroll.showsHorizontalScrollIndicator = false
        hatScroll.heightAnchor.constraint(equalToConstant: 84.0).isActive = true
        let hats = UIStackView()
        hats.axis = .horizontal
        hats.spacing = 8.0
        hats.translatesAutoresizingMaskIntoConstraints = false
        hatScroll.addSubview(hats)
        NSLayoutConstraint.activate([
            hats.leadingAnchor.constraint(equalTo: hatScroll.contentLayoutGuide.leadingAnchor),
            hats.trailingAnchor.constraint(equalTo: hatScroll.contentLayoutGuide.trailingAnchor),
            hats.topAnchor.constraint(equalTo: hatScroll.contentLayoutGuide.topAnchor),
            hats.bottomAnchor.constraint(equalTo: hatScroll.contentLayoutGuide.bottomAnchor),
            hats.heightAnchor.constraint(equalTo: hatScroll.frameLayoutGuide.heightAnchor)
        ])
        for id in 1 ... 10 {
            let button = UIButton(type: .custom)
            button.tag = id
            button.layer.cornerRadius = 12.0
            button.layer.borderWidth = 2.0
            button.widthAnchor.constraint(equalToConstant: 76.0).isActive = true
            button.setImage(WinterSnowmanHatStyle(rawValue: id).flatMap(WinterSnowmanResources.hat), for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.accessibilityLabel = self.text("Шапка", "Hat") + " \(id)"
            button.addTarget(self, action: #selector(self.chooseHat(_:)), for: .touchUpInside)
            hats.addArrangedSubview(button)
            self.hatButtons.append(button)
        }
        content.addArrangedSubview(hatScroll); boxViews.append(hatScroll)
        self.style(self.completeButton)
        self.completeButton.setTitle(self.text("Завершить вместе", "Complete Snowman"), for: .normal)
        self.completeButton.addTarget(self, action: #selector(self.complete), for: .touchUpInside)
        content.addArrangedSubview(self.completeButton)
        self.style(self.exportButton)
        self.exportButton.setTitle(self.text("Сохранить или отправить изображение", "Save or Send Image"), for: .normal)
        self.exportButton.addTarget(self, action: #selector(self.exportImage), for: .touchUpInside)
        content.addArrangedSubview(self.exportButton)
        content.addArrangedSubview(self.label(self.text("Каждая деталь передаётся обычным видимым сообщением после подтверждения. Снеговик обновится после сохранения действия; второй участник увидит его после доставки.", "Each detail is shared in a normal visible message after confirmation. The snowman updates when the action is saved; your partner sees it after delivery."), style: .footnote))
        self.refresh(animated: false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.canvas.stopAnimations()
    }

    private func text(_ ru: String, _ en: String) -> String { self.russian ? ru : en }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = style == .footnote ? .secondaryLabel : .label
        return label
    }

    private func style(_ button: UIButton) {
        var configuration = UIButton.Configuration.tinted()
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14.0, leading: 12.0, bottom: 14.0, trailing: 12.0)
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func refresh(animated: Bool) {
        self.canvas.update(session: self.session, animated: animated)
        let count = self.stages.filter { self.session.contains($0) }.count
        self.canvas.accessibilityLabel = self.text("Снеговик: деталей \(count) из 8", "Snowman: \(count) of 8 details")
        self.status.text = !self.session.accepted ? self.text("Ожидаем принятия приглашения.", "Waiting for the invitation to be accepted.") : (self.session.completed ? self.text("Снеговик готов!", "Your snowman is complete!") : self.text("Добавлено деталей: \(count) из 8.", "Added: \(count) of 8 details."))
        if let next = self.stages.first(where: { !self.session.contains($0) }) {
            self.addButton.setTitle(self.text("Добавить: ", "Add: ") + self.name(next), for: .normal)
        } else {
            self.addButton.setTitle(self.text("Все детали добавлены", "All Details Added"), for: .normal)
        }
        let editable = self.session.accepted && !self.session.completed
        let boxOpen = self.session.contains(.head)
        boxViews.forEach { $0.isHidden = !boxOpen }
        let next = stages.first { !session.contains($0) }
        for button in detailButtons {
            let part = [SnowmanPart.eyes, .nose, .arms, .scarf, .hat][button.tag]
            button.isEnabled = editable && boxOpen && next == part
        }
        self.addButton.isEnabled = editable && (boxOpen || self.session.isSolo) && !self.session.isBuilt
        if !boxOpen && !self.session.isSolo { self.addButton.setTitle("Слепите три шара из накопленного снега", for: .normal) }
        self.completeButton.isEnabled = editable && self.session.isBuilt
        self.exportButton.isEnabled = self.session.isBuilt
        for button in self.colorButtons {
            let selected = button.tag == (self.session.value(.scarfColor) ?? 0)
            button.layer.borderColor = (selected ? UIColor.label : UIColor.clear).cgColor
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            button.isEnabled = editable && boxOpen
        }
        for button in self.hatButtons {
            let selected = button.tag == (self.session.value(.hatStyle) ?? 1)
            button.layer.borderColor = (selected ? UIColor.systemBlue : UIColor.clear).cgColor
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            button.isEnabled = editable && boxOpen
        }
    }

    private func name(_ part: SnowmanPart) -> String {
        switch part {
        case .bottom: return self.text("нижний шар", "bottom snowball")
        case .middle: return self.text("средний шар", "middle snowball")
        case .head: return self.text("голова", "head")
        case .eyes: return self.text("глаза", "eyes")
        case .nose: return self.text("морковка", "carrot nose")
        case .arms: return self.text("руки-ветки", "twig arms")
        case .scarf: return self.text("шарф", "scarf")
        case .hat: return self.text("шапка", "hat")
        case .scarfColor, .hatStyle: return ""
        }
    }

    private func request(_ part: SnowmanPart, value: Int) {
        guard self.session.accepted, !self.session.completed else { return }
        self.onMutation(SnowmanMutation(part: part, value: value, clock: self.session.nextClock))
    }

    @objc private func addDecoration(_ button: UIButton) {
        let part = [SnowmanPart.eyes, .nose, .arms, .scarf, .hat][button.tag]
        guard session.contains(.head), stages.first(where: { !session.contains($0) }) == part else { return }
        request(part, value: 1)
    }

    @objc private func addPart() {
        guard session.isSolo || session.contains(.head), let next = self.stages.first(where: { !self.session.contains($0) }) else { return }
        self.request(next, value: 1)
    }

    @objc private func chooseColor(_ button: UIButton) { self.request(.scarfColor, value: button.tag) }
    @objc private func chooseHat(_ button: UIButton) { self.request(.hatStyle, value: button.tag) }
    @objc private func complete() { if self.session.isBuilt && !self.session.completed { self.onComplete() } }
    @objc private func close() { self.onClose?() }
    @objc private func stopAnimations() { self.canvas.stopAnimations() }

    @objc private func exportImage() {
        guard self.session.isBuilt else { return }
        // A fresh canvas avoids capturing an intermediate installation animation or any controls.
        let export = WinterSnowmanCanvas(frame: CGRect(x: 0.0, y: 0.0, width: 1024.0, height: 1024.0))
        export.update(session: self.session, animated: false)
        export.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: export.bounds.size, format: format).image { context in
            export.layer.render(in: context.cgContext)
        }
        self.onExport(image)
    }
}

/// A fixed small set of shape layers, shared by the on-screen preview and exported artwork.
final class WinterSnowmanCanvas: UIView {
    static let scarfColors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemPurple, .systemOrange, .systemPink]
    private let artwork = CALayer()
    private let ground = CAShapeLayer()
    private let smile = CAShapeLayer()
    private let buttons = CAShapeLayer()
    private let bodyLayer = CALayer()
    private let scarfLayer = CAGradientLayer()
    private let scarfArtwork = CALayer()
    private var parts: [SnowmanPart: CALayer] = [:]
    private var visibleParts = Set<SnowmanPart>()

    init(frame: CGRect, transparent: Bool = false) {
        super.init(frame: frame)
        self.isOpaque = !transparent
        self.backgroundColor = transparent ? .clear : .secondarySystemBackground
        self.isUserInteractionEnabled = false
        self.layer.addSublayer(self.artwork)
        self.ground.isHidden = transparent
        self.ground.fillColor = UIColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 1.0).cgColor
        self.ground.path = UIBezierPath(ovalIn: CGRect(x: 230, y: 930, width: 560, height: 50)).cgPath
        self.artwork.addSublayer(self.ground)

        self.parts[.arms] = self.shape(self.arms(), fill: .clear, stroke: UIColor(red: 0.34, green: 0.22, blue: 0.15, alpha: 1.0), lineWidth: 14.0)
        for (part, rect) in [(SnowmanPart.bottom, WinterSnowmanGeometry.bottom), (.middle, WinterSnowmanGeometry.middle), (.head, WinterSnowmanGeometry.head)] {
            let ball = CALayer()
            ball.frame = rect
            ball.contents = Self.snowballTexture
            self.parts[part] = ball
        }
        // Keep one coherent body for every hat/scarf. The previous whole-character
        // substitutions changed the entire snowman when only an accessory changed.
        self.bodyLayer.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        self.bodyLayer.contents = WinterSnowmanResources.bareBody?.cgImage
        self.bodyLayer.contentsGravity = .resizeAspect
        self.bodyLayer.isHidden = true
        let mouth = UIBezierPath()
        mouth.move(to: CGPoint(x: 455, y: 405)); mouth.addQuadCurve(to: CGPoint(x: 554, y: 405), controlPoint: CGPoint(x: 505, y: 447))
        smile.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        buttons.frame = smile.frame
        smile.path = mouth.cgPath; smile.fillColor = UIColor.clear.cgColor; smile.strokeColor = UIColor.darkGray.cgColor; smile.lineWidth = 6
        let coals = UIBezierPath()
        for y in [555.0, 625.0, 775.0] { coals.append(UIBezierPath(ovalIn: CGRect(x: 495, y: y, width: 20, height: 20))) }
        buttons.path = coals.cgPath; buttons.fillColor = UIColor.darkGray.cgColor
        let eyes = UIBezierPath(ovalIn: CGRect(x: 441, y: 330, width: 21, height: 23))
        eyes.append(UIBezierPath(ovalIn: CGRect(x: 550, y: 330, width: 21, height: 23)))
        self.parts[.eyes] = self.shape(eyes, fill: UIColor(white: 0.12, alpha: 1.0))
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: 500, y: 368))
        nose.addQuadCurve(to: CGPoint(x: 606, y: 380), controlPoint: CGPoint(x: 546, y: 360))
        nose.addQuadCurve(to: CGPoint(x: 500, y: 392), controlPoint: CGPoint(x: 553, y: 399))
        nose.close()
        self.parts[.nose] = self.shape(nose, fill: .systemOrange)
        let scarf = UIBezierPath(roundedRect: CGRect(x: 363, y: 441, width: 286, height: 59), cornerRadius: 28.0)
        scarf.append(UIBezierPath(roundedRect: CGRect(x: 562, y: 479, width: 55, height: 153), cornerRadius: 12.0))
        self.scarfLayer.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        self.scarfLayer.startPoint = CGPoint(x: 0.3, y: 0.3)
        self.scarfLayer.endPoint = CGPoint(x: 0.65, y: 0.65)
        self.scarfLayer.mask = self.shape(scarf, fill: .white)
        let scarfContainer = CALayer()
        scarfContainer.frame = self.scarfLayer.frame
        self.scarfArtwork.frame = self.scarfLayer.frame
        scarfContainer.addSublayer(self.scarfLayer)
        scarfContainer.addSublayer(self.scarfArtwork)
        self.parts[.scarf] = scarfContainer
        for (part, material) in [(SnowmanPart.arms, WinterSnowmanCutout.Part.arms), (.nose, .nose)] {
            if let image = WinterSnowmanResources.accessory(material) {
                let layer = CALayer()
                layer.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)
                layer.contents = image.cgImage
                self.parts[part] = layer
            }
        }
        let hat = CALayer()
        hat.contentsGravity = .resizeAspect
        self.parts[.hat] = hat
        // Arms sit behind the body, with the scarf and hat above their snow surfaces.
        for part in [SnowmanPart.arms, .bottom, .middle, .head, .eyes, .nose, .scarf, .hat] {
            if part == .eyes { self.artwork.addSublayer(self.bodyLayer) }
            if let layer = self.parts[part] {
                layer.isHidden = true
                self.artwork.addSublayer(layer)
            }
        }
        self.artwork.addSublayer(smile); self.artwork.addSublayer(buttons)
    }

    required init?(coder: NSCoder) { preconditionFailure("init(coder:) has not been implemented") }

    private var usesBodyReference: Bool {
        self.bodyLayer.contents != nil && [SnowmanPart.bottom, .middle, .head].allSatisfy { self.visibleParts.contains($0) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.artwork.bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        self.artwork.anchorPoint = .zero
        let scale = min(self.bounds.width, self.bounds.height) / 1024.0
        self.artwork.position = CGPoint(x: (self.bounds.width - 1024.0 * scale) * 0.5, y: (self.bounds.height - 1024.0 * scale) * 0.5)
        self.artwork.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        self.bodyLayer.isHidden = !self.usesBodyReference
        self.smile.isHidden = !self.visibleParts.contains(.head)
        self.buttons.isHidden = !self.visibleParts.contains(.head)
        for (part, layer) in self.parts {
            layer.isHidden = !self.visibleParts.contains(part) || (self.usesBodyReference && [.bottom, .middle, .head].contains(part))
        }
        CATransaction.commit()
    }

    func update(session: WinterSnowmanSession, animated: Bool) {
        let previous = self.visibleParts
        var visible = Set<SnowmanPart>()
        for part in [SnowmanPart.bottom, .middle, .head, .eyes, .nose, .arms, .scarf, .hat] {
            guard session.contains(part) else { break }
            visible.insert(part)
        }
        let animate = animated && !UIAccessibility.isReduceMotionEnabled
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical
            && SnowEffectPreferences.shared.settings.winterAnimationsEnabled
            && UIApplication.shared.applicationState == .active
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let colorIndex = min(Self.scarfColors.count - 1, max(0, session.value(.scarfColor) ?? 0))
        let scarf = WinterSnowmanResources.accessory(.scarf, color: colorIndex)
        self.scarfArtwork.contents = scarf?.cgImage
        self.scarfArtwork.isHidden = scarf == nil
        self.scarfLayer.isHidden = scarf != nil
        let color = Self.scarfColors[colorIndex]
        self.scarfLayer.colors = [color.withAlphaComponent(0.85).cgColor, color.cgColor, color.withAlphaComponent(0.7).cgColor]
        if let style = WinterSnowmanHatStyle(rawValue: session.value(.hatStyle) ?? 1),
           let image = WinterSnowmanResources.hat(style),
           let placement = WinterSnowmanGeometry.hat(style, imageSize: image.size), let hat = self.parts[.hat] {
            hat.contents = image.cgImage
            hat.bounds = CGRect(origin: .zero, size: placement.size)
            hat.position = placement.center
        } else { self.parts[.hat]?.contents = nil }
        self.visibleParts = visible
        self.bodyLayer.isHidden = !self.usesBodyReference
        smile.isHidden = !visible.contains(.head)
        buttons.isHidden = !visible.contains(.head)
        for (part, layer) in self.parts {
            layer.isHidden = !visible.contains(part) || (self.usesBodyReference && [.bottom, .middle, .head].contains(part))
            if !layer.isHidden && animate && visible.contains(part) && !previous.contains(part) {
                let opacity = CABasicAnimation(keyPath: "opacity")
                opacity.fromValue = 0.0
                opacity.toValue = 1.0
                opacity.duration = 0.25
                let placement = CABasicAnimation(keyPath: "transform.translation.y")
                placement.fromValue = -24.0
                placement.toValue = 0.0
                placement.duration = 0.25
                placement.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(opacity, forKey: "installation.opacity")
                layer.add(placement, forKey: "installation.position")
            } else if !animate || layer.isHidden {
                layer.removeAllAnimations()
            }
        }
        CATransaction.commit()
        self.visibleParts = visible
        self.setNeedsLayout()
    }

    func stopAnimations() {
        self.parts.values.forEach { $0.removeAllAnimations() }
    }

    private static let snowballTexture: CGImage? = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
            let c = context.cgContext
            c.addEllipse(in: CGRect(x: 1, y: 1, width: 254, height: 254)); c.clip()
            let colors = [UIColor.white.cgColor, UIColor(red: 0.88, green: 0.90, blue: 0.95, alpha: 1).cgColor, UIColor(red: 0.72, green: 0.77, blue: 0.86, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.72, 1]) {
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: 94, y: 74), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 180, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            // Deterministic static grain, cached once; no random redraw or frame loop.
            for i in 0..<1800 {
                let x = CGFloat((i * 79 + 17) % 256), y = CGFloat((i * 137 + i / 3) % 256)
                c.setFillColor(UIColor(white: i % 3 == 0 ? 0.65 : 1, alpha: 0.10).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
            }
        }.cgImage
    }()

    private func shape(_ path: UIBezierPath, fill: UIColor, stroke: UIColor? = nil, lineWidth: CGFloat = 0.0) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(x: 0.0, y: 0.0, width: 1024.0, height: 1024.0)
        layer.path = path.cgPath
        layer.fillColor = fill.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private func arms() -> UIBezierPath {
        let path = UIBezierPath()
        for direction in [CGFloat(-1.0), CGFloat(1.0)] {
            path.move(to: CGPoint(x: 505.0 + direction * 150.0, y: 565.0))
            path.addLine(to: CGPoint(x: 505.0 + direction * 300.0, y: 473.0))
            path.move(to: CGPoint(x: 505.0 + direction * 250.0, y: 500.0))
            path.addLine(to: CGPoint(x: 505.0 + direction * 252.0, y: 448.0))
            path.move(to: CGPoint(x: 505.0 + direction * 270.0, y: 489.0))
            path.addLine(to: CGPoint(x: 505.0 + direction * 328.0, y: 497.0))
        }
        return path
    }
}
