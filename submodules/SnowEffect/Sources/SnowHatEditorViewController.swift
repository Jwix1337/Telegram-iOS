import Foundation
import UIKit

/// Edits normalized overlay geometry; publishing is an explicit action handled by Telegram UI.
public final class SnowHatEditorViewController: UIViewController, UIGestureRecognizerDelegate {
    public var onClose: (() -> Void)?

    private let accountID: Int64
    private let onPublish: (SnowHatConfiguration) -> Void
    private var localPeerID: Int64?
    private var avatarPreviewView: UIView?
    public var avatarPreviewLayout: ((CGSize) -> Void)?
    private var draft: SnowHatConfiguration
    private let russian = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let previewContainer = UIView()
    private let avatar = UIImageView()
    private let overlay = SnowHatOverlayView()
    private let status = UILabel()
    private var choices: [UIButton] = []

    public init(accountID: Int64, avatarImage: UIImage?, onPublish: @escaping (SnowHatConfiguration) -> Void) {
        self.accountID = accountID
        self.onPublish = onPublish
        self.draft = SnowHatStore.shared.configuration(accountID: accountID, peerID: accountID) ?? SnowHatConfiguration(ownerID: accountID)
        super.init(nibName: nil, bundle: nil)
        self.avatar.image = avatarImage
        self.modalPresentationStyle = .formSheet
    }

    /// Transactional profile editor: only Apply writes; dismissal discards the draft.
    public convenience init(accountID: Int64, peerID: Int64, avatarPreviewView: UIView) {
        self.init(accountID: accountID, avatarImage: nil, onPublish: { _ in })
        self.localPeerID = peerID
        self.draft = SnowHatStore.shared.displayConfiguration(accountID: accountID, peerID: peerID)
            ?? SnowHatConfiguration(ownerID: peerID, enabled: false)
        self.avatarPreviewView = avatarPreviewView
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    public func updateAvatarImage(_ image: UIImage?) {
        self.avatar.image = image
        if self.isViewLoaded { self.updatePreview() }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scrollView)
        self.content.axis = .vertical
        self.content.spacing = 14.0
        self.content.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.content)
        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            self.content.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor, constant: 20.0),
            self.content.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor, constant: -20.0),
            self.content.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 16.0),
            self.content.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -24.0),
            self.content.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor, constant: -40.0)
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 12.0
        let title = self.label(self.text("Новогодние шапки", "Holiday Hats"), style: .title2)
        title.font = .preferredFont(forTextStyle: .title2)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.accessibilityLabel = self.text("Закрыть", "Close")
        close.addTarget(self, action: #selector(self.close), for: .touchUpInside)
        close.widthAnchor.constraint(equalToConstant: 44.0).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        header.addArrangedSubview(title)
        header.addArrangedSubview(close)
        self.content.addArrangedSubview(header)

        self.previewContainer.heightAnchor.constraint(equalToConstant: 290.0).isActive = true
        self.previewContainer.backgroundColor = .secondarySystemBackground
        self.previewContainer.layer.cornerRadius = 20.0
        self.previewContainer.clipsToBounds = true
        self.avatar.contentMode = .scaleAspectFill
        self.avatar.backgroundColor = .tertiarySystemFill
        self.avatar.tintColor = .secondaryLabel
        self.avatar.clipsToBounds = true
        self.previewContainer.addSubview(self.avatar)
        if let preview = self.avatarPreviewView {
            preview.isUserInteractionEnabled = false
            self.avatar.addSubview(preview)
        }
        self.previewContainer.addSubview(self.overlay)
        self.content.addArrangedSubview(self.previewContainer)
        self.content.addArrangedSubview(self.label(self.text("Двигайте шапку, изменяйте размер двумя пальцами и поворачивайте.", "Drag the hat, pinch to resize, and rotate with two fingers."), style: .footnote))

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(self.rotate(_:)))
        let gestures: [UIGestureRecognizer] = [pan, pinch, rotation]
        for gesture in gestures {
            gesture.delegate = self
            self.previewContainer.addGestureRecognizer(gesture)
        }

        let selector = UIScrollView()
        selector.showsHorizontalScrollIndicator = false
        selector.heightAnchor.constraint(equalToConstant: 106.0).isActive = true
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8.0
        row.translatesAutoresizingMaskIntoConstraints = false
        selector.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: selector.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: selector.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: selector.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: selector.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: selector.frameLayoutGuide.heightAnchor)
        ])
        for id in 1 ... 10 {
            let button = self.hatButton(id: id)
            self.choices.append(button)
            row.addArrangedSubview(button)
        }
        self.content.addArrangedSubview(selector)
        self.status.font = .preferredFont(forTextStyle: .footnote)
        self.status.adjustsFontForContentSizeCategory = true
        self.status.textColor = .secondaryLabel
        self.status.numberOfLines = 0
        self.content.addArrangedSubview(self.status)
        if self.localPeerID != nil {
            self.content.addArrangedSubview(self.action(self.text("Без шапки", "No Hat"), selector: #selector(self.removeHat), prominent: false))
            self.content.addArrangedSubview(self.action(self.text("Применить", "Apply"), selector: #selector(self.applyOverride), prominent: true))
            self.content.addArrangedSubview(self.action(self.text("Отмена", "Cancel"), selector: #selector(self.close), prominent: false))
            self.content.addArrangedSubview(self.label(self.text("Украшение видно только в текущем аккаунте на этом устройстве. Фото Telegram не изменяется.", "Visible only in this account on this device. The Telegram photo is unchanged."), style: .footnote))
        } else {
            self.content.addArrangedSubview(self.action(self.text("Сохранить на устройстве", "Save on This Device"), selector: #selector(self.saveLocal), prominent: false))
            self.content.addArrangedSubview(self.action(self.text("Сохранить и опубликовать", "Save and Publish"), selector: #selector(self.publish), prominent: true))
            self.content.addArrangedSubview(self.action(self.text("Сбросить положение", "Reset Position"), selector: #selector(self.resetPosition), prominent: false))
            self.content.addArrangedSubview(self.action(self.text("Отключить и опубликовать", "Disable and Publish"), selector: #selector(self.disableAndPublish), prominent: false))
            self.content.addArrangedSubview(self.label(self.text("Другие пользователи Telegram Snow увидят шапку после получения обычного видимого сообщения. При публикации вы выберете получателя и подтвердите отправку. Фото профиля не изменяется.", "Other Telegram Snow users see your hat after receiving a normal visible message. Publishing lets you choose a recipient and confirm sending. Your profile photo stays unchanged."), style: .footnote))
        }
        self.updatePreview()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let diameter = min(166.0, max(80.0, self.previewContainer.bounds.width - 100.0))
        self.avatar.frame = CGRect(x: (self.previewContainer.bounds.width - diameter) * 0.5, y: 102.0, width: diameter, height: diameter)
        self.avatar.layer.cornerRadius = diameter * 0.5
        self.avatarPreviewView?.frame = self.avatar.bounds
        self.avatarPreviewLayout?(self.avatar.bounds.size)
        self.overlay.frame = self.avatar.frame
        self.overlay.layoutIfNeeded()
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer.view === self.previewContainer && otherGestureRecognizer.view === self.previewContainer
    }

    private func text(_ ru: String, _ en: String) -> String { self.russian ? ru : en }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = style == .footnote ? .secondaryLabel : .label
        label.numberOfLines = 0
        return label
    }

    private func action(_ title: String, selector: Selector, prominent: Bool) -> UIButton {
        let button = UIButton(type: .system)
        var configuration: UIButton.Configuration = prominent ? .filled() : .tinted()
        configuration.title = title
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14.0, leading: 12.0, bottom: 14.0, trailing: 12.0)
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    private func hatButton(id: Int) -> UIButton {
        let ru = ["Санта", "Оленёнок", "Кошка", "Снеговик", "Эльф", "Гирлянда", "Золотая", "Вязаная", "Розовая", "Неоновая"]
        let en = ["Santa", "Reindeer", "Cat", "Snowman", "Elf", "Lights", "Gold", "Knitted", "Pink", "Neon"]
        let button = UIButton(type: .system)
        button.tag = id
        button.accessibilityLabel = (self.russian ? ru : en)[id - 1]
        button.layer.cornerRadius = 12.0
        button.layer.borderWidth = 2.0
        button.widthAnchor.constraint(equalToConstant: 88.0).isActive = true
        let image = UIImageView(image: SnowHatAssets.image(for: id))
        image.contentMode = .scaleAspectFit
        image.isUserInteractionEnabled = false
        image.translatesAutoresizingMaskIntoConstraints = false
        let name = self.label(button.accessibilityLabel ?? "", style: .caption2)
        name.textAlignment = .center
        name.isUserInteractionEnabled = false
        name.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(image)
        button.addSubview(name)
        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: button.topAnchor, constant: 4.0),
            image.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 5.0),
            image.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -5.0),
            image.heightAnchor.constraint(equalToConstant: 72.0),
            name.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 3.0),
            name.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2.0),
            name.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2.0),
            name.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -3.0)
        ])
        button.addTarget(self, action: #selector(self.choose(_:)), for: .touchUpInside)
        return button
    }

    private func updatePreview() {
        if self.avatar.image == nil { self.avatar.image = UIImage(systemName: "person.fill") }
        self.overlay.preview(self.draft)
        for button in self.choices {
            let selected = self.draft.enabled && button.tag == self.draft.hatID
            button.layer.borderColor = (selected ? UIColor.systemBlue : UIColor.clear).cgColor
            button.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.08) : .clear
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        if self.localPeerID != nil {
            self.status.text = self.text("Предпросмотр. Изменения сохраняются только по кнопке «Применить».", "Preview. Changes are saved only when you tap Apply.")
            return
        }
        self.status.text = self.draft.enabled ? self.text("Предпросмотр. Публикация передаёт настройки выбранному пользователю видимым сообщением.", "Preview. Publishing shares these settings with the selected user in a visible message.") : self.text("Шапка отключена. Выберите шапку, чтобы включить её.", "Hat is disabled. Choose a hat to enable it.")
    }

    private func stampedDraft() -> SnowHatConfiguration {
        var value = self.draft
        let previous = SnowHatStore.shared.configuration(accountID: self.accountID, peerID: self.accountID)?.modifiedAt ?? 0
        value.modifiedAt = max(Int64((Date().timeIntervalSince1970 * 1000.0).rounded()), previous < Int64.max ? previous + 1 : previous)
        return value
    }

    @objc private func choose(_ sender: UIButton) {
        self.draft.hatID = sender.tag
        self.draft.enabled = true
        self.updatePreview()
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard self.avatar.bounds.width > 0.0, gesture.state == .began || gesture.state == .changed else { return }
        let translation = gesture.translation(in: self.previewContainer)
        self.draft.offsetX = min(1.0, max(-1.0, self.draft.offsetX + Double(translation.x / self.avatar.bounds.width)))
        self.draft.offsetY = min(1.0, max(-1.0, self.draft.offsetY + Double(translation.y / self.avatar.bounds.height)))
        gesture.setTranslation(.zero, in: self.previewContainer)
        self.updatePreview()
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        self.draft.scale = min(2.0, max(0.35, self.draft.scale * Double(gesture.scale)))
        gesture.scale = 1.0
        self.updatePreview()
    }

    @objc private func rotate(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let angle = self.draft.rotation + Double(gesture.rotation)
        self.draft.rotation = atan2(sin(angle), cos(angle))
        gesture.rotation = 0.0
        self.updatePreview()
    }

    @objc private func resetPosition() {
        self.draft.scale = 1.0
        self.draft.offsetX = 0.0
        self.draft.offsetY = -0.4
        self.draft.rotation = 0.0
        self.updatePreview()
    }

    @objc private func removeHat() {
        self.draft.enabled = false
        self.updatePreview()
    }

    @objc private func applyOverride() {
        guard let peerID = self.localPeerID else { return }
        if SnowHatStore.shared.saveOverride(self.draft, accountID: self.accountID, peerID: peerID) {
            self.close()
        }
    }

    @objc private func saveLocal() {
        self.draft = self.stampedDraft()
        if SnowHatStore.shared.saveLocal(self.draft, accountID: self.accountID) {
            self.status.text = self.text("Сохранено только на этом устройстве. Для обмена нажмите «Сохранить и опубликовать».", "Saved only on this device. Use Save and Publish to share.")
        }
    }

    @objc private func publish() {
        self.onPublish(self.stampedDraft())
    }

    @objc private func disableAndPublish() {
        self.draft.enabled = false
        self.updatePreview()
        self.onPublish(self.stampedDraft())
    }

    @objc private func close() {
        if let onClose = self.onClose { onClose() } else { self.dismiss(animated: true) }
    }
}
