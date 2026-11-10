import Foundation
import XCTest
import SwiftSignalKit
import Postbox
@testable import TelegramCore

// MARK: NAGRAM
/// The filtered-unread scans (badge adjustment and "auto-read filtered messages") run on every unread-counter change.
/// Each chat's result is cached, so a scan reads only what changed: nothing for an unchanged chat, only the new messages
/// when some arrived, nothing when the chat was read further. Driven over the harness's Postbox, without a state manager.
final class NagramFilteredUnreadTests: StateSyncTestCase {
    private final class Rules {
    }

    private let user = StateSyncFixture.userPeerId(500)
    private let cache = NagramFilteredUnreadCache()
    private let rules = Rules()
    private let isHidden: (Message) -> Bool = { $0.text.hasPrefix("spam") }

    /// Messages 1...100 stored, odd ids hidden; read up to 50.
    private func seedChat() {
        self.fixture.seedPeers([StateSyncFixture.makeUser(id: self.user, accessHash: 1, firstName: "U")])
        self.fixture.seedChat(peerId: self.user)
        self.store(ids: 1 ... 100)
        self.fixture.removeAllHoles(peerId: self.user)
        self.fixture.seedReadState(peerId: self.user, maxIncomingReadId: 50, maxOutgoingReadId: 0, maxKnownId: 100, count: 50)
    }

    private func store(ids: ClosedRange<Int32>, hidden: ((Int32) -> Bool)? = nil) {
        for id in ids {
            let isHidden = hidden?(id) ?? (id % 2 == 1)
            self.fixture.storeMessage(peerId: self.user, id: id, timestamp: self.baseDate + id, authorId: self.user, text: isHidden ? "spam \(id)" : "m\(id)")
        }
    }

    private func summary(rules: AnyObject? = nil, reload: Bool = false) -> NagramFilteredUnreadSummary? {
        let rulesIdentity = ObjectIdentifier(rules ?? self.rules)
        return self.fixture.transaction { transaction -> NagramFilteredUnreadSummary? in
            guard let readState = transaction.getCombinedPeerReadState(self.user) else {
                return nil
            }
            return _internal_nagramFilteredUnreadSummary(transaction: transaction, cache: self.cache, peerId: self.user, accountPeerId: StateSyncFixture.accountPeerId, readState: readState, rulesIdentity: rulesIdentity, reload: reload, isHidden: self.isHidden)
        } ?? nil
    }

    private func index(_ id: Int32) -> MessageIndex {
        return MessageIndex(id: MessageId(peerId: self.user, namespace: Namespaces.Message.Cloud, id: id), timestamp: self.baseDate + id)
    }

    func testTheFirstScanCountsTheHiddenUnreadMessages() {
        self.seedChat()

        XCTAssertEqual(self.summary(), NagramFilteredUnreadSummary(hiddenCount: 25, hasVisibleUnread: true, newestHiddenIndex: self.index(99)))
    }

    func testAnUnchangedChatIsNotReadAgain() {
        self.seedChat()
        let first = self.summary()
        let loaded = self.cache.loadedEntryCount

        XCTAssertEqual(self.summary(), first)
        XCTAssertEqual(self.cache.loadedEntryCount, loaded)
    }

    func testNewMessagesAreTheOnlyOnesRead() {
        self.seedChat()
        let _ = self.summary()
        let loaded = self.cache.loadedEntryCount

        self.store(ids: 101 ... 102, hidden: { _ in true })
        self.fixture.seedReadState(peerId: self.user, maxIncomingReadId: 50, maxOutgoingReadId: 0, maxKnownId: 102, count: 52)

        XCTAssertEqual(self.summary(), NagramFilteredUnreadSummary(hiddenCount: 27, hasVisibleUnread: true, newestHiddenIndex: self.index(102)))
        XCTAssertLessThanOrEqual(self.cache.loadedEntryCount - loaded, 12)
        XCTAssertEqual(self.summary(reload: true), NagramFilteredUnreadSummary(hiddenCount: 27, hasVisibleUnread: true, newestHiddenIndex: self.index(102)))
    }

    func testReadingFurtherReadsNothing() {
        self.seedChat()
        let _ = self.summary()
        let loaded = self.cache.loadedEntryCount

        self.fixture.seedReadState(peerId: self.user, maxIncomingReadId: 90, maxOutgoingReadId: 0, maxKnownId: 100, count: 10)

        XCTAssertEqual(self.summary(), NagramFilteredUnreadSummary(hiddenCount: 5, hasVisibleUnread: true, newestHiddenIndex: self.index(99)))
        XCTAssertEqual(self.cache.loadedEntryCount, loaded)
    }

    func testAReadBoundaryMovedBackReadsTheChatAgain() {
        self.seedChat()
        self.fixture.seedReadState(peerId: self.user, maxIncomingReadId: 90, maxOutgoingReadId: 0, maxKnownId: 100, count: 10)
        let _ = self.summary()

        self.fixture.seedReadState(peerId: self.user, maxIncomingReadId: 80, maxOutgoingReadId: 0, maxKnownId: 100, count: 20)

        XCTAssertEqual(self.summary(), NagramFilteredUnreadSummary(hiddenCount: 10, hasVisibleUnread: true, newestHiddenIndex: self.index(99)))
    }

    func testNewRulesReadTheChatAgain() {
        self.seedChat()
        let _ = self.summary()
        let loaded = self.cache.loadedEntryCount

        let _ = self.summary(rules: Rules())

        XCTAssertGreaterThan(self.cache.loadedEntryCount, loaded)
    }

    func testAChatWithOnlyHiddenUnreadMessagesHasNoVisibleOne() {
        self.seedChat()
        self.store(ids: 101 ... 103, hidden: { _ in true })
        self.fixture.seedReadState(peerId: self.user, maxIncomingReadId: 100, maxOutgoingReadId: 0, maxKnownId: 103, count: 3)

        XCTAssertEqual(self.summary(), NagramFilteredUnreadSummary(hiddenCount: 3, hasVisibleUnread: false, newestHiddenIndex: self.index(103)))
    }
}
