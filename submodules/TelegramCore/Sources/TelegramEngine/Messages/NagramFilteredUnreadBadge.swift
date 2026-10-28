import Foundation
import Postbox
import SwiftSignalKit
import NagramSettings

// MARK: NAGRAM — 从桌面角标中扣除被消息屏蔽规则隐藏的未读消息。
public extension TelegramEngine.Messages {
    /// The unread messages (or, with `countsChats`, the chats whose every unread message is) that the
    /// regex message filters hide, among the chats the badge counts (`includeTags`).
    func nagramFilteredUnreadBadgeAdjustment(includeTags: EnginePeerSummaryCounterTags, countsChats: Bool) -> Signal<Int32, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> Int32 in
            let accountPeerId = account.peerId
            let seedConfiguration = account.postbox.seedConfiguration

            var unreadPeerIds = Set(transaction.getUnreadChatListPeerIds(groupId: .root, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))
            unreadPeerIds.formUnion(transaction.getUnreadChatListPeerIds(groupId: Namespaces.PeerGroup.archive, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))

            let globalNotificationSettings = transaction.getGlobalNotificationSettings()
            var hiddenMessageCount: Int32 = 0
            var hiddenChatCount: Int32 = 0

            for peerId in unreadPeerIds {
                guard let readState = transaction.getCombinedPeerReadState(peerId), readState.count > 0 else {
                    continue
                }
                guard let peer = transaction.getPeer(peerId) else {
                    continue
                }

                let peerTags = seedConfiguration.peerSummaryCounterTags(peer, transaction.isPeerContact(peerId: peerId))
                guard !peerTags.isDisjoint(with: includeTags) else {
                    continue
                }

                let notificationPeerId: PeerId
                if let associatedPeerId = peer.associatedPeerId, peer.associatedPeerOverridesIdentity {
                    notificationPeerId = associatedPeerId
                } else {
                    notificationPeerId = peerId
                }
                guard !resolvedIsRemovedFromTotalUnreadCount(globalSettings: globalNotificationSettings, peer: peer, peerSettings: transaction.getPeerNotificationSettings(id: notificationPeerId)) else {
                    continue
                }
                guard let matcher = NagramSettings.shared.regexFilterMatcher(peerId: peerId.toInt64(), isOutgoing: false) else {
                    continue
                }

                let historyView = transaction.getMessagesHistoryViewState(
                    input: .single(peerId: peerId, threadId: nil),
                    ignoreMessagesInTimestampRange: nil,
                    ignoreMessageIds: Set(),
                    count: Int(readState.count) + 10,
                    clipHoles: true,
                    anchor: .upperBound,
                    namespaces: .not(Namespaces.Message.allNonRegular)
                )
                var peerHiddenMessageCount: Int32 = 0
                for entry in historyView.entries {
                    let message = entry.message
                    guard !entry.isRead, message.id.peerId == peerId, message.effectivelyIncoming(accountPeerId) else {
                        continue
                    }
                    if matcher.isHidden(text: message.text, authorPeerId: message.author?.id.id._internalGetInt64Value()) {
                        peerHiddenMessageCount += 1
                    }
                }

                hiddenMessageCount += peerHiddenMessageCount
                if peerHiddenMessageCount >= readState.count {
                    hiddenChatCount += 1
                }
            }

            return countsChats ? hiddenChatCount : hiddenMessageCount
        }
    }
}
