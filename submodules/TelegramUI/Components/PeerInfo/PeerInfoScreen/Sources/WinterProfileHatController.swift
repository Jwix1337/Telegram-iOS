import UIKit
import AsyncDisplayKit
import Display
import AccountContext
import TelegramCore
import TelegramPresentationData
import SwiftSignalKit
import AvatarNode
import SnowEffect

/// Local profile decoration, deliberately separate from the owner's publication editor.
final class WinterProfileHatController: ViewController {
    private let context: AccountContext
    private let peer: EnginePeer
    // ContentNode contains the normal photo/initials without AvatarNode's saved hat overlay.
    private let avatar = AvatarNode.ContentNode(font: avatarPlaceholderFont(size: 64.0))
    private let peerDisposable = MetaDisposable()
    private var editor: SnowHatEditorViewController?

    init(context: AccountContext, peer: EnginePeer) {
        self.context = context
        self.peer = peer
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        self.peerDisposable.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .systemBackground
        let editor = SnowHatEditorViewController(accountID: self.context.account.peerId.toInt64(), peerID: self.peer.id.toInt64(), avatarPreviewView: self.avatar.view)
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        editor.overrideUserInterfaceStyle = presentationData.theme.overallDarkAppearance ? .dark : .light
        editor.avatarPreviewLayout = { [weak self] size in
            self?.avatar.updateSize(size: size)
        }
        editor.onClose = { [weak self] in
            guard let self else { return }
            if let navigationController = self.navigationController {
                let _ = navigationController.popViewController(animated: true)
            } else {
                self.dismiss()
            }
        }
        self.editor = editor
        self.addChild(editor)
        self.displayNode.view.addSubview(editor.view)
        editor.didMove(toParent: self)
        self.updateAvatar(self.peer)
        self.peerDisposable.set((self.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: self.peer.id))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            if let peer { self?.updateAvatar(peer) }
        }))
        self.displayNodeDidLoad()
    }

    private func updateAvatar(_ peer: EnginePeer) {
        let theme = self.context.sharedContext.currentPresentationData.with { $0 }.theme
        self.avatar.setPeer(context: self.context, theme: theme, peer: peer, displayDimensions: CGSize(width: 256.0, height: 256.0))
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        if let editor = self.editor {
            transition.updateFrame(view: editor.view, frame: CGRect(origin: .zero, size: layout.size))
        }
    }
}
