import Foundation
import UIKit

/// Explicit local binding to the currently selected Telegram conversation. Device IDs
/// are compared by the users out of band; the server never receives Telegram peer IDs.
public final class WinterSyncSetupViewController: UIViewController {
    private let accountID: Int64
    private let peerID: Int64
    private let endpoint = UITextField()
    private let device = UITextField()
    private let token = UITextField()
    private let code = UITextField()
    private let status = UILabel()
    private var operation: Task<Void, Never>?
    private var buttons: [UIButton] = []

    public init(accountID: Int64, peerID: Int64) {
        self.accountID = accountID; self.peerID = peerID
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .formSheet
    }
    required init?(coder: NSCoder) { preconditionFailure("init(coder:) has not been implemented") }
    deinit { operation?.cancel() }
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        operation?.cancel(); operation = nil
    }
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        let title = UILabel(); title.text = "Winter Sync"; title.font = .preferredFont(forTextStyle: .title1)
        stack.addArrangedSubview(title)
        let explanation = UILabel(); explanation.numberOfLines = 0
        explanation.text = "Для этого личного чата. Введите HTTPS-адрес и выданные администратором ID/ключ устройства. Ключ администратора здесь не нужен. Сравните ID второго устройства через доверенный канал перед подтверждением. Сервер не подтверждает Telegram-личность."
        stack.addArrangedSubview(explanation)
        for (field, placeholder) in [(endpoint, "https://winter.example.org"), (device, "Device UUID"), (token, "Device key (не admin key)"), (code, "Одноразовый код второго устройства")] {
            field.placeholder = placeholder; field.borderStyle = .roundedRect
            field.autocorrectionType = .no; field.autocapitalizationType = .none; field.spellCheckingType = .no
            field.textContentType = nil
            stack.addArrangedSubview(field)
        }
        endpoint.keyboardType = .URL; token.isSecureTextEntry = true
        if let credentials = try? WinterSyncHub.shared.credentials(accountID) {
            endpoint.text = credentials.endpoint.absoluteString; device.text = credentials.deviceID
        }
        button("Сохранить ключ в Keychain", in: stack, action: #selector(configure))
        button("Создать одноразовый код", in: stack, action: #selector(createCode))
        button("Принять код", in: stack, action: #selector(claim))
        button("Проверить пары и подтвердить", in: stack, action: #selector(pairs))
        button("Отозвать доступ этой пары", in: stack, action: #selector(revoke))
        button("Удалить ключ с этого iPhone", in: stack, action: #selector(forget))
        button("Закрыть", in: stack, action: #selector(close))
        status.numberOfLines = 0; status.font = .preferredFont(forTextStyle: .footnote)
        status.text = WinterSyncHub.shared.status(accountID); stack.addArrangedSubview(status)
    }
    private func button(_ title: String, in stack: UIStackView, action: Selector) {
        let button = UIButton(type: .system); var configuration = UIButton.Configuration.tinted()
        configuration.title = title; button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
        buttons.append(button); stack.addArrangedSubview(button)
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard operation == nil else { return }
        buttons.forEach { $0.isEnabled = false }
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.buttons.forEach { $0.isEnabled = true }; self.operation = nil }
            do { try await action() }
            catch {
                if !Task.isCancelled { self.status.text = "Операция не выполнена. Проверьте HTTPS, ключ, подтверждение пары и очередь. Данные Telegram не отправлены." }
            }
        }
    }
    @objc private func configure() {
        guard let url = URL(string: endpoint.text ?? ""), let id = device.text, let secret = token.text,
              let credentials = try? WinterSyncCredentials(endpoint: url, deviceID: id, token: secret) else { status.text = "Нужны HTTPS-адрес, UUID и ключ устройства."; return }
        run { [self] in
            try await WinterSyncHub.shared.configure(credentials, account: accountID)
            token.text = nil; status.text = "Ключ проверен и сохранён только в Keychain этого устройства."
        }
    }
    @objc private func createCode() {
        run { [self] in
            let client = WinterSyncClient(try WinterSyncHub.shared.credentials(accountID)); defer { client.stop() }
            let result = try await client.code()
            let alert = UIAlertController(title: "Код на \(result.expires_in) секунд", message: result.code, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Скопировать код", style: .default) { _ in UIPasteboard.general.string = result.code })
            alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
            present(alert, animated: true)
        }
    }
    @objc private func claim() {
        let value = code.text ?? ""
        guard (16 ... 32).contains(value.count) else { status.text = "Введите одноразовый код."; return }
        run { [self] in
            let client = WinterSyncClient(try WinterSyncHub.shared.credentials(accountID)); defer { client.stop() }
            let pair = try await client.claim(value)
            code.text = nil; status.text = "Пара \(pair) создана. Оба участника должны проверить ID и подтвердить её."
        }
    }
    @objc private func pairs() {
        run { [self] in
            let credentials = try WinterSyncHub.shared.credentials(accountID)
            let client = WinterSyncClient(credentials); defer { client.stop() }
            let pairs = try await client.pairs()
            guard pairs.count <= 32 else { throw WinterSyncError.invalidData }
            let chooser = UIAlertController(title: "Выберите пару для этого чата", message: "Проверьте полный ID второго устройства вне сервиса.", preferredStyle: .actionSheet)
            for pair in pairs {
                guard let other = pair.other(credentials.deviceID) else { continue }
                chooser.addAction(UIAlertAction(title: other, style: .default) { [weak self] _ in self?.confirm(pair, other: other) })
            }
            chooser.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            chooser.popoverPresentationController?.sourceView = view
            chooser.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            present(chooser, animated: true)
        }
    }
    private func confirm(_ pair: WinterSyncPair, other: String) {
        let alert = UIAlertController(title: "Подтвердить устройство?", message: "ID: \(other)\nПара: \(pair.id)\nСвязать его именно с пользователем текущего чата? После подключения зимние события передаются серверу, без технических сообщений Telegram.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "ID проверен, подтверждаю", style: .default) { [weak self] _ in
            guard let self else { return }
            self.run {
                let client = WinterSyncClient(try WinterSyncHub.shared.credentials(self.accountID)); defer { client.stop() }
                guard try await client.confirm(pair.id) else { self.status.text = "Вы подтвердили пару. Ждём второго участника; затем повторите проверку пар."; return }
                guard let active = try await client.pairs().first(where: { $0.id == pair.id }) else { throw WinterSyncError.invalidData }
                try WinterSyncHub.shared.bind(active, account: self.accountID, peer: self.peerID)
                self.status.text = "Пара подключена. Серверный режим не переключается на сообщения Telegram при сбоях."
            }
        })
        present(alert, animated: true)
    }
    @objc private func revoke() {
        let alert = UIAlertController(title: "Отозвать доступ?", message: "Сервис отключит обмен с этой парой. Автоматического возврата к сообщениям Telegram не будет.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Отозвать", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run { try await WinterSyncHub.shared.revoke(account: self.accountID, peer: self.peerID); self.status.text = "Доступ пары отозван." }
        })
        present(alert, animated: true)
    }
    @objc private func forget() {
        let alert = UIAlertController(title: "Удалить локальный ключ?", message: "Неотправленные серверные действия будут удалены. Маршруты останутся приостановлены без Telegram fallback. Для глобального отзыва ключа обратитесь к администратору.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить ключ", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.run {
                try WinterSyncHub.shared.forget(account: self.accountID); self.token.text = nil
                self.status.text = "Локальный ключ удалён."
            }
        })
        present(alert, animated: true)
    }
    @objc private func close() { dismiss(animated: true) }
}
