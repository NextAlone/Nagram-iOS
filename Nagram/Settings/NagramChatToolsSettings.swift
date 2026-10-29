import Foundation

/// The buttons of the chat tools bar at the top of a chat.
public enum NagramChatToolId: String, CaseIterable {
    case search
    case media
    case pinned
    case beginning
    case notifications
    case cache
    case latest
    case mentions
    case select
    case translate
    case manage

    /// Tools added after the first release stay hidden until the user turns them on, so an upgrade keeps the bar as it was.
    static let hiddenByDefault: Set<NagramChatToolId> = [.latest, .mentions, .select, .translate, .manage]
}

/// How large the chat tools bar draws its buttons.
public enum NagramChatToolsSize: String, CaseIterable {
    /// Icons only.
    case compact
    /// Icons with small titles.
    case standard
    /// Icons with titles, as the bar first shipped.
    case large
}

private let nagramChatToolsOrderKey = "nagram.chatTools.order"
private let nagramChatToolsHiddenKey = "nagram.chatTools.hidden"
private let nagramChatToolsSizeKey = "nagram.chatTools.size"

public extension NagramSettings {
    var chatToolsOrder: [NagramChatToolId] {
        get {
            return nagramNormalizedChatToolIds(nagramChatToolIds(from: NagramDemoMode.userDefaults.string(forKey: nagramChatToolsOrderKey)))
        }
        set {
            NagramSettingsCloudSync.shared.set(nagramNormalizedChatToolIds(newValue).map(\.rawValue).joined(separator: ","), forKey: nagramChatToolsOrderKey)
        }
    }

    func isChatToolEnabled(_ id: NagramChatToolId) -> Bool {
        return !self.hiddenChatToolIds.contains(id)
    }

    func setChatToolEnabled(_ id: NagramChatToolId, enabled: Bool) {
        var ids = self.hiddenChatToolIds
        if enabled {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        NagramSettingsCloudSync.shared.set(ids.map(\.rawValue).sorted().joined(separator: ","), forKey: nagramChatToolsHiddenKey)
    }

    /// The shown tools in the user's order.
    var enabledChatTools: [NagramChatToolId] {
        let hidden = self.hiddenChatToolIds
        return self.chatToolsOrder.filter { !hidden.contains($0) }
    }

    var chatToolsSize: NagramChatToolsSize {
        get {
            return NagramDemoMode.userDefaults.string(forKey: nagramChatToolsSizeKey).flatMap(NagramChatToolsSize.init(rawValue:)) ?? .standard
        }
        set {
            NagramSettingsCloudSync.shared.set(newValue.rawValue, forKey: nagramChatToolsSizeKey)
        }
    }

    func resetChatTools() {
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramChatToolsOrderKey)
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramChatToolsHiddenKey)
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramChatToolsSizeKey)
    }

    private var hiddenChatToolIds: Set<NagramChatToolId> {
        guard let stored = NagramDemoMode.userDefaults.string(forKey: nagramChatToolsHiddenKey) else {
            return NagramChatToolId.hiddenByDefault
        }
        return Set(nagramChatToolIds(from: stored))
    }
}

private func nagramChatToolIds(from string: String?) -> [NagramChatToolId] {
    guard let string, !string.isEmpty else {
        return []
    }
    return string.split(separator: ",").compactMap { NagramChatToolId(rawValue: String($0)) }
}

private func nagramNormalizedChatToolIds(_ ids: [NagramChatToolId]) -> [NagramChatToolId] {
    var result: [NagramChatToolId] = []
    var seen = Set<NagramChatToolId>()
    for id in ids + NagramChatToolId.allCases {
        if seen.insert(id).inserted {
            result.append(id)
        }
    }
    return result
}
