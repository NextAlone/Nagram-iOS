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

    /// MARK: NAGRAM — Marks as read the chats whose every unread incoming message the regex filters hide, through
    /// the same interactive read path as opening the chat, so the server and other devices see it too. A chat is
    /// skipped unless all of its unread messages were loaded and hidden (a hole, a visible unread message, a chat
    /// marked unread by hand, a forum) — the cost of a mistake is a real message the user never sees.
    func nagramMarkFullyFilteredChatsAsRead() -> Signal<Int, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> Int in
            let accountPeerId = account.peerId

            var unreadPeerIds = Set(transaction.getUnreadChatListPeerIds(groupId: .root, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))
            unreadPeerIds.formUnion(transaction.getUnreadChatListPeerIds(groupId: Namespaces.PeerGroup.archive, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))

            var markedChatCount = 0
            for peerId in unreadPeerIds {
                guard let readState = transaction.getCombinedPeerReadState(peerId), readState.count > 0, !readState.markedUnread else {
                    continue
                }
                guard let peer = transaction.getPeer(peerId), !peer.isForumOrMonoForum else {
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
                var hiddenUnreadCount: Int32 = 0
                var newestHiddenIndex: MessageIndex?
                var hasVisibleUnread = false
                for entry in historyView.entries {
                    let message = entry.message
                    guard !entry.isRead, message.id.peerId == peerId, message.effectivelyIncoming(accountPeerId) else {
                        continue
                    }
                    guard matcher.isHidden(text: message.text, authorPeerId: message.author?.id.id._internalGetInt64Value()) else {
                        hasVisibleUnread = true
                        break
                    }
                    hiddenUnreadCount += 1
                    if let current = newestHiddenIndex {
                        if current < message.index {
                            newestHiddenIndex = message.index
                        }
                    } else {
                        newestHiddenIndex = message.index
                    }
                }
                guard !hasVisibleUnread, hiddenUnreadCount >= readState.count, let newestHiddenIndex else {
                    continue
                }
                _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: account.stateManager, index: newestHiddenIndex)
                markedChatCount += 1
            }
            return markedChatCount
        }
    }
}
