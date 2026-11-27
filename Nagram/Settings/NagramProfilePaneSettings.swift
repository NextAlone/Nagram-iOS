import Foundation

public enum NagramProfilePane: String, CaseIterable {
    case botPreview
    case members
    case stories
    case gifts
    case media
    case savedMessagesChats
    case savedMessages
    case files
    case music
    case voice
    case links
    case gifs
    case polls
    case groupsInCommon
    case similarChannels
    case similarBots
    case storyArchive
}

public struct NagramProfilePaneSettings: Equatable {
    // Preserve identifiers from newer clients when editing preferences synced through iCloud.
    fileprivate let order: [String]
    fileprivate let hidden: Set<String>

    /// Replace only the slots that the user has ordered. New or unranked tabs keep their native positions.
    public func ordered(_ available: [NagramProfilePane]) -> [NagramProfilePane] {
        return reorderProfilePanes(available, by: self.order.compactMap(NagramProfilePane.init(rawValue:)))
    }

    public func isHidden(_ pane: NagramProfilePane) -> Bool {
        return self.hidden.contains(pane.rawValue)
    }
}

private func reorderProfilePanes<Pane: Equatable>(_ panes: [Pane], by order: [Pane]) -> [Pane] {
    let ranked = order.filter(panes.contains)
    var replacements = ranked.makeIterator()
    return panes.map { pane in
        if ranked.contains(pane), let replacement = replacements.next() {
            return replacement
        }
        return pane
    }
}

public extension NagramSettings {
    var profilePaneSettings: NagramProfilePaneSettings {
        let defaults = NagramDemoMode.userDefaults
        func ids(forKey key: String) -> [String] {
            var seen = Set<String>()
            return (defaults.string(forKey: key) ?? "").split(separator: ",").map(String.init).filter { seen.insert($0).inserted }
        }
        return NagramProfilePaneSettings(order: ids(forKey: "nagram.profilePanes.order"), hidden: Set(ids(forKey: "nagram.profilePanes.hidden")))
    }

    func setProfilePaneHidden(_ hidden: Bool, for pane: NagramProfilePane) {
        var panes = self.profilePaneSettings.hidden
        if hidden {
            panes.insert(pane.rawValue)
        } else {
            panes.remove(pane.rawValue)
        }
        NagramSettingsCloudSync.shared.set(panes.sorted().joined(separator: ","), forKey: "nagram.profilePanes.hidden")
    }

    func setProfilePaneOrder(_ panes: [NagramProfilePane]) {
        var seen = Set<String>()
        let requested = panes.map(\.rawValue).filter { seen.insert($0).inserted }
        let previous = self.profilePaneSettings.order
        // Hidden and unavailable tabs retain their slots when editing a subset on a profile.
        let combined = previous + requested.filter { !previous.contains($0) }
        let order = reorderProfilePanes(combined, by: requested)
        NagramSettingsCloudSync.shared.set(order.joined(separator: ","), forKey: "nagram.profilePanes.order")
    }
}
