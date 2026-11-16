import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AlertUI
import PresentationDataUtils
import AccountContext
import SnowEffect
import AvatarNode

/// Publishing is an ordinary visible message. Every recipient and every update requires confirmation.
func snowHatPublishingController(context: AccountContext, configuration: SnowHatConfiguration) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let russian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
    let picker = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
        context: context,
        filter: [.onlyWriteable, .onlyPrivateChats, .excludeSecretChats, .excludeBots, .excludeSavedMessages, .doNotSearchMessages],
        title: russian ? "Опубликовать шапку" : "Publish Hat"
    ))
    picker.peerSelected = { [weak picker] peer, _ in
        guard let picker, !picker.inProgress, case let .user(user) = peer, user.botInfo == nil,
              peer.id.namespace == Namespaces.Peer.CloudUser,
              configuration.ownerID == context.account.peerId.toInt64() else {
            return
        }
        let name = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        let serverMode = WinterSyncHub.shared.owns(accountID: context.account.peerId.toInt64(), peerID: peer.id.toInt64())
        let explanation = serverMode ? (russian ? "Опубликовать шапку через подключённую пару Winter Sync? Техническое сообщение Telegram не отправляется. При сбое сервиса публикация останется в очереди." : "Publish via the paired Winter Sync service? No technical Telegram message is sent. Offline publications remain queued.") : russian
            ? "В чат с \(name) будет отправлен 🎄 со ссылкой, содержащей настройки шапки. Совместимый Telegram Snow покажет её на вашей аватарке. Каждое изменение и отключение нужно опубликовать снова. Отправить?"
            : "A visible 🎄 link containing your hat settings will be sent to \(name). A compatible Telegram Snow client will display it on your avatar. Publish again after every change or when disabling your hat. Send?"
        picker.present(textAlertController(context: context, title: russian ? "Сохранить и опубликовать" : "Save and Publish", text: explanation, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: russian ? "Подтвердить публикацию" : "Confirm Publish", action: { [weak picker] in
                guard let picker, !picker.inProgress else { return }
                var published = configuration
                // Re-publication is a new update, bound to this message's server timestamp.
                let accountID = context.account.peerId.toInt64()
                let previous = SnowHatStore.shared.configuration(accountID: accountID, peerID: accountID)?.modifiedAt ?? 0
                published.modifiedAt = max(Int64(Date().timeIntervalSince1970 * 1000.0), previous < Int64.max ? previous + 1 : previous)
                guard let event = WinterEventTransport.shared.makeEvent(type: .hat, accountID: accountID, peerID: peer.id.toInt64(), hat: published),
                      WinterEventTransport.shared.recordOutgoing(event, accountID: accountID) else {
                    return
                }
                // The account bridge drains this explicitly confirmed durable outbox.
                // It is shared with snowballs/snowmen; no second sender is started here.
                picker.dismiss()

            })
        ]), in: .window(.root))
    }
    return picker
}

/// Hosts the UIKit editor in Telegram's existing navigation/layout system.
private final class SnowHatEditorHostController: ViewController {
    private let context: AccountContext
    private var editor: SnowHatEditorViewController?
    private let previewAvatar = AvatarNode(font: avatarPlaceholderFont(size: 96.0))
    private let avatarDisposable = MetaDisposable()

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        self.avatarDisposable.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .systemBackground
        let editor = SnowHatEditorViewController(accountID: self.context.account.peerId.toInt64(), avatarImage: nil, onPublish: { [weak self] configuration in
            guard let self else { return }
            let picker = snowHatPublishingController(context: self.context, configuration: configuration)
            if let navigationController = self.navigationController as? NavigationController {
                navigationController.pushViewController(picker)
            } else {
                self.present(picker, in: .window(.root))
            }
        })
        editor.overrideUserInterfaceStyle = self.context.sharedContext.currentPresentationData.with { $0 }.theme.overallDarkAppearance ? .dark : .light
        editor.onClose = { [weak self] in
            guard let self else { return }
            if let navigationController = self.navigationController,
               navigationController.viewControllers.contains(where: { $0 === self }) {
                let _ = navigationController.popViewController(animated: true)
            } else {
                self.dismiss()
            }
        }
        self.editor = editor
        // Reuse the normal avatar loader. Only its original photo is copied to the
        // editor; the decoration itself remains a separate transparent overlay.
        self.previewAvatar.frame = CGRect(x: 0.0, y: 0.0, width: 256.0, height: 256.0)
        self.previewAvatar.alpha = 0.0
        self.previewAvatar.isUserInteractionEnabled = false
        let previousImageUpdated = self.previewAvatar.imageNode.contentUpdated
        self.previewAvatar.imageNode.contentUpdated = { [weak editor] image in
            previousImageUpdated?(image)
            DispatchQueue.main.async { [weak editor] in editor?.updateAvatarImage(image) }
        }
        self.displayNode.addSubnode(self.previewAvatar)
        self.addChild(editor)
        self.displayNode.view.addSubview(editor.view)
        editor.didMove(toParent: self)
        self.avatarDisposable.set((self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.context.account.peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else { return }
            let theme = self.context.sharedContext.currentPresentationData.with { $0 }.theme
            self.previewAvatar.setPeer(context: self.context, theme: theme, peer: peer, displayDimensions: CGSize(width: 256.0, height: 256.0), storeUnrounded: true)
        }))
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        if let editor = self.editor {
            transition.updateFrame(view: editor.view, frame: CGRect(origin: .zero, size: layout.size))
        }
    }
}

func snowHatEditorController(context: AccountContext) -> ViewController {
    return SnowHatEditorHostController(context: context)
}
