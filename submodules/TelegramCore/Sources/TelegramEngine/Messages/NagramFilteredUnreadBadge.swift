import Foundation
import Postbox
import SwiftSignalKit
import NagramSettings

// MARK: NAGRAM — 被消息屏蔽规则隐藏的未读消息：桌面角标扣除它们，“被过滤的消息自动已读”把只剩它们的聊天标为已读。

/// What the regex filters make of each unread chat's unread incoming messages, kept between scans so that a scan reads
/// only the chats that changed since the last one, and of those only the messages that are new. Both scans run on every
/// change of the unread counters, which a busy account sees about once a second; reading every unread message of every
/// unread chat each time held the Postbox queue for seconds, and opening a chat or switching folders waited behind it.
///
/// Touched only inside Postbox transactions, which run one at a time.
public final class NagramFilteredUnreadCache {
    struct Entry {
        let rulesIdentity: ObjectIdentifier
        let readState: CombinedPeerReadState
        let topIndex: MessageIndex?
        /// Each unread incoming message loaded from the chat's newest end, and whether the filters hide it.
        let unread: [MessageIndex: Bool]
    }

    var entries: [PeerId: Entry] = [:]
    /// History entries read from Postbox so far.
    var loadedEntryCount = 0

    public init() {
    }

    func prune(keeping peerIds: Set<PeerId>) {
        self.entries = self.entries.filter { peerIds.contains($0.key) }
    }
}

struct NagramFilteredUnreadSummary: Equatable {
    var hiddenCount: Int32 = 0
    var hasVisibleUnread = false
    var newestHiddenIndex: MessageIndex?
}

private enum NagramReadBoundaryChange {
    case same
    case advanced
    case other
}

/// How the incoming read boundary moved, ignoring the counts and `maxKnownId`.
private func nagramReadBoundaryChange(from old: CombinedPeerReadState, to new: CombinedPeerReadState) -> NagramReadBoundaryChange {
    guard old.states.count == new.states.count else {
        return .other
    }
    var advanced = false
    for (namespace, newState) in new.states {
        guard let oldState = old.states.first(where: { $0.0 == namespace })?.1 else {
            return .other
        }
        switch (oldState, newState) {
        case let (.idBased(oldMaxId, _, _, _, _), .idBased(newMaxId, _, _, _, _)):
            if newMaxId < oldMaxId {
                return .other
            }
            advanced = advanced || newMaxId > oldMaxId
        case let (.indexBased(oldMaxIndex, _, _, _), .indexBased(newMaxIndex, _, _, _)):
            if newMaxIndex < oldMaxIndex {
                return .other
            }
            advanced = advanced || newMaxIndex > oldMaxIndex
        default:
            return .other
        }
    }
    return advanced ? .advanced : .same
}

/// The unread incoming messages among the chat's newest `count`, only those newer than `after` when it is given. Nil
/// when `after` is given and the loaded messages do not reach back to it, since newer ones may then be missing.
private func nagramLoadUnread(transaction: Transaction, cache: NagramFilteredUnreadCache, peerId: PeerId, accountPeerId: PeerId, readState: CombinedPeerReadState, count: Int, after: MessageIndex?, isHidden: (Message) -> Bool) -> [MessageIndex: Bool]? {
    let historyView = transaction.getMessagesHistoryViewState(
        input: .single(peerId: peerId, threadId: nil),
        ignoreMessagesInTimestampRange: nil,
        ignoreMessageIds: Set(),
        count: count,
        clipHoles: true,
        anchor: .upperBound,
        namespaces: .not(Namespaces.Message.allNonRegular)
    )
    cache.loadedEntryCount += historyView.entries.count
    var reachedAfter = after == nil
    var result: [MessageIndex: Bool] = [:]
    for entry in historyView.entries {
        let message = entry.message
        if let after, message.index <= after {
            reachedAfter = true
            continue
        }
        // Not `entry.isRead`: a history view without read states leaves it false for every incoming message.
        guard message.id.peerId == peerId, message.effectivelyIncoming(accountPeerId), !readState.isIncomingMessageIndexRead(message.index) else {
            continue
        }
        result[message.index] = isHidden(message)
    }
    return reachedAfter ? result : nil
}

/// The cached messages brought up to date: those read since dropped, those newer than the cached top loaded. Nil when
/// the change cannot be followed that way (rules, a read boundary that moved back, a deleted message), which reloads
/// the chat.
private func nagramUpdatedUnread(entry: NagramFilteredUnreadCache.Entry, transaction: Transaction, cache: NagramFilteredUnreadCache, peerId: PeerId, accountPeerId: PeerId, readState: CombinedPeerReadState, topIndex: MessageIndex?, isHidden: (Message) -> Bool) -> [MessageIndex: Bool]? {
    guard let topIndex, let previousTopIndex = entry.topIndex, topIndex >= previousTopIndex else {
        return nil
    }
    switch nagramReadBoundaryChange(from: entry.readState, to: readState) {
    case .other:
        return nil
    case .same:
        if readState.count < entry.readState.count {
            return nil
        }
    case .advanced:
        break
    }
    var unread = entry.unread.filter { !readState.isIncomingMessageIndexRead($0.key) }
    if topIndex > previousTopIndex {
        let addedCount = max(0, Int(readState.count) - Int(entry.readState.count))
        guard let newer = nagramLoadUnread(transaction: transaction, cache: cache, peerId: peerId, accountPeerId: accountPeerId, readState: readState, count: addedCount + 10, after: previousTopIndex, isHidden: isHidden) else {
            return nil
        }
        unread.merge(newer, uniquingKeysWith: { _, new in new })
    }
    return unread
}

/// The chat's unread incoming messages as the filters see them, from the cache where the chat has not changed since the
/// last scan; `reload` reads them all again.
func _internal_nagramFilteredUnreadSummary(transaction: Transaction, cache: NagramFilteredUnreadCache, peerId: PeerId, accountPeerId: PeerId, readState: CombinedPeerReadState, rulesIdentity: ObjectIdentifier, reload: Bool, isHidden: (Message) -> Bool) -> NagramFilteredUnreadSummary {
    let topIndex = transaction.getTopPeerMessageIndex(peerId: peerId)
    var unread: [MessageIndex: Bool]?
    if !reload, let entry = cache.entries[peerId], entry.rulesIdentity == rulesIdentity {
        if entry.readState == readState && entry.topIndex == topIndex {
            unread = entry.unread
        } else {
            unread = nagramUpdatedUnread(entry: entry, transaction: transaction, cache: cache, peerId: peerId, accountPeerId: accountPeerId, readState: readState, topIndex: topIndex, isHidden: isHidden)
        }
    }
    let resolvedUnread = unread ?? nagramLoadUnread(transaction: transaction, cache: cache, peerId: peerId, accountPeerId: accountPeerId, readState: readState, count: Int(readState.count) + 10, after: nil, isHidden: isHidden) ?? [:]
    cache.entries[peerId] = NagramFilteredUnreadCache.Entry(rulesIdentity: rulesIdentity, readState: readState, topIndex: topIndex, unread: resolvedUnread)

    var summary = NagramFilteredUnreadSummary()
    for (index, hidden) in resolvedUnread {
        if hidden {
            summary.hiddenCount += 1
            if summary.newestHiddenIndex.flatMap({ $0 < index }) ?? true {
                summary.newestHiddenIndex = index
            }
        } else {
            summary.hasVisibleUnread = true
        }
    }
    return summary
}

private func nagramUnreadPeerIds(transaction: Transaction) -> Set<PeerId> {
    var unreadPeerIds = Set(transaction.getUnreadChatListPeerIds(groupId: .root, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))
    unreadPeerIds.formUnion(transaction.getUnreadChatListPeerIds(groupId: Namespaces.PeerGroup.archive, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))
    return unreadPeerIds
}

private func nagramIsHidden(_ matcher: NagramRegexFilterMatcher) -> (Message) -> Bool {
    return { message in
        return matcher.isHidden(text: message.text, authorPeerId: message.author?.id.id._internalGetInt64Value())
    }
}

public extension TelegramEngine.Messages {
    /// The unread messages (or, with `countsChats`, the chats whose every unread message is) that the
    /// regex message filters hide, among the chats the badge counts (`includeTags`).
    func nagramFilteredUnreadBadgeAdjustment(cache: NagramFilteredUnreadCache, includeTags: EnginePeerSummaryCounterTags, countsChats: Bool) -> Signal<Int32, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> Int32 in
            let accountPeerId = account.peerId
            let seedConfiguration = account.postbox.seedConfiguration

            let unreadPeerIds = nagramUnreadPeerIds(transaction: transaction)
            cache.prune(keeping: unreadPeerIds)

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

                let summary = _internal_nagramFilteredUnreadSummary(transaction: transaction, cache: cache, peerId: peerId, accountPeerId: accountPeerId, readState: readState, rulesIdentity: matcher.identity, reload: false, isHidden: nagramIsHidden(matcher))
                hiddenMessageCount += summary.hiddenCount
                if summary.hiddenCount >= readState.count {
                    hiddenChatCount += 1
                }
            }

            return countsChats ? hiddenChatCount : hiddenMessageCount
        }
    }

    /// MARK: NAGRAM — Marks as read the chats whose every unread incoming message the regex filters hide, through
    /// the same interactive read path as opening the chat, so the server and other devices see it too. A chat is
    /// skipped unless all of its unread messages were loaded and hidden (a hole, a visible unread message, a chat
    /// marked unread by hand, a forum) — the cost of a mistake is a real message the user never sees, so a chat the
    /// cache finds fully hidden is read again from Postbox before it is marked.
    func nagramMarkFullyFilteredChatsAsRead(cache: NagramFilteredUnreadCache) -> Signal<Int, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> Int in
            let accountPeerId = account.peerId

            let unreadPeerIds = nagramUnreadPeerIds(transaction: transaction)
            cache.prune(keeping: unreadPeerIds)

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

                let isFullyHidden: (NagramFilteredUnreadSummary) -> Bool = { summary in
                    return !summary.hasVisibleUnread && summary.hiddenCount >= readState.count && summary.newestHiddenIndex != nil
                }
                let cached = _internal_nagramFilteredUnreadSummary(transaction: transaction, cache: cache, peerId: peerId, accountPeerId: accountPeerId, readState: readState, rulesIdentity: matcher.identity, reload: false, isHidden: nagramIsHidden(matcher))
                guard isFullyHidden(cached) else {
                    continue
                }
                let verified = _internal_nagramFilteredUnreadSummary(transaction: transaction, cache: cache, peerId: peerId, accountPeerId: accountPeerId, readState: readState, rulesIdentity: matcher.identity, reload: true, isHidden: nagramIsHidden(matcher))
                guard isFullyHidden(verified), let newestHiddenIndex = verified.newestHiddenIndex else {
                    continue
                }
                _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: account.stateManager, index: newestHiddenIndex)
                markedChatCount += 1
            }
            return markedChatCount
        }
    }
}
