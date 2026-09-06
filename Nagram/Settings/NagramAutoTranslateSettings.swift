import Foundation

// MARK: NAGRAM — 对话级本地自动翻译开关。

public extension NagramSettings {
    static func autoTranslateKey(accountPeerId: Int64, peerId: Int64, threadId: Int64?) -> String {
        if let threadId {
            return "nagram.autoTranslate.\(accountPeerId).\(peerId).\(threadId)"
        } else {
            return "nagram.autoTranslate.\(accountPeerId).\(peerId)"
        }
    }

    func isAutoTranslateEnabled(accountPeerId: Int64, peerId: Int64, threadId: Int64?) -> Bool {
        return NagramDemoMode.userDefaults.bool(forKey: Self.autoTranslateKey(accountPeerId: accountPeerId, peerId: peerId, threadId: threadId))
    }

    func setAutoTranslateEnabled(_ enabled: Bool, accountPeerId: Int64, peerId: Int64, threadId: Int64?) {
        let key = Self.autoTranslateKey(accountPeerId: accountPeerId, peerId: peerId, threadId: threadId)
        if enabled {
            NagramSettingsCloudSync.shared.set(true, forKey: key)
        } else {
            NagramSettingsCloudSync.shared.removeObject(forKey: key)
        }
    }
}
