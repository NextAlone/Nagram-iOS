import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import ItemListUI
import ItemListPeerItem
import NagramStrings

// MARK: NAGRAM — 用户在共同群里的近期发言。
// 服务端没有跨群按发送者搜索的接口：先分页取完共同群，再逐群用 messages.search(from_id:) 取最近几条，合并后按时间倒序列出。

private let maxCommonGroups = 100
private let messagesPerGroup: Int32 = 10
private let searchBatchSize = 4

private struct CommonGroupMessage: Equatable {
    let group: EnginePeer
    let message: EngineMessage

    static func ==(lhs: CommonGroupMessage, rhs: CommonGroupMessage) -> Bool {
        return lhs.group == rhs.group && lhs.message.id == rhs.message.id && lhs.message.stableVersion == rhs.message.stableVersion
    }
}

private struct CommonGroupMessagesState: Equatable {
    var totalGroups: Int?
    var searchedGroups: Int = 0
    var messages: [CommonGroupMessage] = []
    var isFinished: Bool = false
}

private final class CommonGroupMessagesArguments {
    let context: AccountContext
    let openMessage: (EngineMessage) -> Void

    init(context: AccountContext, openMessage: @escaping (EngineMessage) -> Void) {
        self.context = context
        self.openMessage = openMessage
    }
}

private enum CommonGroupMessagesEntry: ItemListNodeEntry {
    case progress(String)
    case message(Int, CommonGroupMessage, String, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: AnyHashable {
        switch self {
        case .progress:
            return AnyHashable("progress")
        case let .message(_, item, _, _):
            return AnyHashable(item.message.id)
        }
    }

    private var sortIndex: Int {
        switch self {
        case .progress:
            return -1
        case let .message(index, _, _, _):
            return index
        }
    }

    static func ==(lhs: CommonGroupMessagesEntry, rhs: CommonGroupMessagesEntry) -> Bool {
        switch lhs {
        case let .progress(text):
            if case .progress(text) = rhs {
                return true
            }
            return false
        case let .message(index, item, text, date):
            if case .message(index, item, text, date) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: CommonGroupMessagesEntry, rhs: CommonGroupMessagesEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CommonGroupMessagesArguments
        switch self {
        case let .progress(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .message(_, item, text, date):
            let message = item.message
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: PresentationDateTimeFormat(), nameDisplayOrder: .firstLast, context: arguments.context, peer: item.group, presence: nil, text: .text(text, .secondary), label: .text(date, .standard, nil, false), editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.openMessage(message)
            }, setPeerIdWithRevealedOptions: { _, _ in }, removePeer: { _ in })
        }
    }
}

/// 逐批搜索共同群里该用户的消息；每批完成后更新一次状态。
private final class CommonGroupMessagesLoader {
    private let context: AccountContext
    private let userPeerId: EnginePeer.Id
    private let groupsContext: GroupsInCommonContext
    private var groupsDisposable: Disposable?
    private let searchDisposable = MetaDisposable()
    private var groups: [EnginePeer] = []
    private var didStartSearch = false

    private var stateValue = CommonGroupMessagesState() {
        didSet {
            self.statePromise.set(self.stateValue)
        }
    }
    private let statePromise = ValuePromise<CommonGroupMessagesState>(CommonGroupMessagesState())
    var state: Signal<CommonGroupMessagesState, NoError> {
        return self.statePromise.get()
    }

    init(context: AccountContext, userPeerId: EnginePeer.Id) {
        self.context = context
        self.userPeerId = userPeerId
        self.groupsContext = GroupsInCommonContext(account: context.account, peerId: userPeerId)

        self.groupsDisposable = (self.groupsContext.state
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let self, !self.didStartSearch else {
                return
            }
            guard case let .ready(canLoadMore) = state.dataState else {
                return
            }
            if canLoadMore && state.peers.count < maxCommonGroups {
                self.groupsContext.loadMore()
                return
            }
            self.didStartSearch = true
            self.groups = state.peers.prefix(maxCommonGroups).compactMap { renderedPeer in
                return renderedPeer.peer.flatMap(EnginePeer.init)
            }
            var updated = self.stateValue
            updated.totalGroups = self.groups.count
            self.stateValue = updated
            self.searchNextBatch(from: 0)
        })
    }

    deinit {
        self.groupsDisposable?.dispose()
        self.searchDisposable.dispose()
    }

    private func searchNextBatch(from start: Int) {
        guard start < self.groups.count else {
            var updated = self.stateValue
            updated.isFinished = true
            self.stateValue = updated
            return
        }
        let batch = Array(self.groups[start ..< min(start + searchBatchSize, self.groups.count)])
        let userPeerId = self.userPeerId
        let signals: [Signal<[CommonGroupMessage], NoError>] = batch.map { group in
            return self.context.engine.messages.searchMessages(location: .peer(peerId: group.id, fromId: userPeerId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: messagesPerGroup)
            |> take(1)
            |> map { result -> [CommonGroupMessage] in
                return result.0.messages.map { CommonGroupMessage(group: group, message: EngineMessage($0)) }
            }
        }
        self.searchDisposable.set((combineLatest(signals)
        |> deliverOnMainQueue).startStrict(next: { [weak self] results in
            guard let self else {
                return
            }
            var updated = self.stateValue
            updated.searchedGroups += batch.count
            updated.messages.append(contentsOf: results.flatMap { $0 })
            updated.messages.sort(by: { lhs, rhs in
                if lhs.message.timestamp != rhs.message.timestamp {
                    return lhs.message.timestamp > rhs.message.timestamp
                }
                return lhs.message.index > rhs.message.index
            })
            self.stateValue = updated
            self.searchNextBatch(from: start + batch.count)
        }))
    }
}

public func nagramCommonGroupMessagesController(context: AccountContext, userPeerId: EnginePeer.Id) -> ViewController {
    let loader = CommonGroupMessagesLoader(context: context, userPeerId: userPeerId)
    var openMessageImpl: ((EngineMessage) -> Void)?
    let arguments = CommonGroupMessagesArguments(context: context, openMessage: { message in
        openMessageImpl?(message)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        loader.state
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [CommonGroupMessagesEntry] = []
        if let totalGroups = state.totalGroups, totalGroups > 0 {
            let progressKey = state.isFinished ? "Nagram.CommonGroupMessages.Searched" : "Nagram.CommonGroupMessages.Searching"
            let progress = ngI18n(progressKey, lang)
                .replacingOccurrences(of: "{searched}", with: "\(state.searchedGroups)")
                .replacingOccurrences(of: "{total}", with: "\(totalGroups)")
            entries.append(.progress(progress))
        }
        let now = Int32(Date().timeIntervalSince1970)
        for (index, item) in state.messages.enumerated() {
            let text = descriptionStringForMessage(contentSettings: context.currentContentSettings.with { $0 }, message: item.message, strings: presentationData.strings, nameDisplayOrder: presentationData.nameDisplayOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: context.account.peerId).0.string
            let date = stringForRelativeTimestamp(strings: presentationData.strings, relativeTimestamp: item.message.timestamp, relativeTo: now, dateTimeFormat: presentationData.dateTimeFormat)
            entries.append(.message(index, item, text.replacingOccurrences(of: "\n", with: " "), date))
        }

        let emptyStateItem: ItemListControllerEmptyStateItem?
        if !state.messages.isEmpty {
            emptyStateItem = nil
        } else if state.isFinished {
            emptyStateItem = ItemListTextEmptyStateItem(text: ngI18n("Nagram.CommonGroupMessages.Empty", lang))
        } else {
            emptyStateItem = ItemListLoadingIndicatorEmptyStateItem(theme: presentationData.theme)
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.CommonGroupMessages", lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            emptyStateItem: emptyStateItem,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        // 列表关闭时释放搜索。
        let _ = loader
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    openMessageImpl = { [weak controller] message in
        guard let controller, let navigationController = controller.navigationController as? NavigationController else {
            return
        }
        guard let peer = message.peers[message.id.peerId].flatMap(EnginePeer.init) else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always, useExisting: false))
    }
    return controller
}
