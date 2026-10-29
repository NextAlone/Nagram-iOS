import Foundation

/// How the composer offers text styles: the keyboard-area panel behind the format button, a bar that
/// stays under the input field while typing, or both.
public enum NagramTextStyleToolbarMode: String, CaseIterable {
    case off
    case panel
    case bar
    case both

    public var showsPanel: Bool {
        return self == .panel || self == .both
    }

    public var showsBar: Bool {
        return self == .bar || self == .both
    }
}

private let nagramTextStyleToolbarModeKey = "nagram.textStyleToolbarMode"

public extension NagramSettings {
    /// Until a mode is chosen, the former on/off switch (`nagram.showTextStyleToolbar`) decides,
    /// so an upgrade keeps each user's existing behavior.
    var textStyleToolbarMode: NagramTextStyleToolbarMode {
        get {
            if let stored = NagramDemoMode.userDefaults.string(forKey: nagramTextStyleToolbarModeKey), let mode = NagramTextStyleToolbarMode(rawValue: stored) {
                return mode
            }
            return self.showTextStyleToolbar ? .panel : .off
        }
        set {
            NagramSettingsCloudSync.shared.set(newValue.rawValue, forKey: nagramTextStyleToolbarModeKey)
        }
    }
}

private let nagramTextStyleToolbarOrderKey = "nagram.textStyleToolbar.order"
private let nagramTextStyleToolbarHiddenKey = "nagram.textStyleToolbar.hidden"

/// The order and the styles of the keyboard-area panel and the bar under the input field, which share
/// one list. Every style is shown until the user hides it, so an upgrade keeps the full set.
public extension NagramSettings {
    var textStyleToolbarItemOrder: [NagramTextStyleMenuItemId] {
        get {
            return nagramNormalizedTextStyleIds(nagramTextStyleIds(from: NagramDemoMode.userDefaults.string(forKey: nagramTextStyleToolbarOrderKey)))
        }
        set {
            NagramSettingsCloudSync.shared.set(nagramNormalizedTextStyleIds(newValue).map(\.rawValue).joined(separator: ","), forKey: nagramTextStyleToolbarOrderKey)
        }
    }

    func isTextStyleToolbarItemEnabled(_ id: NagramTextStyleMenuItemId) -> Bool {
        return !self.hiddenTextStyleToolbarItemIds.contains(id)
    }

    func setTextStyleToolbarItemEnabled(_ id: NagramTextStyleMenuItemId, enabled: Bool) {
        var ids = self.hiddenTextStyleToolbarItemIds
        if enabled {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        NagramSettingsCloudSync.shared.set(ids.map(\.rawValue).sorted().joined(separator: ","), forKey: nagramTextStyleToolbarHiddenKey)
    }

    /// The shown styles in the user's order.
    var enabledTextStyleToolbarItems: [NagramTextStyleMenuItemId] {
        let hidden = self.hiddenTextStyleToolbarItemIds
        return self.textStyleToolbarItemOrder.filter { !hidden.contains($0) }
    }

    func resetTextStyleToolbarItems() {
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramTextStyleToolbarOrderKey)
        NagramSettingsCloudSync.shared.removeObject(forKey: nagramTextStyleToolbarHiddenKey)
    }

    private var hiddenTextStyleToolbarItemIds: Set<NagramTextStyleMenuItemId> {
        return Set(nagramTextStyleIds(from: NagramDemoMode.userDefaults.string(forKey: nagramTextStyleToolbarHiddenKey)))
    }
}

public extension NagramTextStyleMenuItemId {
    /// The glyph the panel, the bar and the settings preview draw for the style.
    var glyph: String {
        switch self {
        case .quote:
            return "❝"
        case .spoiler:
            return "||"
        case .bold:
            return "B"
        case .italic:
            return "I"
        case .monospace:
            return "`"
        case .link:
            return "↗"
        case .date:
            return "◷"
        case .strikethrough:
            return "S"
        case .underline:
            return "U"
        case .code:
            return "</>"
        }
    }
}

func nagramTextStyleIds(from string: String?) -> [NagramTextStyleMenuItemId] {
    guard let string, !string.isEmpty else {
        return []
    }
    return string.split(separator: ",").compactMap { NagramTextStyleMenuItemId(rawValue: String($0)) }
}

/// Removes duplicates and appends any style the stored list does not name, in the default order.
func nagramNormalizedTextStyleIds(_ ids: [NagramTextStyleMenuItemId]) -> [NagramTextStyleMenuItemId] {
    var result: [NagramTextStyleMenuItemId] = []
    var seen = Set<NagramTextStyleMenuItemId>()
    for id in ids + NagramTextStyleMenuItemId.allCases {
        if seen.insert(id).inserted {
            result.append(id)
        }
    }
    return result
}
