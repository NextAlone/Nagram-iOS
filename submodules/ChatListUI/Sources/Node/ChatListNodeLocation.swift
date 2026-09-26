import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import TelegramUIPreferences
import AccountContext
import NagramSettings // MARK: NAGRAM

public enum ChatListNodeLocation: Equatable {
    case initial(count: Int, filter: ChatListFilter?)
    case navigation(index: EngineChatList.Item.Index, filter: ChatListFilter?)
    case scroll(index: EngineChatList.Item.Index, sourceIndex: EngineChatList.Item.Index, scrollPosition: ListViewScrollPosition, animated: Bool, filter: ChatListFilter?)
    
    public var filter: ChatListFilter? {
        switch self {
        case let .initial(_, filter):
            return filter
        case let .navigation(_, filter):
            return filter
        case let .scroll(_, _, _, _, filter):
            return filter
        }
    }
}

public struct ChatListNodeViewUpdate {
    public let list: EngineChatList
    public let type: ViewUpdateType
    public let scrollPosition: ChatListNodeViewScrollPosition?
    
    public init(list: EngineChatList, type: ViewUpdateType, scrollPosition: ChatListNodeViewScrollPosition?) {
        self.list = list
        self.type = type
        self.scrollPosition = scrollPosition
    }
}

private func communityPeerId(item: EngineChatList.Item) -> EnginePeer.Id? {
    guard case let .chatList(peerId) = item.id else {
        return nil
    }
    if let peer = item.renderedPeer.peer, case let .community(community) = peer, community.collapsedInDialogs == true {
        return peerId
    } else {
        return nil
    }
}

private func filteredCommunityChatListItems(_ items: [EngineChatList.Item]) -> [EngineChatList.Item] {
    return items.filter { item in
        if let peer = item.renderedPeer.peer, case let .community(community) = peer {
            return community.collapsedInDialogs == true && !NagramSettings.shared.disableCommunityChatGrouping // MARK: NAGRAM — 本地强制拆分 Community 会话
        } else {
            return true
        }
    }
}

private func chatListNodeViewUpdateWithCommunitySummaries(account: Account, update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
    let baseItems = filteredCommunityChatListItems(update.list.items)
    let baseList = EngineChatList(
        items: baseItems,
        groupItems: update.list.groupItems,
        additionalItems: update.list.additionalItems,
        hasEarlier: update.list.hasEarlier,
        hasLater: update.list.hasLater,
        isLoading: update.list.isLoading
    )
    let baseUpdate = ChatListNodeViewUpdate(list: baseList, type: update.type, scrollPosition: update.scrollPosition)

    let communityIds = baseItems.compactMap { item in
        return communityPeerId(item: item)
    }
    if communityIds.isEmpty {
        return .single(baseUpdate)
    }

    var isFirstSummary = true
    return communityChatListItemSummaries(postbox: account.postbox, communityIds: communityIds)
    |> map { summaries -> ChatListNodeViewUpdate in
        let updatedType: ViewUpdateType
        let updatedScrollPosition: ChatListNodeViewScrollPosition?
        if isFirstSummary {
            updatedType = update.type
            updatedScrollPosition = update.scrollPosition
            isFirstSummary = false
        } else {
            updatedType = .Generic
            updatedScrollPosition = nil
        }

        let items = baseItems.map { item -> EngineChatList.Item in
            guard let communityId = communityPeerId(item: item), let summary = summaries[communityId], summary.hasLinkedPeers else {
                return item
            }
            let messages = summary.topMessage.map { [$0] } ?? item.messages
            return item.withUpdatedCommunitySummary(messages: messages, readCounters: summary.readCounters ?? item.readCounters)
        }

        let list = EngineChatList(
            items: items,
            groupItems: baseList.groupItems,
            additionalItems: baseList.additionalItems,
            hasEarlier: baseList.hasEarlier,
            hasLater: baseList.hasLater,
            isLoading: baseList.isLoading
        )
        return ChatListNodeViewUpdate(list: list, type: updatedType, scrollPosition: updatedScrollPosition)
    }
}

// MARK: NAGRAM — 最新一组消息全部命中 hide 时，使用本地历史中最近的未隐藏消息作为列表预览。
func nagramChatListNodeViewUpdateWithPreviousUnhiddenMessages(account: Account, update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
    struct Target {
        let itemIndex: Int
        let peerId: EnginePeer.Id
        let threadId: Int64?
        let upperBound: EngineMessage.Index
    }

    var targets: [Target] = []
    for (itemIndex, item) in update.list.items.enumerated() {
        guard item.draft == nil, item.mediaDraftContentType == nil, let firstMessage = item.messages.min(by: { $0.index < $1.index }) else {
            continue
        }

        let peerId: EnginePeer.Id
        if let peer = item.renderedPeer.peer, case .community = peer, let messagePeerId = item.messages.last?.id.peerId {
            peerId = messagePeerId
        } else if case let .chatList(index) = item.index {
            peerId = index.messageIndex.id.peerId
        } else if let messagePeerId = item.messages.last?.id.peerId {
            peerId = messagePeerId
        } else {
            continue
        }

        guard item.messages.allSatisfy({ message in
            return nagramChatListMessageIsHidden(message, peerId: peerId, accountPeerId: account.peerId)
        }) else {
            continue
        }

        let threadId: Int64?
        if case let .forum(_, _, value, _, _) = item.index {
            threadId = value
        } else {
            threadId = nil
        }
        targets.append(Target(itemIndex: itemIndex, peerId: peerId, threadId: threadId, upperBound: firstMessage.index))
    }

    if targets.isEmpty {
        return .single(update)
    }

    return account.postbox.transaction { transaction -> [Int: EngineMessage] in
        var result: [Int: EngineMessage] = [:]
        for target in targets {
            let historyView = transaction.getMessagesHistoryViewState(
                input: .single(peerId: target.peerId, threadId: target.threadId),
                ignoreMessagesInTimestampRange: nil,
                ignoreMessageIds: Set(),
                count: 100,
                clipHoles: true,
                anchor: .index(target.upperBound),
                namespaces: .not(Namespaces.Message.allNonRegular)
            )
            for entry in historyView.entries.reversed() {
                let message = EngineMessage(entry.message)
                guard message.index < target.upperBound else {
                    continue
                }
                if !nagramChatListMessageIsHidden(message, peerId: target.peerId, accountPeerId: account.peerId) {
                    result[target.itemIndex] = message
                    break
                }
            }
        }
        return result
    }
    |> map { messagesByItemIndex -> ChatListNodeViewUpdate in
        if messagesByItemIndex.isEmpty {
            return update
        }
        let items = update.list.items.enumerated().map { itemIndex, item -> EngineChatList.Item in
            guard let message = messagesByItemIndex[itemIndex] else {
                return item
            }
            // MARK: NAGRAM — 保留隐藏的最新消息供 ChatListNodeEntries 计算未读角标；
            // 随后现有过滤逻辑会移除它们，只留下回退消息作为预览。
            return item.withUpdatedCommunitySummary(messages: item.messages + [message], readCounters: item.readCounters)
        }
        return ChatListNodeViewUpdate(
            list: EngineChatList(
                items: items,
                groupItems: update.list.groupItems,
                additionalItems: update.list.additionalItems,
                hasEarlier: update.list.hasEarlier,
                hasLater: update.list.hasLater,
                isLoading: update.list.isLoading
            ),
            type: update.type,
            scrollPosition: update.scrollPosition
        )
    }
}

public func chatListFilterPredicate(filter: ChatListFilterData, accountPeerId: EnginePeer.Id, includeRecentPeerIds: Set<EnginePeer.Id> = Set()) -> ChatListFilterPredicate {
    var includePeers = Set(filter.includePeers.peers)
    var excludePeers = Set(filter.excludePeers)
    includePeers.formUnion(includeRecentPeerIds) // MARK: NAGRAM
    
    if !filter.includePeers.pinnedPeers.isEmpty {
        includePeers.subtract(filter.includePeers.pinnedPeers)
        excludePeers.subtract(filter.includePeers.pinnedPeers)
    }
    
    var includeAdditionalPeerGroupIds: [PeerGroupId] = []
    if !filter.excludeArchived {
        includeAdditionalPeerGroupIds.append(Namespaces.PeerGroup.archive)
    }
    
    var messageTagSummary: ChatListMessageTagSummaryResultCalculation?
    if filter.excludeRead || filter.excludeMuted {
        messageTagSummary = ChatListMessageTagSummaryResultCalculation(addCount: ChatListMessageTagSummaryResultComponent(tag: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud), subtractCount: ChatListMessageTagActionsSummaryResultComponent(type: PendingMessageActionType.consumeUnseenPersonalMessage, namespace: Namespaces.Message.Cloud))
    }
    return ChatListFilterPredicate(includePeerIds: includePeers, excludePeerIds: excludePeers, pinnedPeerIds: filter.includePeers.pinnedPeers, messageTagSummary: messageTagSummary, includeAdditionalPeerGroupIds: includeAdditionalPeerGroupIds, include: { peer, isMuted, isUnread, isContact, messageTagSummaryResult in
        if filter.excludeRead {
            var effectiveUnread = isUnread
            if let messageTagSummaryResult = messageTagSummaryResult, messageTagSummaryResult {
                effectiveUnread = true
            }
            if !effectiveUnread {
                return false
            }
        }
        if filter.excludeMuted {
            if isMuted {
                if let messageTagSummaryResult = messageTagSummaryResult, messageTagSummaryResult {
                } else {
                    return false
                }
            }
        }
        if !includeRecentPeerIds.isEmpty {
            var effectivePeerId = peer.id
            if let associatedPeerId = peer.associatedPeerId, peer.associatedPeerOverridesIdentity {
                effectivePeerId = associatedPeerId
            }
            if includeRecentPeerIds.contains(peer.id) || includeRecentPeerIds.contains(effectivePeerId) {
                return true
            }
        }
        if !filter.categories.contains(.contacts) && isContact {
            if let user = peer as? TelegramUser {
                if user.botInfo == nil && !user.flags.contains(.isSupport) {
                    return false
                }
            } else if let _ = peer as? TelegramSecretChat {
                return false
            }
        }
        if !filter.categories.contains(.nonContacts) && (!isContact && peer.id != accountPeerId) {
            if let user = peer as? TelegramUser {
                if user.botInfo == nil {
                    return false
                }
            } else if let _ = peer as? TelegramSecretChat {
                return false
            }
        }
        if filter.categories.contains(.nonContacts) && peer.id == accountPeerId {
            return false
        }
        if !filter.categories.contains(.bots) {
            if let user = peer as? TelegramUser {
                if user.botInfo != nil || user.flags.contains(.isSupport) {
                    return false
                }
            }
        }
        if !filter.categories.contains(.groups) {
            if let _ = peer as? TelegramGroup {
                return false
            } else if let channel = peer as? TelegramChannel {
                if case .group = channel.info {
                    return false
                }
            } else if let _ = peer as? TelegramCommunity {
                return false
            }
        }
        if !filter.categories.contains(.channels) {
            if let channel = peer as? TelegramChannel {
                if case .broadcast = channel.info {
                    return false
                }
            }
        }
        return true
    })
}

// MARK: NAGRAM — 最近会话文件夹同时匹配已折叠的聚合容器。
public func nagramChatListFilterRecentPeerIds(accountPeerId: EnginePeer.Id, filterId: Int32) -> Set<EnginePeer.Id> {
    let accountPeerIdValue = accountPeerId.toInt64()
    guard NagramSettings.shared.isRecentChatFolderEnabled(accountPeerId: accountPeerIdValue, filterId: filterId)
    else {
        return Set()
    }
    return Set(NagramSettings.shared.recentChatFilterPeerIds(accountPeerId: accountPeerIdValue).map(EnginePeer.Id.init))
}

private func nagramResolveRecentChatContainerPeerIds(account: Account, filterId: Int32) -> Signal<Set<EnginePeer.Id>, NoError> {
    let accountPeerId = account.peerId.toInt64()
    guard NagramSettings.shared.isRecentChatFolderEnabled(accountPeerId: accountPeerId, filterId: filterId) else {
        return .single(Set())
    }
    let recentChatIds = NagramSettings.shared.recentChatIds(accountPeerId: accountPeerId)
    return account.postbox.transaction { transaction -> ([Int64: Int64], Set<Int64>) in
        var containerPeerIds: [Int64: Int64] = [:]
        var resolvedPeerIds = Set<Int64>()
        for recentChatId in recentChatIds {
            let peerId = EnginePeer.Id(recentChatId)
            guard let peer = transaction.getPeer(peerId) else {
                continue
            }
            guard let containerPeerId = peer.containerPeerId else {
                resolvedPeerIds.insert(recentChatId)
                continue
            }
            guard let community = transaction.getPeer(containerPeerId) as? TelegramCommunity else {
                continue
            }
            resolvedPeerIds.insert(recentChatId)
            if community.collapsedInDialogs == true {
                containerPeerIds[recentChatId] = containerPeerId.toInt64()
            }
        }
        return (containerPeerIds, resolvedPeerIds)
    }
    |> deliverOnMainQueue
    |> map { containerPeerIds, resolvedPeerIds -> Set<EnginePeer.Id> in
        NagramSettings.shared.updateRecentChatContainerPeerIds(containerPeerIds, resolvedPeerIds: resolvedPeerIds, accountPeerId: accountPeerId)
        return nagramChatListFilterRecentPeerIds(accountPeerId: account.peerId, filterId: filterId)
    }
}

private func nagramRecentChatsFilterUpdates(accountPeerId: Int64, filterId: Int32) -> Signal<Void, NoError> {
    let initial = Signal<Void, NoError>.single(Void())
    let changes = Signal<Void, NoError> { subscriber in
        let recentChatsObserver = NotificationCenter.default.addObserver(forName: .nagramRecentChatsDidChange, object: nil, queue: .main) { notification in
            if let updatedAccountPeerId = notification.userInfo?["accountPeerId"] as? Int64, updatedAccountPeerId == accountPeerId {
                subscriber.putNext(Void())
            }
        }
        let folderSettingsObserver = NotificationCenter.default.addObserver(forName: .nagramRecentChatFolderSettingsDidChange, object: nil, queue: .main) { notification in
            if let updatedAccountPeerId = notification.userInfo?["accountPeerId"] as? Int64, updatedAccountPeerId == accountPeerId,
               let updatedFilterId = notification.userInfo?["filterId"] as? Int32,
               updatedFilterId == filterId {
                subscriber.putNext(Void())
            }
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(recentChatsObserver)
            NotificationCenter.default.removeObserver(folderSettingsObserver)
        }
    }
    return initial |> then(changes)
}

public func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListNodeLocation, account: Account, shouldLoadCanMessagePeer: Bool) -> Signal<ChatListNodeViewUpdate, NoError> {
    let accountPeerId = account.peerId
    
    switch chatListLocation {
    case let .chatList(groupId):
        let filterPredicate: Signal<ChatListFilterPredicate?, NoError>
        if let filter = location.filter, case let .filter(id, _, _, data) = filter {
            let nagramAccountPeerId = account.peerId.toInt64()
            filterPredicate = nagramRecentChatsFilterUpdates(accountPeerId: nagramAccountPeerId, filterId: id)
            |> mapToSignal { _ -> Signal<ChatListFilterPredicate?, NoError> in
                return nagramResolveRecentChatContainerPeerIds(account: account, filterId: id)
                |> map { includeRecentPeerIds -> ChatListFilterPredicate? in
                    return chatListFilterPredicate(filter: data, accountPeerId: account.peerId, includeRecentPeerIds: includeRecentPeerIds)
                }
            }
        } else {
            filterPredicate = .single(nil)
        }
        
        switch location {
        case let .initial(count, _):
            return filterPredicate
            |> mapToSignal { filterPredicate -> Signal<ChatListNodeViewUpdate, NoError> in
                let signal: Signal<(ChatListView, ViewUpdateType), NoError>
                signal = account.viewTracker.tailChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, count: count, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
                return signal
                |> map { view, updateType -> ChatListNodeViewUpdate in
                    return ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: accountPeerId), type: updateType, scrollPosition: nil)
                }
            }
            |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: update)
            }
        case let .navigation(index, _):
            guard case let .chatList(index) = index else {
                return .never()
            }
            return filterPredicate
            |> mapToSignal { filterPredicate -> Signal<ChatListNodeViewUpdate, NoError> in
                var first = true
                return account.viewTracker.aroundChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, index: index, count: 80, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
                |> map { view, updateType -> ChatListNodeViewUpdate in
                    let genericType: ViewUpdateType
                    if first {
                        first = false
                        genericType = ViewUpdateType.UpdateVisible
                    } else {
                        genericType = updateType
                    }
                    return ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: accountPeerId), type: genericType, scrollPosition: nil)
                }
            }
            |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: update)
            }
        case let .scroll(index, sourceIndex, scrollPosition, animated, _):
            guard case let .chatList(index) = index else {
                return .never()
            }
            
            let directionHint: ListViewScrollToItemDirectionHint = sourceIndex > .chatList(index) ? .Down : .Up
            let chatScrollPosition: ChatListNodeViewScrollPosition = .index(index: index, position: scrollPosition, directionHint: directionHint, animated: animated)
            return filterPredicate
            |> mapToSignal { filterPredicate -> Signal<ChatListNodeViewUpdate, NoError> in
                var first = true
                return account.viewTracker.aroundChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, index: index, count: 80, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
                |> map { view, updateType -> ChatListNodeViewUpdate in
                    let genericType: ViewUpdateType
                    let scrollPosition: ChatListNodeViewScrollPosition? = first ? chatScrollPosition : nil
                    if first {
                        first = false
                        genericType = ViewUpdateType.UpdateVisible
                    } else {
                        genericType = updateType
                    }
                    return ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: accountPeerId), type: genericType, scrollPosition: scrollPosition)
                }
            }
            |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: update)
            }
        }
    case let .forum(peerId):
        let viewKey: PostboxViewKey = .messageHistoryThreadIndex(
            id: peerId,
            summaryComponents: ChatListEntrySummaryComponents(
                components: [
                    ChatListEntryMessageTagSummaryKey(
                        tag: .unseenPersonalMessage,
                        actionType: PendingMessageActionType.consumeUnseenPersonalMessage
                    ): ChatListEntrySummaryComponents.Component(
                        tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                        actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                    ),
                    ChatListEntryMessageTagSummaryKey(
                        tag: .unseenReaction,
                        actionType: PendingMessageActionType.readReactionOrPollVote
                    ): ChatListEntrySummaryComponents.Component(
                        tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                        actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                    ),
                    ChatListEntryMessageTagSummaryKey(
                        tag: .unseenPollVote,
                        actionType: PendingMessageActionType.readReactionOrPollVote
                    ): ChatListEntrySummaryComponents.Component(
                        tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                        actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                    )
                ]
            )
        )
        
        let readStateKey: PostboxViewKey = .combinedReadState(peerId: peerId, handleThreads: false)
        
        var isFirst = false
        return account.postbox.combinedView(keys: [viewKey, readStateKey])
        |> map { views -> ChatListNodeViewUpdate in
            guard let view = views.views[viewKey] as? MessageHistoryThreadIndexView else {
                preconditionFailure()
            }
            guard let readStateView = views.views[readStateKey] as? CombinedReadStateView else {
                preconditionFailure()
            }
            
            var maxReadId: Int32 = 0
            if let state = readStateView.state?.states.first(where: { $0.0 == Namespaces.Message.Cloud }) {
                if case let .idBased(maxIncomingReadId, _, _, _, _) = state.1 {
                    maxReadId = maxIncomingReadId
                }
            }
            
            var items: [EngineChatList.Item] = []
            for item in view.items {
                guard let peer = view.peer else {
                    continue
                }
                guard let data = item.info.get(MessageHistoryThreadData.self) else {
                    continue
                }
                
                let defaultPeerNotificationSettings: TelegramPeerNotificationSettings = (view.peerNotificationSettings as? TelegramPeerNotificationSettings) ?? .defaultSettings
                
                var hasUnseenMentions = false
                
                var isMuted = false
                switch data.notificationSettings.muteState {
                case .muted:
                    isMuted = true
                case .unmuted:
                    isMuted = false
                case .default:
                    if case .default = data.notificationSettings.muteState {
                        if case .muted = defaultPeerNotificationSettings.muteState {
                            isMuted = true
                        }
                    }
                }
                
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenPersonalMessage,
                    actionType: PendingMessageActionType.consumeUnseenPersonalMessage
                )] {
                    hasUnseenMentions = (info.tagSummaryCount ?? 0) > (info.actionsSummaryCount ?? 0)
                }
                
                var hasUnseenReactions = false
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenReaction,
                    actionType: PendingMessageActionType.readReactionOrPollVote
                )] {
                    hasUnseenReactions = (info.tagSummaryCount ?? 0) != 0
                }
                
                var hasUnseenPollVotes = false
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenPollVote,
                    actionType: PendingMessageActionType.readReactionOrPollVote
                )] {
                    hasUnseenPollVotes = (info.tagSummaryCount ?? 0) != 0
                }
                
                let pinnedIndex: EngineChatList.Item.PinnedIndex
                if let index = item.pinnedIndex {
                    pinnedIndex = .index(index)
                } else {
                    pinnedIndex = .none
                }
                
                var topicMaxIncomingReadId = data.maxIncomingReadId
                if data.maxIncomingReadId == 0 && maxReadId != 0 && Int64(maxReadId) <= item.id {
                    topicMaxIncomingReadId = max(topicMaxIncomingReadId, maxReadId)
                }
                
                let readCounters = EnginePeerReadCounters(state: CombinedPeerReadState(states: [(Namespaces.Message.Cloud, .idBased(maxIncomingReadId: topicMaxIncomingReadId, maxOutgoingReadId: data.maxOutgoingReadId, maxKnownId: 1, count: data.incomingUnreadCount, markedUnread: false))]), isMuted: false)
                
                var draft: EngineChatList.Draft?
                if let embeddedState = item.embeddedInterfaceState, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            draft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
                
                items.append(EngineChatList.Item(
                    id: .forum(item.id),
                    index: .forum(pinnedIndex: pinnedIndex, timestamp: item.index.timestamp, threadId: item.id, namespace: item.index.id.namespace, id: item.index.id.id),
                    messages: item.topMessage.flatMap { [EngineMessage($0)] } ?? [],
                    readCounters: readCounters,
                    isMuted: isMuted,
                    draft: draft,
                    threadData: data,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(peer)),
                    presence: nil,
                    hasUnseenMentions: hasUnseenMentions,
                    hasUnseenReactions: hasUnseenReactions,
                    hasUnseenPollVotes: hasUnseenPollVotes,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: false,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))
            }
            
            let list = EngineChatList(
                items: items.reversed(),
                groupItems: [],
                additionalItems: [],
                hasEarlier: false,
                hasLater: false,
                isLoading: view.isLoading
            )
            
            let type: ViewUpdateType
            if isFirst {
                type = .Initial
            } else {
                type = .Generic
            }
            isFirst = false
            return ChatListNodeViewUpdate(list: list, type: type, scrollPosition: nil)
        }
    case let .savedMessagesChats(peerId):
        let viewKey: PostboxViewKey = .savedMessagesIndex(peerId: peerId)
        let interfaceStateKey: PostboxViewKey = .chatInterfaceState(peerId: peerId)
        
        var isFirst = true
        return account.postbox.combinedView(keys: [viewKey, interfaceStateKey])
        |> map { views -> ChatListNodeViewUpdate in
            guard let view = views.views[viewKey] as? MessageHistorySavedMessagesIndexView else {
                preconditionFailure()
            }
            
            var draft: EngineChatList.Draft?
            if let interfaceStateView = views.views[interfaceStateKey] as? ChatInterfaceStateView {
                if let embeddedState = interfaceStateView.value, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            draft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
            }
             
            var items: [EngineChatList.Item] = []
            for item in view.items {
                guard let sourcePeer = item.peer else {
                    continue
                }
                
                let sourceId = PeerId(item.id)
                
                var messages: [EngineMessage] = []
                if let topMessage = item.topMessage {
                    messages.append(EngineMessage(topMessage))
                }
                
                let mappedMessageIndex = MessageIndex(id: MessageId(peerId: sourceId, namespace: item.index.id.namespace, id: item.index.id.id), timestamp: item.index.timestamp)
                
                let readCounters = EnginePeerReadCounters(state: CombinedPeerReadState(states: [(Namespaces.Message.Cloud, .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 0, count: Int32(item.unreadCount), markedUnread: item.markedUnread))]), isMuted: false)
                
                var itemDraft: EngineChatList.Draft?
                if let embeddedState = item.embeddedInterfaceState, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            itemDraft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
                
                items.append(EngineChatList.Item(
                    id: .chatList(sourceId),
                    index: .chatList(ChatListIndex(pinningIndex: item.pinnedIndex.flatMap(UInt16.init), messageIndex: mappedMessageIndex)),
                    messages: messages,
                    readCounters: readCounters,
                    isMuted: false,
                    draft: sourceId == accountPeerId ? draft : itemDraft,
                    threadData: nil,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(sourcePeer)),
                    presence: nil,
                    hasUnseenMentions: false,
                    hasUnseenReactions: false,
                    hasUnseenPollVotes: false,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: false,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))
            }
            
            let list = EngineChatList(
                items: items.reversed(),
                groupItems: [],
                additionalItems: [],
                hasEarlier: false,
                hasLater: false,
                isLoading: view.isLoading
            )
            
            let type: ViewUpdateType
            if isFirst {
                type = .Initial
            } else {
                type = .Generic
            }
            isFirst = false
            return ChatListNodeViewUpdate(list: list, type: type, scrollPosition: nil)
        }
    }
}
