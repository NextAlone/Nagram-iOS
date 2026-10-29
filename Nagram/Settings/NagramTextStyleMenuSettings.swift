import Foundation

/// Text styles that can be flattened onto the first level of the composer's selection menu.
public enum NagramTextStyleMenuItemId: String, CaseIterable {
    case quote
    case spoiler
    case bold
    case italic
    case monospace
    case link
    case date
    case strikethrough
    case underline
    case code
}

/// Where the flattened styles go in the selection menu. The full Format submenu keeps its own place,
/// right after the system Cut/Copy/Paste group.
public enum NagramTextStyleMenuPosition: String, CaseIterable {
    case first
    case beforeFormat
    case afterFormat
    case last
}

private let nagramTextStyleMenuOrderKey = "nagram.textStyleMenu.order"
private let nagramTextStyleMenuEnabledKey = "nagram.textStyleMenu.enabled"
private let nagramTextStyleMenuPositionKey = "nagram.textStyleMenu.position"

public extension NagramSettings {
    var textStyleMenuItemOrder: [NagramTextStyleMenuItemId] {
        get {
            return nagramNormalizedTextStyleIds(nagramTextStyleIds(from: NagramDemoMode.userDefaults.string(forKey: nagramTextStyleMenuOrderKey)))
        }
        set {
            let order = nagramNormalizedTextStyleIds(newValue)
            NagramSettingsCloudSync.shared.set(order.map(\.rawValue).joined(separator: ","), forKey: nagramTextStyleMenuOrderKey)
        }
    }

    /// Nothing is flattened until the user picks styles, so the menu is unchanged by default.
    func isTextStyleMenuItemEnabled(_ id: NagramTextStyleMenuItemId) -> Bool {
        return self.enabledTextStyleMenuItemIds.contains(id)
    }

    func setTextStyleMenuItemEnabled(_ id: NagramTextStyleMenuItemId, enabled: Bool) {
        var ids = self.enabledTextStyleMenuItemIds
        if enabled {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        NagramSettingsCloudSync.shared.set(ids.map(\.rawValue).sorted().joined(separator: ","), forKey: nagramTextStyleMenuEnabledKey)
    }

    /// The enabled styles in the user's order.
    var enabledTextStyleMenuItems: [NagramTextStyleMenuItemId] {
        let enabled = self.enabledTextStyleMenuItemIds
        return self.textStyleMenuItemOrder.filter { enabled.contains($0) }
    }

    var textStyleMenuPosition: NagramTextStyleMenuPosition {
        get {
            return NagramDemoMode.userDefaults.string(forKey: nagramTextStyleMenuPositionKey).flatMap(NagramTextStyleMenuPosition.init(rawValue:)) ?? .beforeFormat
        }
        set {
            NagramSettingsCloudSync.shared.set(newValue.rawValue, forKey: nagramTextStyleMenuPositionKey)
        }
    }

    func resetTextStyleMenu() {
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramTextStyleMenuOrderKey)
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramTextStyleMenuEnabledKey)
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramTextStyleMenuPositionKey)
    }
}

private extension NagramSettings {
    var enabledTextStyleMenuItemIds: Set<NagramTextStyleMenuItemId> {
        return Set(nagramTextStyleIds(from: NagramDemoMode.userDefaults.string(forKey: nagramTextStyleMenuEnabledKey)))
    }
}
