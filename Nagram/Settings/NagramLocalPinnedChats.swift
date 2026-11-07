import Foundation

public extension Notification.Name {
    static let nagramLocalPinnedChatsDidChange = Notification.Name("NagramLocalPinnedChatsDidChange")
}

// MARK: NAGRAM — 本地置顶：超出 Telegram 置顶上限后，「全部聊天」里只在本机置顶的会话。
// 与服务端置顶完全分开存放，永不同步到服务器；顺序即显示顺序，排在服务端置顶之后。
// 按账号存放，值是 PeerId 的 Int64 表示，由 UI 侧负责往返。只存本机，不进 iCloud 同步。
public extension NagramSettings {
    /// 与 Postbox 的 ChatListIndex.nagramLocalPinnedLimit 一致。
    static let localPinnedChatsLimit = 62

    private func localPinnedChatsKey(accountPeerId: Int64) -> String {
        return "nagram.localPinnedChats.\(accountPeerId)"
    }

    func localPinnedChatIds(accountPeerId: Int64) -> [Int64] {
        return NagramDemoMode.userDefaults.stringArray(forKey: self.localPinnedChatsKey(accountPeerId: accountPeerId))?.compactMap(Int64.init) ?? []
    }

    func isLocallyPinnedChat(_ peerId: Int64, accountPeerId: Int64) -> Bool {
        return self.localPinnedChatIds(accountPeerId: accountPeerId).contains(peerId)
    }

    func setLocalPinnedChatIds(_ peerIds: [Int64], accountPeerId: Int64) {
        var seen = Set<Int64>()
        let values = peerIds.filter { seen.insert($0).inserted }.prefix(NagramSettings.localPinnedChatsLimit)
        let key = self.localPinnedChatsKey(accountPeerId: accountPeerId)
        if values.isEmpty {
            NagramDemoMode.userDefaults.removeObject(forKey: key)
        } else {
            NagramDemoMode.userDefaults.set(values.map { String($0) }, forKey: key)
        }
        NotificationCenter.default.post(name: .nagramLocalPinnedChatsDidChange, object: nil, userInfo: ["accountPeerId": accountPeerId])
    }

    /// 新的本地置顶放在本地置顶的最上面，与 Telegram 新置顶出现在最上方一致。达到上限时返回 false。
    @discardableResult
    func addLocalPinnedChat(_ peerId: Int64, accountPeerId: Int64) -> Bool {
        var values = self.localPinnedChatIds(accountPeerId: accountPeerId)
        if values.contains(peerId) {
            return true
        }
        if values.count >= NagramSettings.localPinnedChatsLimit {
            return false
        }
        values.insert(peerId, at: 0)
        self.setLocalPinnedChatIds(values, accountPeerId: accountPeerId)
        return true
    }

    func removeLocalPinnedChat(_ peerId: Int64, accountPeerId: Int64) {
        let values = self.localPinnedChatIds(accountPeerId: accountPeerId)
        guard values.contains(peerId) else {
            return
        }
        self.setLocalPinnedChatIds(values.filter { $0 != peerId }, accountPeerId: accountPeerId)
    }
}
