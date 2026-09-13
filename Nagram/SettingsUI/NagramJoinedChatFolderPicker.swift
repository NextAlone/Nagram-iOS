import AccountContext
import Display
import NagramSettings
import NagramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

public func nagramPresentFolderPickerAfterJoining(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void) {
    guard NagramSettings.shared.chooseFolderAfterJoining else {
        return
    }
    let _ = (combineLatest(
        context.engine.peers.updatedChatListFilters() |> take(1),
        context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId),
            TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: false),
            TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: true)
        )
    ) |> deliverOnMainQueue).startStandalone(next: { filters, limits in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let limit = Int(limits.0?.isPremium == true ? limits.2.maxFolderChatsCount : limits.1.maxFolderChatsCount)
        let controller = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: presentationData.strings.ChatList_Context_AddToFolder)]
        for filter in filters {
            guard case let .filter(id, title, _, data) = filter, !data.includePeers.peers.contains(peerId) else {
                continue
            }
            items.append(ActionSheetButtonItem(title: title.text, color: .accent, action: { [weak controller] in
                controller?.dismissAnimated()
                let _ = (context.engine.peers.updateChatListFiltersInteractively { current in
                    return current.map { filter in
                        guard case let .filter(currentId, title, emoticon, data) = filter, currentId == id else {
                            return filter
                        }
                        var updatedData = data
                        guard updatedData.includePeers.peers.contains(peerId) || updatedData.includePeers.peers.count < limit else {
                            return filter
                        }
                        let _ = updatedData.addIncludePeer(peerId: peerId)
                        return .filter(id: currentId, title: title, emoticon: emoticon, data: updatedData)
                    }
                } |> deliverOnMainQueue).startStandalone(next: { updated in
                    let added = updated.contains { filter in
                        if case let .filter(currentId, _, _, data) = filter, currentId == id {
                            return data.includePeers.peers.contains(peerId)
                        }
                        return false
                    }
                    if !added {
                        let alert = ActionSheetController(presentationData: presentationData)
                        alert.setItemGroups([ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: ngI18n("Nagram.JoinedChatFolderUnavailable", lang)),
                            ActionSheetButtonItem(title: presentationData.strings.Common_OK, color: .accent, action: { [weak alert] in
                                alert?.dismissAnimated()
                            })
                        ])])
                        present(alert)
                    }
                })
            }))
        }
        guard items.count > 1 else {
            return
        }
        controller.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak controller] in
                controller?.dismissAnimated()
            })])
        ])
        present(controller)
    })
}
