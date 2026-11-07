import Foundation
import XCTest
import SwiftSignalKit
@testable import Postbox

// MARK: NAGRAM
/// Nagram's local pins: chats pinned in "All chats" on this device only, past the server's pin limit. The root view
/// gets them as a `.peers(asPinned:)` space whose pinning indices start at `nagramLocalPinningIndexOffset`, so they sort
/// after (below) every server pin and are told apart by `isNagramLocalPin`. The chat stays in the unpinned space too;
/// ChatListUI drops that row, so the view itself is expected to carry both.
final class ChatListNagramLocalPinnedViewTests: XCTestCase {
    private var fixture: PostboxFixture!

    private let serverPinnedChat = MessageHistoryTableFixture.peerId(900)
    private let localPinnedChat = MessageHistoryTableFixture.peerId(901)
    private let secondLocalPinnedChat = MessageHistoryTableFixture.peerId(902)
    private let otherChat = MessageHistoryTableFixture.peerId(903)
    private let namespace = PostboxFixture.messageNamespace

    override func setUp() {
        super.setUp()
        self.fixture = PostboxFixture(name: "ChatListNagramLocalPinnedViewTests")
    }

    override func tearDown() {
        self.fixture.close()
        self.fixture = nil
        super.tearDown()
    }

    private func message(peerId: PeerId, id: Int32, timestamp: Int32) -> StoreMessage {
        return MessageHistoryTableFixture.storeMessage(id: MessageId(peerId: peerId, namespace: self.namespace, id: id), timestamp: timestamp, text: "m\(id)", flags: [.Incoming])
    }

    private func seed() {
        let peerIds = [self.serverPinnedChat, self.localPinnedChat, self.secondLocalPinnedChat, self.otherChat]
        self.fixture.transaction { transaction in
            transaction.updatePeersInternal(peerIds.map { FixturePeer(id: $0, title: "\($0.id._internalGetInt64Value())") }, update: { _, updated in updated })
            for peerId in peerIds {
                transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
            }
            let _ = transaction.addMessages([
                self.message(peerId: self.serverPinnedChat, id: 1, timestamp: 1000),
                self.message(peerId: self.localPinnedChat, id: 1, timestamp: 1100),
                self.message(peerId: self.secondLocalPinnedChat, id: 1, timestamp: 1200),
                self.message(peerId: self.otherChat, id: 1, timestamp: 1300),
            ], location: .Random)
            transaction.setPinnedItemIds(groupId: .root, itemIds: [.peer(self.serverPinnedChat)])
        }
    }

    private func observeRoot(localPins: [PeerId]) -> PostboxFixture.Recorder<ChatListView> {
        return self.fixture.observe(self.fixture.postbox.tailChatListView(groupId: .root, filterPredicate: nil, count: 10, summaryComponents: ChatListEntrySummaryComponents(), nagramLocalPinnedPeerIds: localPins) |> map { $0.0 })
    }

    private func indices(for peerId: PeerId, in view: ChatListView?) -> [ChatListIndex] {
        return (view?.entries ?? []).compactMap { entry -> ChatListIndex? in
            if case let .MessageEntry(data) = entry, data.index.messageIndex.id.peerId == peerId {
                return data.index
            }
            return nil
        }
    }

    func testLocalPinsSortBelowServerPinsInTheirOwnOrder() {
        self.seed()
        let view = self.observeRoot(localPins: [self.secondLocalPinnedChat, self.localPinnedChat]).waitForValues(count: 1).last

        let serverPin = self.indices(for: self.serverPinnedChat, in: view).first(where: { $0.pinningIndex != nil })
        let firstLocal = self.indices(for: self.secondLocalPinnedChat, in: view).first(where: { $0.pinningIndex != nil })
        let secondLocal = self.indices(for: self.localPinnedChat, in: view).first(where: { $0.pinningIndex != nil })

        XCTAssertEqual(serverPin?.pinningIndex, 0)
        XCTAssertEqual(serverPin?.isNagramLocalPin, false)
        XCTAssertEqual(firstLocal?.pinningIndex, ChatListIndex.nagramLocalPinningIndexOffset)
        XCTAssertEqual(secondLocal?.pinningIndex, ChatListIndex.nagramLocalPinningIndexOffset + 1)
        XCTAssertEqual(firstLocal?.isNagramLocalPin, true)
        if let serverPin, let firstLocal, let secondLocal {
            XCTAssertTrue(serverPin > firstLocal, "a server pin is shown above every local pin")
            XCTAssertTrue(firstLocal > secondLocal, "local pins keep the stored order")
        }
        XCTAssertTrue(self.indices(for: self.localPinnedChat, in: view).contains(where: { $0.pinningIndex == nil }), "the unpinned row is left for ChatListUI to drop")
    }

    func testLocalPinFollowsANewMessage() {
        self.seed()
        let recorder = self.observeRoot(localPins: [self.localPinnedChat])
        recorder.waitForValues(count: 1)

        self.fixture.transaction { transaction in
            let _ = transaction.addMessages([self.message(peerId: self.localPinnedChat, id: 2, timestamp: 5000)], location: .Random)
        }

        let view = recorder.waitForValues(count: 2).last
        let pinnedRows = (view?.entries ?? []).compactMap { entry -> ChatListEntry.MessageEntryData? in
            if case let .MessageEntry(data) = entry, data.index.messageIndex.id.peerId == self.localPinnedChat, data.index.pinningIndex != nil {
                return data
            }
            return nil
        }
        XCTAssertEqual(pinnedRows.count, 1)
        XCTAssertEqual(pinnedRows.first?.index.pinningIndex, ChatListIndex.nagramLocalPinningIndexOffset)
        XCTAssertEqual(pinnedRows.first?.messages.first?.id.id, 2)
    }

    func testNoLocalPinsLeavesTheRootViewUnchanged() {
        self.seed()
        let view = self.observeRoot(localPins: []).waitForValues(count: 1).last
        let pinned = (view?.entries ?? []).compactMap { entry -> ChatListIndex? in
            if case let .MessageEntry(data) = entry, data.index.pinningIndex != nil {
                return data.index
            }
            return nil
        }
        XCTAssertEqual(pinned.map { $0.messageIndex.id.peerId }, [self.serverPinnedChat])
    }
}
