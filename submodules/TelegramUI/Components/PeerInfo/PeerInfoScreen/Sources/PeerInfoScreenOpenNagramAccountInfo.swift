import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ContextUI
import UndoUI

extension PeerInfoScreenNode {
    func openNagramAccountInfoContextMenu(copyItems: [PeerInfoNagramAccountInfoCopyItem], node: ASDisplayNode, gesture: ContextGesture?) {
        guard let sourceNode = node as? ContextExtractedContentContainingNode else {
            return
        }
        guard !copyItems.isEmpty else {
            return
        }
        
        let copyAction: (String) -> Void = { [weak self] value in
            guard let self else {
                return
            }
            UIPasteboard.general.string = value
            
            self.controller?.present(UndoOverlayController(
                presentationData: self.presentationData,
                content: .copy(text: self.presentationData.strings.Conversation_TextCopied),
                elevatedLayout: false,
                animateInAsReplacement: false,
                action: { _ in return false }
            ), in: .current)
        }
        
        let items: [ContextMenuItem] = copyItems.map { copyItem in
            .action(ContextMenuActionItem(text: copyItem.title, icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
            }, action: { c, _ in
                c?.dismiss {
                    copyAction(copyItem.value)
                }
            }))
        }
        
        let actions = ContextController.Items(content: .list(items))
        let contextController = makeContextController(
            presentationData: self.presentationData,
            source: .extracted(PeerInfoContextExtractedContentSource(sourceNode: sourceNode)),
            items: .single(actions),
            gesture: gesture
        )
        self.controller?.present(contextController, in: .window(.root))
    }
}
