import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AlertUI
import SnowEffect

/// The only network bridge for explicitly confirmed winter events, including hats.
/// An interrupted enqueue can repeat its visible message; event IDs prevent repeating effects.
final class WinterEventAccountBridge {
    private weak var context: AccountContext?
    private var incoming: Disposable?
    private let outgoing = MetaDisposable()
    private var observers: [NSObjectProtocol] = []
    private var retry: Timer?
    private var sending = false
    private var stopped = false

    init(context: AccountContext) {
        self.context = context
        let accountID = context.account.peerId.toInt64()
        self.incoming = context.account.stateManager.incomingMessages.start(next: { messages in
            for message in messages {
                guard message.id.namespace == Namespaces.Message.Cloud,
                      message.id.peerId.namespace == Namespaces.Peer.CloudUser,
                      message.forwardInfo == nil,
                      let author = message.author, author.id == message.id.peerId else { continue }
                let _ = WinterEventTransport.shared.receive(messageText: message.text, authorID: author.id.toInt64(), accountID: accountID, messageTimestamp: message.timestamp)
            }
        })
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: WinterEventTransport.didChange, object: WinterEventTransport.shared, queue: .main) { [weak self] notification in
            guard (notification.userInfo?["accountID"] as? Int64) == accountID else { return }
            self?.pump()
        })
        self.observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.pump() })
        DispatchQueue.main.async { [weak self] in self?.pump() }
    }

    deinit { self.stop() }

    func stop() {
        self.stopped = true
        self.retry?.invalidate()
        self.retry = nil
        self.incoming?.dispose()
        self.incoming = nil
        self.outgoing.dispose()
        for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
        self.observers.removeAll()
    }

    private func pump() {
        guard !self.stopped, !self.sending, UIApplication.shared.applicationState == .active,
              let context = self.context else { return }
        let accountID = context.account.peerId.toInt64()
        guard let event = WinterEventTransport.shared.pendingOutgoing(accountID: accountID).first,
              let text = WinterEventTransport.shared.messageText(event) else { return }
        self.sending = true
        self.retry?.invalidate()
        self.retry = nil
        let message: EnqueueMessage = .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        self.outgoing.set((enqueueMessages(account: context.account, peerId: EnginePeer.Id(event.recipientID), messages: [message])
        |> deliverOnMainQueue).start(next: { [weak self] ids in
            guard let self, !self.stopped else { return }
            self.sending = false
            if ids.contains(where: { $0 != nil }) {
                WinterEventTransport.shared.markEnqueued(eventID: event.eventID, accountID: accountID)
                DispatchQueue.main.async { [weak self] in self?.pump() }
            } else {
                let timer = Timer(timeInterval: 15.0, repeats: false) { [weak self] _ in self?.pump() }
                RunLoop.main.add(timer, forMode: .common)
                self.retry = timer
            }
        }))
    }
}

/// Chat-local controls and presentation. Persistent state and delivery are owned by the transport.
final class WinterChatInteractions: NSObject {
    private let context: AccountContext
    private let peerID: EnginePeer.Id
    private weak var host: ViewController?
    private let sendImage: (UIImage) -> Void
    private let snowball = WinterSnowballView(frame: .zero)
    private var visible = false
    private weak var snowmanHost: WinterSnowmanHostController?
    private var snowmanSessionID: String?
    private lazy var button = UIBarButtonItem(image: UIImage(systemName: "snowflake"), style: .plain, target: self, action: #selector(self.showMenu))
    private var accountID: Int64 { self.context.account.peerId.toInt64() }
    private var russian: Bool { self.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.lowercased().hasPrefix("ru") }

    init(context: AccountContext, peerID: EnginePeer.Id, host: ViewController, sendImage: @escaping (UIImage) -> Void) {
        self.context = context
        self.peerID = peerID
        self.host = host
        self.sendImage = sendImage
        super.init()
        self.button.accessibilityLabel = self.text("Зимние действия", "Winter Actions")
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(self.changed), name: WinterEventTransport.didChange, object: WinterEventTransport.shared)
        center.addObserver(self, selector: #selector(self.changed), name: SnowEffectPreferences.didChange, object: SnowEffectPreferences.shared)
        center.addObserver(self, selector: #selector(self.changed), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(self.resignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else {
            self.layout()
            return
        }
        self.visible = visible
        self.refresh()
    }

    func layout() {
        if let host = self.host, host.isViewLoaded {
            self.snowball.frame = host.view.bounds
        }
        self.installButton()
    }

    private var canPresent: Bool {
        return self.visible && UIApplication.shared.applicationState == .active && self.host?.isViewLoaded == true && self.host?.view.window != nil
    }

    private func text(_ ru: String, _ en: String) -> String { self.russian ? ru : en }

    @objc private func changed() { self.refresh() }
    @objc private func resignActive() {
        self.snowball.stop()
        self.removeButton()
    }

    private func installButton() {
        let settings = SnowEffectPreferences.shared.settings
        guard self.canPresent, settings.winterSnowballsEnabled || settings.winterSnowmanEnabled,
              let host = self.host else {
            self.removeButton()
            return
        }
        var items = host.navigationItem.rightBarButtonItems ?? []
        guard !items.contains(where: { $0 === self.button }) else { return }
        items.insert(self.button, at: 0)
        host.navigationItem.rightBarButtonItems = items
    }

    private func removeButton() {
        guard let host = self.host, let items = host.navigationItem.rightBarButtonItems,
              items.contains(where: { $0 === self.button }) else { return }
        host.navigationItem.rightBarButtonItems = items.filter { $0 !== self.button }
    }

    private func refresh() {
        if let session = WinterEventTransport.shared.session(accountID: self.accountID, peerID: self.peerID.toInt64()) {
            self.snowmanSessionID = session.sessionID
            self.snowmanHost?.update(session: session)
        }
        self.installButton()
        guard self.canPresent, let host = self.host else {
            self.snowball.stop()
            return
        }
        if self.snowball.superview == nil {
            self.snowball.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.addSubview(self.snowball)
        }
        self.layout()
        // Reading pending events is independent of message-history scrolling. Persist consumption
        // even with animations disabled, so enabling them later cannot replay old actions.
        let events = WinterEventTransport.shared.pendingSnowballs(accountID: self.accountID, peerID: self.peerID.toInt64(), consume: true)
        let settings = SnowEffectPreferences.shared.settings
        if settings.winterReceiveSnowballs, settings.winterAnimationsEnabled, let event = events.last {
            self.snowball.play(incoming: true, seed: self.seed(event))
        }
    }

    private func seed(_ event: WinterEvent) -> Int {
        event.eventID.utf8.reduce(0) { ($0 * 31 + Int($1)) % 104729 }
    }

    @objc private func showMenu() {
        guard self.canPresent else { return }
        let settings = SnowEffectPreferences.shared.settings
        let session = WinterEventTransport.shared.session(accountID: self.accountID, peerID: self.peerID.toInt64())
        let sheet = ActionSheetController(presentationData: self.context.sharedContext.currentPresentationData.with { $0 })
        var items: [ActionSheetItem] = []
        if settings.winterSnowballsEnabled {
            items.append(ActionSheetButtonItem(title: self.text("Бросить снежок", "Throw Snowball"), color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.request(type: .snowball)
            }))
        }
        if settings.winterSnowmanEnabled {
            if let session, !session.completed {
                let needsAccept = !session.accepted && session.inviteeID == self.accountID
                items.append(ActionSheetButtonItem(title: needsAccept ? self.text("Принять приглашение слепить снеговика", "Accept Snowman Invitation") : self.text("Открыть общего снеговика", "Open Shared Snowman"), color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    if needsAccept { self?.request(type: .snowman_accept, sessionID: session.sessionID, openAfter: true) }
                    else { self?.openSnowman(session) }
                }))
            } else {
                items.append(ActionSheetButtonItem(title: self.text("Слепить снеговика", "Build Snowman"), color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.request(type: .snowman_invite, openAfter: true)
                }))
            }
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.text("Отмена", "Cancel"), color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
        self.host?.present(sheet, in: .window(.root))
    }

    private func request(type: WinterEvent.Kind, sessionID: String? = nil, mutation: SnowmanMutation? = nil, openAfter: Bool = false) {
        let title = type.label
        let body = self.text("В этот чат будет отправлено обычное видимое сообщение с зимним действием. Получатель увидит эффект в совместимом Telegram Snow. Отправить?", "An ordinary visible winter-action message will be sent to this chat. The recipient sees its effect in a compatible Telegram Snow. Send?")
        self.confirm(title: title, body: body) { [weak self] in
            guard let self else { return }
            let settings = SnowEffectPreferences.shared.settings
            guard type != .snowball || settings.winterSnowballsEnabled,
                  type == .snowball || settings.winterSnowmanEnabled,
                  let event = WinterEventTransport.shared.makeEvent(type: type, accountID: self.accountID, peerID: self.peerID.toInt64(), sessionID: sessionID, mutation: mutation),
                  WinterEventTransport.shared.recordOutgoing(event, accountID: self.accountID) else {
                self.notice(self.text("Действие пока недоступно. Подождите немного и проверьте состояние снеговика.", "This action is not available yet. Wait briefly and check the snowman state."))
                return
            }
            if type == .snowball, self.canPresent {
                self.snowball.play(incoming: false, seed: self.seed(event))
            }
            if openAfter, let session = WinterEventTransport.shared.session(accountID: self.accountID, peerID: self.peerID.toInt64()) {
                self.openSnowman(session)
            }
        }
    }

    private func confirm(title: String, body: String, action: @escaping () -> Void) {
        let controller = textAlertController(context: self.context, title: title, text: body, actions: [
            TextAlertAction(type: .genericAction, title: self.text("Отмена", "Cancel"), action: {}),
            TextAlertAction(type: .defaultAction, title: self.text("Отправить сообщение", "Send Message"), action: action)
        ])
        if let snowmanHost = self.snowmanHost { snowmanHost.present(controller, in: .window(.root)) }
        else { self.host?.present(controller, in: .window(.root)) }
    }

    private func notice(_ message: String) {
        let alert = textAlertController(context: self.context, title: self.text("Зимние действия", "Winter Actions"), text: message, actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})])
        if let snowmanHost = self.snowmanHost { snowmanHost.present(alert, in: .window(.root)) }
        else { self.host?.present(alert, in: .window(.root)) }
    }

    private func openSnowman(_ session: WinterSnowmanSession) {
        guard SnowEffectPreferences.shared.settings.winterSnowmanEnabled else { return }
        self.snowmanSessionID = session.sessionID
        if let snowmanHost = self.snowmanHost {
            snowmanHost.update(session: session)
            return
        }
        let controller = WinterSnowmanHostController(context: self.context, session: session, onMutation: { [weak self] mutation in
            guard let self, let sessionID = self.snowmanSessionID else { return }
            self.request(type: .snowman_update, sessionID: sessionID, mutation: mutation)
        }, onComplete: { [weak self] in
            guard let self, let sessionID = self.snowmanSessionID else { return }
            self.request(type: .snowman_complete, sessionID: sessionID)
        }, onExport: { [weak self] image in self?.export(image) })
        self.snowmanHost = controller
        if let navigation = self.host?.navigationController as? NavigationController { navigation.pushViewController(controller) }
        else { self.host?.present(controller, in: .window(.root)) }
    }

    private func export(_ image: UIImage) {
        guard let presenter = self.snowmanHost else { return }
        let sheet = ActionSheetController(presentationData: self.context.sharedContext.currentPresentationData.with { $0 })
        sheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: self.text("Сохранить изображение / Поделиться", "Save Image / Share"), color: .accent, action: { [weak presenter, weak sheet] in
                sheet?.dismissAnimated()
                guard let presenter else { return }
                let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                activity.popoverPresentationController?.sourceView = presenter.view
                activity.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1.0, height: 1.0)
                presenter.present(activity, animated: true)
            }),
            ActionSheetButtonItem(title: self.text("Отправить изображение в этот чат", "Send Image to This Chat"), color: .accent, action: { [weak self, weak sheet] in
                sheet?.dismissAnimated()
                self?.confirm(title: self?.text("Готовый снеговик", "Finished Snowman") ?? "Snowman", body: self?.text("Отправить изображение снеговика обычной фотографией в этот чат?", "Send the snowman image as a normal photo to this chat?") ?? "") { [weak self] in self?.sendImage(image) }
            })
        ]), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: self.text("Отмена", "Cancel"), color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])])
        presenter.present(sheet, in: .window(.root))
    }
}

private final class WinterSnowmanHostController: ViewController {
    private let content: WinterSnowmanViewController

    init(context: AccountContext, session: WinterSnowmanSession, onMutation: @escaping (SnowmanMutation) -> Void, onComplete: @escaping () -> Void, onExport: @escaping (UIImage) -> Void) {
        self.content = WinterSnowmanViewController(session: session, onMutation: onMutation, onComplete: onComplete, onExport: onExport)
        super.init(navigationBarPresentationData: nil)
        self.content.overrideUserInterfaceStyle = context.sharedContext.currentPresentationData.with { $0 }.theme.overallDarkAppearance ? .dark : .light
        self.content.onClose = { [weak self] in
            guard let self else { return }
            if let navigation = self.navigationController, navigation.viewControllers.contains(where: { $0 === self }) {
                let _ = navigation.popViewController(animated: true)
            } else { self.dismiss() }
        }
    }

    required init(coder: NSCoder) { preconditionFailure("init(coder:) has not been implemented") }

    func update(session: WinterSnowmanSession) { self.content.update(session: session) }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.addChild(self.content)
        self.displayNode.view.addSubview(self.content.view)
        self.content.didMove(toParent: self)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        transition.updateFrame(view: self.content.view, frame: CGRect(origin: .zero, size: layout.size))
    }
}
