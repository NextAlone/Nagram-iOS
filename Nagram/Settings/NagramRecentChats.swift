import Foundation

public extension Notification.Name {
    static let nagramRecentChatsDidChange = Notification.Name("NagramRecentChatsDidChange")
    static let nagramRecentChatFolderSettingsDidChange = Notification.Name("NagramRecentChatFolderSettingsDidChange")
}

// MARK: NAGRAM — 最近会话存储。字符串落盘,由 UI 侧负责 PeerId 往返。
public extension NagramSettings {
    private var recentChatsLimit: Int {
        return 50
    }

    private func recentChatsKey(accountPeerId: Int64) -> String {
        return "nagram.recentChats.\(accountPeerId)"
    }
    
    private func recentChatFoldersKey(accountPeerId: Int64) -> String {
        return "nagram.recentChatFolders.\(accountPeerId)"
    }
    
    private func recentChatContainerPeerIdsKey(accountPeerId: Int64) -> String {
        return "nagram.recentChatContainerPeerIds.\(accountPeerId)"
    }
    
    private func recentChatContainerPeerIds(accountPeerId: Int64) -> [Int64: Int64] {
        guard let values = NagramDemoMode.userDefaults.dictionary(forKey: self.recentChatContainerPeerIdsKey(accountPeerId: accountPeerId)) else {
            return [:]
        }
        var result: [Int64: Int64] = [:]
        for (peerId, containerPeerId) in values {
            guard let peerId = Int64(peerId) else {
                continue
            }
            if let containerPeerId = containerPeerId as? String, let value = Int64(containerPeerId) {
                result[peerId] = value
            } else if let containerPeerId = containerPeerId as? NSNumber {
                result[peerId] = containerPeerId.int64Value
            }
        }
        return result
    }
    
    private func setRecentChatContainerPeerIds(_ values: [Int64: Int64], accountPeerId: Int64) {
        let key = self.recentChatContainerPeerIdsKey(accountPeerId: accountPeerId)
        if values.isEmpty {
            NagramDemoMode.userDefaults.removeObject(forKey: key)
        } else {
            NagramDemoMode.userDefaults.set(Dictionary(uniqueKeysWithValues: values.map { (String($0.key), String($0.value)) }), forKey: key)
        }
    }

    func recentChatIds(accountPeerId: Int64, limit: Int? = nil) -> [Int64] {
        let values = NagramDemoMode.userDefaults.stringArray(forKey: self.recentChatsKey(accountPeerId: accountPeerId))?.compactMap(Int64.init) ?? []
        if let limit {
            return Array(values.prefix(limit))
        } else {
            return values
        }
    }
    
    func recentChatFilterPeerIds(accountPeerId: Int64, limit: Int? = nil) -> [Int64] {
        let recentChatIds = self.recentChatIds(accountPeerId: accountPeerId, limit: limit)
        let containerPeerIds = self.recentChatContainerPeerIds(accountPeerId: accountPeerId)
        var seenPeerIds = Set<Int64>()
        var result: [Int64] = []
        for peerId in recentChatIds {
            if seenPeerIds.insert(peerId).inserted {
                result.append(peerId)
            }
            if let containerPeerId = containerPeerIds[peerId], seenPeerIds.insert(containerPeerId).inserted {
                result.append(containerPeerId)
            }
        }
        return result
    }
    
    func isRecentChatFolderEnabled(accountPeerId: Int64, filterId: Int32) -> Bool {
        guard filterId > 0 else {
            return false
        }
        return NagramDemoMode.userDefaults.stringArray(forKey: self.recentChatFoldersKey(accountPeerId: accountPeerId))?.contains(String(filterId)) ?? false
    }
    
    func hasRecentChatFolderEnabled(accountPeerId: Int64) -> Bool {
        return !(NagramDemoMode.userDefaults.stringArray(forKey: self.recentChatFoldersKey(accountPeerId: accountPeerId)) ?? []).isEmpty
    }
    
    func setRecentChatFolderEnabled(_ enabled: Bool, accountPeerId: Int64, filterId: Int32) {
        guard filterId > 0 else {
            return
        }
        
        let key = self.recentChatFoldersKey(accountPeerId: accountPeerId)
        var values = Set(NagramDemoMode.userDefaults.stringArray(forKey: key) ?? [])
        let id = String(filterId)
        let hadValue = values.contains(id)
        if enabled {
            values.insert(id)
        } else {
            values.remove(id)
        }
        if values.isEmpty {
            NagramSettingsCloudSync.shared.removeObject(forKey: key)
        } else {
            NagramSettingsCloudSync.shared.set(Array(values).sorted(), forKey: key)
        }
        
        if hadValue != enabled {
            NotificationCenter.default.post(
                name: .nagramRecentChatFolderSettingsDidChange,
                object: self,
                userInfo: ["accountPeerId": accountPeerId, "filterId": filterId]
            )
        }
    }

    func addRecentChatId(_ peerId: Int64, accountPeerId: Int64) {
        self.addRecentChatId(peerId, containerPeerId: nil, updateContainerPeerId: false, accountPeerId: accountPeerId)
    }
    
    func addRecentChatId(_ peerId: Int64, containerPeerId: Int64?, accountPeerId: Int64) {
        self.addRecentChatId(peerId, containerPeerId: containerPeerId, updateContainerPeerId: true, accountPeerId: accountPeerId)
    }
    
    private func addRecentChatId(_ peerId: Int64, containerPeerId: Int64?, updateContainerPeerId: Bool, accountPeerId: Int64) {
        guard self.recentChatsEnabled || self.hasRecentChatFolderEnabled(accountPeerId: accountPeerId) else {
            return
        }
        var values = self.recentChatIds(accountPeerId: accountPeerId)
        let previousValues = values
        var containerPeerIds = self.recentChatContainerPeerIds(accountPeerId: accountPeerId)
        let previousContainerPeerIds = containerPeerIds
        if updateContainerPeerId {
            if let containerPeerId, containerPeerId != peerId {
                containerPeerIds[peerId] = containerPeerId
            } else {
                containerPeerIds.removeValue(forKey: peerId)
            }
        }
        if values.first != peerId {
            values.removeAll(where: { $0 == peerId })
            values.insert(peerId, at: 0)
        }
        if values.count > self.recentChatsLimit {
            values.removeSubrange(self.recentChatsLimit ..< values.count)
        }
        let retainedPeerIds = Set(values)
        containerPeerIds = containerPeerIds.filter { retainedPeerIds.contains($0.key) }
        if values == previousValues && containerPeerIds == previousContainerPeerIds {
            return
        }
        if values != previousValues {
            NagramDemoMode.userDefaults.set(values.map { String($0) }, forKey: self.recentChatsKey(accountPeerId: accountPeerId))
        }
        if containerPeerIds != previousContainerPeerIds {
            self.setRecentChatContainerPeerIds(containerPeerIds, accountPeerId: accountPeerId)
        }
        NotificationCenter.default.post(
            name: .nagramRecentChatsDidChange,
            object: self,
            userInfo: ["accountPeerId": accountPeerId]
        )
    }
    
    func updateRecentChatContainerPeerIds(_ values: [Int64: Int64], resolvedPeerIds: Set<Int64>, accountPeerId: Int64) {
        let recentChatIds = Set(self.recentChatIds(accountPeerId: accountPeerId))
        var containerPeerIds = self.recentChatContainerPeerIds(accountPeerId: accountPeerId)
        let previousContainerPeerIds = containerPeerIds
        for peerId in resolvedPeerIds where recentChatIds.contains(peerId) {
            containerPeerIds.removeValue(forKey: peerId)
        }
        for (peerId, containerPeerId) in values where recentChatIds.contains(peerId) && peerId != containerPeerId {
            containerPeerIds[peerId] = containerPeerId
        }
        containerPeerIds = containerPeerIds.filter { recentChatIds.contains($0.key) }
        guard containerPeerIds != previousContainerPeerIds else {
            return
        }
        self.setRecentChatContainerPeerIds(containerPeerIds, accountPeerId: accountPeerId)
        NotificationCenter.default.post(
            name: .nagramRecentChatsDidChange,
            object: self,
            userInfo: ["accountPeerId": accountPeerId]
        )
    }
    
    func removeRecentChatId(_ peerId: Int64, accountPeerId: Int64) {
        var values = self.recentChatIds(accountPeerId: accountPeerId)
        var containerPeerIds = self.recentChatContainerPeerIds(accountPeerId: accountPeerId)
        let previousCount = values.count
        values.removeAll(where: { $0 == peerId })
        guard values.count != previousCount else {
            return
        }
        containerPeerIds.removeValue(forKey: peerId)
        
        let key = self.recentChatsKey(accountPeerId: accountPeerId)
        if values.isEmpty {
            NagramDemoMode.userDefaults.removeObject(forKey: key)
        } else {
            NagramDemoMode.userDefaults.set(values.map { String($0) }, forKey: key)
        }
        self.setRecentChatContainerPeerIds(containerPeerIds, accountPeerId: accountPeerId)
        NotificationCenter.default.post(
            name: .nagramRecentChatsDidChange,
            object: self,
            userInfo: ["accountPeerId": accountPeerId]
        )
    }
    
    @discardableResult
    func removeRecentChatIds(matchingFilterPeerId filterPeerId: Int64, accountPeerId: Int64) -> Bool {
        var values = self.recentChatIds(accountPeerId: accountPeerId)
        var containerPeerIds = self.recentChatContainerPeerIds(accountPeerId: accountPeerId)
        let previousCount = values.count
        values.removeAll(where: { peerId in
            return peerId == filterPeerId || containerPeerIds[peerId] == filterPeerId
        })
        guard values.count != previousCount else {
            return false
        }
        
        let retainedPeerIds = Set(values)
        containerPeerIds = containerPeerIds.filter { retainedPeerIds.contains($0.key) }
        let recentChatsKey = self.recentChatsKey(accountPeerId: accountPeerId)
        if values.isEmpty {
            NagramDemoMode.userDefaults.removeObject(forKey: recentChatsKey)
        } else {
            NagramDemoMode.userDefaults.set(values.map { String($0) }, forKey: recentChatsKey)
        }
        self.setRecentChatContainerPeerIds(containerPeerIds, accountPeerId: accountPeerId)
        NotificationCenter.default.post(
            name: .nagramRecentChatsDidChange,
            object: self,
            userInfo: ["accountPeerId": accountPeerId]
        )
        return true
    }
}
