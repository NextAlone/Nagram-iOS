import Foundation
import Display
import TelegramCore
import AccountContext
import UndoUI
import NagramSettings
import NagramStrings

// MARK: NAGRAM — 本地置顶的操作入口（上下文菜单和左滑都走这里）。
// 只作用于「全部聊天」：服务端置顶满额时，开关打开就改为在本机置顶，否则仍是原生的 Premium 上限提示。

/// 设置打开时，该会话是否是「全部聊天」的本地置顶。
func nagramIsLocallyPinnedChat(context: AccountContext, peerId: EnginePeer.Id) -> Bool {
    guard NagramSettings.shared.localPinnedChatsEnabled else {
        return false
    }
    return NagramSettings.shared.isLocallyPinnedChat(peerId.toInt64(), accountPeerId: context.account.peerId.toInt64())
}

func nagramRemoveLocalPinnedChat(context: AccountContext, peerId: EnginePeer.Id) {
    NagramSettings.shared.removeLocalPinnedChat(peerId.toInt64(), accountPeerId: context.account.peerId.toInt64())
}

/// 服务端置顶满额时尝试本地置顶。返回 nil 表示不处理（开关关闭或不在「全部聊天」），调用方继续原生提示；
/// 否则返回要显示的提示控制器。
func nagramLocalPinOnLimitExceeded(context: AccountContext, location: TogglePeerChatPinnedLocation, itemId: EngineChatList.PinnedItem.Id) -> ViewController? {
    guard NagramSettings.shared.localPinnedChatsEnabled, case .group(.root) = location, case let .peer(peerId) = itemId else {
        return nil
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let lang = presentationData.strings.baseLanguageCode
    let text: String
    if NagramSettings.shared.addLocalPinnedChat(peerId.toInt64(), accountPeerId: context.account.peerId.toInt64()) {
        text = ngI18n("Nagram.LocalPinnedChats.Added", lang)
    } else {
        text = ngI18n("Nagram.LocalPinnedChats.LimitReached", lang).replacingOccurrences(of: "{limit}", with: "\(NagramSettings.localPinnedChatsLimit)")
    }
    return UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}
