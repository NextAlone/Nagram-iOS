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

public enum NagramProfilePaneScope: String, CaseIterable {
    case user
    case bot
    case group
    case channel
    case myProfile
    case savedMessages

    public var panes: [NagramProfilePane] {
        return NagramProfilePane.allCases.filter { pane in
            switch pane {
            case .botPreview, .similarBots: return self == .bot
            case .members: return self == .group
            case .similarChannels: return self == .channel
            case .storyArchive: return self == .myProfile
            case .savedMessagesChats: return self == .savedMessages
            case .stories: return self != .savedMessages
            case .gifts: return self == .user || self == .channel || self == .myProfile
            case .groupsInCommon: return self == .user || self == .bot
            case .savedMessages: return self != .myProfile && self != .savedMessages
            case .media, .files, .music, .voice, .links, .gifs, .polls: return self != .myProfile
            }
        }
    }

    fileprivate var settingsKey: String { return "nagram.profilePanes.byType.\(self.rawValue)" }
}

public struct NagramProfilePaneSettings: Equatable {
    // Preserve identifiers from newer clients when editing preferences synced through iCloud.
    fileprivate var order: [String] = []
    fileprivate var hidden: Set<String> = []

    public init() {}

    fileprivate init(order: [String], hidden: [String]) {
        var seen = Set<String>()
        self.order = order.filter { seen.insert($0).inserted }
        self.hidden = Set(hidden)
    }

    fileprivate func save(for scope: NagramProfilePaneScope, defaults: UserDefaults) {
        NagramSettingsCloudSync.shared.set(["order": self.order, "hidden": self.hidden.sorted()], forKey: scope.settingsKey, defaults: defaults)
    }

    /// Replace only the slots that the user has ordered. New or unranked tabs keep their native positions.
    public func ordered(_ available: [NagramProfilePane]) -> [NagramProfilePane] {
        return reorderProfilePanes(available, by: self.order.compactMap(NagramProfilePane.init(rawValue:)))
    }

    public func overridesMainPane(_ pane: NagramProfilePane, in available: [NagramProfilePane]) -> Bool {
        let serverOrder = [pane] + available.filter { $0 != pane }
        return self.ordered(serverOrder).first(where: { !self.isHidden($0) }) != pane
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
    func profilePaneSettings(for scope: NagramProfilePaneScope, defaults: UserDefaults = NagramDemoMode.userDefaults) -> NagramProfilePaneSettings {
        if let stored = defaults.dictionary(forKey: scope.settingsKey) as? [String: [String]] {
            return NagramProfilePaneSettings(order: stored["order"] ?? [], hidden: stored["hidden"] ?? [])
        }
        // A type inherits the previous global preferences until the first edit of that type.
        func legacyIds(_ key: String) -> [String] {
            return (defaults.string(forKey: key) ?? "").split(separator: ",").map(String.init)
        }
        return NagramProfilePaneSettings(order: legacyIds("nagram.profilePanes.order"), hidden: legacyIds("nagram.profilePanes.hidden"))
    }

    func setProfilePaneHidden(_ hidden: Bool, for pane: NagramProfilePane, in scope: NagramProfilePaneScope, defaults: UserDefaults = NagramDemoMode.userDefaults) {
        var settings = self.profilePaneSettings(for: scope, defaults: defaults)
        if hidden {
            settings.hidden.insert(pane.rawValue)
        } else {
            settings.hidden.remove(pane.rawValue)
        }
        settings.save(for: scope, defaults: defaults)
    }

    func setProfilePaneOrder(_ panes: [NagramProfilePane], in scope: NagramProfilePaneScope, defaults: UserDefaults = NagramDemoMode.userDefaults) {
        var settings = self.profilePaneSettings(for: scope, defaults: defaults)
        var seen = Set<String>()
        let requested = panes.map(\.rawValue).filter { seen.insert($0).inserted }
        // Hidden and unavailable tabs retain their slots when editing a subset on a profile.
        let combined = settings.order + requested.filter { !settings.order.contains($0) }
        settings.order = reorderProfilePanes(combined, by: requested)
        settings.save(for: scope, defaults: defaults)
    }
}
