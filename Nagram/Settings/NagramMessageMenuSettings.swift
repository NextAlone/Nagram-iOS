import Foundation

public enum NagramMessageMenuItemId: String, CaseIterable {
    case viewInChat
    case favoriteSticker
    case shareCallStats
    case rateCall
    case saveNotificationSound
    case increaseSpeed
    case sendGift
    case reply
    case `repeat`
    case sendScheduledNow
    case editScheduledTime
    case copy
    case translate
    case speak
    case saveMedia
    case saveToFiles
    case sendLogs
    case viewReplies
    case edit
    case editSuggestedPostMessage
    case editSuggestedPostTime
    case editSuggestedPostPrice
    case createSuggestedPost
    case unvotePoll
    case addTodoTask
    case unpin
    case pin
    case stopPoll
    case copyLink
    case saveGif
    case editSticker
    case viewStickerPack
    case forward
    case report
    case block
    case viewStats
    case viewPollStats
    case factCheck
    case viewInChannel
    case select
    case selectAll
    case delete
}

private let nagramMessageMenuOrderKey = "nagram.messageMenu.order"
private let nagramMessageMenuDisabledKey = "nagram.messageMenu.disabled"

public extension NagramSettings {
    var messageMenuItemOrder: [NagramMessageMenuItemId] {
        get {
            let stored = self.messageMenuIds(from: UserDefaults.standard.string(forKey: nagramMessageMenuOrderKey))
            return self.normalizedMessageMenuOrder(stored)
        }
        set {
            let order = self.normalizedMessageMenuOrder(newValue)
            UserDefaults.standard.set(order.map(\.rawValue).joined(separator: ","), forKey: nagramMessageMenuOrderKey)
        }
    }

    func isMessageMenuItemEnabled(_ id: NagramMessageMenuItemId) -> Bool {
        return !self.disabledMessageMenuItemIds.contains(id)
    }

    func setMessageMenuItemEnabled(_ id: NagramMessageMenuItemId, enabled: Bool) {
        var disabled = self.disabledMessageMenuItemIds
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
        UserDefaults.standard.set(disabled.map(\.rawValue).sorted().joined(separator: ","), forKey: nagramMessageMenuDisabledKey)
    }

    func resetMessageMenuItems() {
        UserDefaults.standard.removeObject(forKey: nagramMessageMenuOrderKey)
        UserDefaults.standard.removeObject(forKey: nagramMessageMenuDisabledKey)
    }
}

private extension NagramSettings {
    var disabledMessageMenuItemIds: Set<NagramMessageMenuItemId> {
        return Set(self.messageMenuIds(from: UserDefaults.standard.string(forKey: nagramMessageMenuDisabledKey)))
    }

    func messageMenuIds(from string: String?) -> [NagramMessageMenuItemId] {
        guard let string, !string.isEmpty else {
            return []
        }
        return string.split(separator: ",").compactMap { NagramMessageMenuItemId(rawValue: String($0)) }
    }

    func normalizedMessageMenuOrder(_ ids: [NagramMessageMenuItemId]) -> [NagramMessageMenuItemId] {
        var result: [NagramMessageMenuItemId] = []
        var seen = Set<NagramMessageMenuItemId>()
        for id in ids {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        for id in NagramMessageMenuItemId.allCases {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }
}
