import Foundation
import Postbox
import SwiftSignalKit

// MARK: NAGRAM — 写入 Nagram/Demo 的演示账号数据库。内容由 Nagram/Demo 提供，这里只负责落库。
/// Seeds the account database of the disposable demo record `id`: the peers, the account's own
/// state, and one fully loaded, read-state-consistent history per chat. `chats` are listed in chat
/// list order (the first one is pinned); a message is incoming unless `accountPeerId` wrote it,
/// and the last `unreadCount` incoming messages of a chat are unread.
public func nagramSeedDemoDatabase(
    rootPath: String,
    id: AccountRecordId,
    encryptionParameters: EngineValueBoxEncryptionParameters,
    accountPeerId: EnginePeer.Id,
    peers: [EnginePeer],
    onlinePeerIds: [EnginePeer.Id],
    timestamp: Int32,
    chats: [(peerId: EnginePeer.Id, messages: [(authorId: EnginePeer.Id, text: String)], unreadCount: Int32)]
) -> Signal<Void, AccountTransactionError> {
    precondition(rootPath.contains("/nagram-demo-data/"), "Demo data requires its isolated directory")
    return accountTransaction(rootPath: rootPath, id: id, encryptionParameters: encryptionParameters, isReadOnly: false, transaction: { _, transaction -> Void in
        transaction.updatePeersInternal(peers.map { $0._asPeer() }, update: { _, peer in peer })
        // Private chat history waits for a known business intro, even when there is none.
        let userPeerIds = peers.map(\.id).filter { $0.namespace == Namespaces.Peer.CloudUser }
        transaction.updatePeerCachedData(peerIds: Set(userPeerIds), update: { _, _ in
            CachedUserData().withUpdatedBusinessIntro(nil).withUpdatedPeerStatusSettings(PeerStatusSettings())
        })
        var presences: [PeerId: PeerPresence] = [:]
        for peerId in onlinePeerIds {
            presences[peerId] = TelegramUserPresence(status: .present(until: Int32.max), lastActivity: timestamp)
        }
        transaction.updatePeerPresencesInternal(presences: presences, merge: { _, presence in presence })
        transaction.setState(AuthorizedAccountState(
            isTestingEnvironment: true, masterDatacenterId: 2, peerId: accountPeerId,
            state: AuthorizedAccountState.State(pts: 1, qts: 0, date: timestamp, seq: 0),
            invalidatedChannels: []
        ))
        transaction.updatePreferencesEntry(key: PreferencesKeys.contactsSettings, { _ in
            PreferencesEntry(ContactsSettings(synchronizeContacts: false))
        })

        for (chatIndex, chat) in chats.enumerated() {
            let firstId = Int32(chatIndex * 100 + 1)
            let messages = chat.messages.enumerated().map { index, item -> StoreMessage in
                return StoreMessage(
                    id: MessageId(peerId: chat.peerId, namespace: Namespaces.Message.Cloud, id: firstId + Int32(index)),
                    customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil,
                    timestamp: timestamp - Int32(chatIndex * 900 + (chat.messages.count - index - 1) * 60),
                    flags: item.authorId == accountPeerId ? [] : [.Incoming], tags: [], globalTags: [], localTags: [],
                    forwardInfo: nil, authorId: item.authorId, text: item.text, attributes: [], media: []
                )
            }
            let _ = transaction.addMessages(messages, location: .Random)
            transaction.updatePeerChatListInclusion(chat.peerId, inclusion: .ifHasMessagesOrOneOf(
                groupId: .root, pinningIndex: chatIndex == 0 ? 0 : nil, minTimestamp: nil
            ))
            let lastId = firstId + Int32(chat.messages.count) - 1
            let unreadIds = chat.messages.enumerated().compactMap { index, item -> Int32? in
                return item.authorId == accountPeerId ? nil : firstId + Int32(index)
            }.suffix(Int(chat.unreadCount))
            transaction.resetIncomingReadStates([chat.peerId: [Namespaces.Message.Cloud: .idBased(
                maxIncomingReadId: unreadIds.first.map { $0 - 1 } ?? lastId, maxOutgoingReadId: lastId,
                maxKnownId: lastId, count: Int32(unreadIds.count), markedUnread: false
            )]])
            transaction.removeHole(peerId: chat.peerId, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... Int32.max - 1)
        }
        for groupId in [PeerGroupId.root, Namespaces.PeerGroup.archive] {
            for hole in transaction.allChatListHoles(groupId: groupId) {
                transaction.replaceChatListHole(groupId: groupId, index: hole.index, hole: nil)
            }
        }
    })
}
