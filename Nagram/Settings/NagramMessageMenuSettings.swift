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
    case repeatWithoutQuote
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
    case forwardWithoutQuote
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
private let nagramMessageMenuEnabledDefaultDisabledKey = "nagram.messageMenu.enabledDefaultDisabled"
private let nagramDefaultDisabledMessageMenuItemIds: Set<NagramMessageMenuItemId> = [.repeatWithoutQuote, .forwardWithoutQuote]

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
        if nagramDefaultDisabledMessageMenuItemIds.contains(id), !self.enabledDefaultDisabledMessageMenuItemIds.contains(id) {
            return false
        }
        return !self.disabledMessageMenuItemIds.contains(id)
    }

    func setMessageMenuItemEnabled(_ id: NagramMessageMenuItemId, enabled: Bool) {
        var disabled = self.disabledMessageMenuItemIds
        var enabledDefaultDisabled = self.enabledDefaultDisabledMessageMenuItemIds
        if enabled {
            disabled.remove(id)
            if nagramDefaultDisabledMessageMenuItemIds.contains(id) {
                enabledDefaultDisabled.insert(id)
            }
        } else {
            disabled.insert(id)
            enabledDefaultDisabled.remove(id)
        }
        UserDefaults.standard.set(disabled.map(\.rawValue).sorted().joined(separator: ","), forKey: nagramMessageMenuDisabledKey)
        UserDefaults.standard.set(enabledDefaultDisabled.map(\.rawValue).sorted().joined(separator: ","), forKey: nagramMessageMenuEnabledDefaultDisabledKey)
    }

    func resetMessageMenuItems() {
        UserDefaults.standard.removeObject(forKey: nagramMessageMenuOrderKey)
        UserDefaults.standard.removeObject(forKey: nagramMessageMenuDisabledKey)
        UserDefaults.standard.removeObject(forKey: nagramMessageMenuEnabledDefaultDisabledKey)
    }
}

private extension NagramSettings {
    var disabledMessageMenuItemIds: Set<NagramMessageMenuItemId> {
        return Set(self.messageMenuIds(from: UserDefaults.standard.string(forKey: nagramMessageMenuDisabledKey)))
    }

    var enabledDefaultDisabledMessageMenuItemIds: Set<NagramMessageMenuItemId> {
        return Set(self.messageMenuIds(from: UserDefaults.standard.string(forKey: nagramMessageMenuEnabledDefaultDisabledKey)))
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
