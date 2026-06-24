import Foundation

public enum NagramBottomBarItemId: String, CaseIterable, Hashable {
    case contacts
    case calls
    case chats
    case settings
    case search

    public var isNavigationItem: Bool {
        switch self {
        case .contacts, .calls, .chats, .settings:
            return true
        case .search:
            return false
        }
    }
}

public enum NagramBottomBarWidthMode: String {
    case full
    case adaptive
}

public enum NagramBottomBarSlotMode: String {
    case visibleOnly
    case preserveHidden
}

public enum NagramBottomBarAlignment: String {
    case left
    case center
}

public enum NagramBottomBarSearchMode: String {
    case button
    case bar
    case hidden
}

public struct NagramBottomBarSettings: Equatable {
    public static let defaultBottomItems: [NagramBottomBarItemId] = [.contacts, .calls, .chats, .settings]

    public var isBottomBarVisible: Bool
    public var bottomItems: [NagramBottomBarItemId]
    public var externalItem: NagramBottomBarItemId?
    public var hiddenItems: Set<NagramBottomBarItemId>
    public var topSearchVisible: Bool
    public var showLabels: Bool
    public var widthMode: NagramBottomBarWidthMode
    public var slotMode: NagramBottomBarSlotMode
    public var buttonWidthFillRatio: Int32
    public var alignment: NagramBottomBarAlignment
    public var searchMode: NagramBottomBarSearchMode

    public init(
        isBottomBarVisible: Bool = true,
        bottomItems: [NagramBottomBarItemId] = NagramBottomBarSettings.defaultBottomItems,
        externalItem: NagramBottomBarItemId? = .search,
        hiddenItems: Set<NagramBottomBarItemId> = [],
        topSearchVisible: Bool = true,
        showLabels: Bool = true,
        widthMode: NagramBottomBarWidthMode = .full,
        slotMode: NagramBottomBarSlotMode = .visibleOnly,
        buttonWidthFillRatio: Int32 = 100,
        alignment: NagramBottomBarAlignment = .center,
        searchMode: NagramBottomBarSearchMode = .button
    ) {
        self.isBottomBarVisible = isBottomBarVisible
        self.bottomItems = bottomItems
        self.externalItem = externalItem
        self.hiddenItems = hiddenItems
        self.topSearchVisible = topSearchVisible
        self.showLabels = showLabels
        self.widthMode = widthMode
        self.slotMode = slotMode
        self.buttonWidthFillRatio = buttonWidthFillRatio
        self.alignment = alignment
        self.searchMode = searchMode
        self.normalize()
    }

    public var visibleBottomItems: [NagramBottomBarItemId] {
        guard self.isBottomBarVisible else {
            return []
        }
        return self.bottomItems.filter { item in
            return item != .search && !self.hiddenItems.contains(item) && self.externalItem != item
        }
    }

    public var visibleNavigationItems: [NagramBottomBarItemId] {
        var result = self.visibleBottomItems.filter(\.isNavigationItem)
        if let externalItem = self.externalItem, externalItem.isNavigationItem, !self.hiddenItems.contains(externalItem) {
            result.append(externalItem)
        }
        return result
    }

    public func isVisible(_ item: NagramBottomBarItemId) -> Bool {
        if item == .search {
            return self.searchMode != .hidden && !self.hiddenItems.contains(.search)
        }
        if self.hiddenItems.contains(item) {
            return false
        }
        return self.bottomItems.contains(item) || self.externalItem == item
    }

    public var hiddenOrAvailableItems: [NagramBottomBarItemId] {
        let hiddenItems = NagramBottomBarItemId.allCases.filter { self.hiddenItems.contains($0) }
        let availableItems = NagramBottomBarItemId.allCases.filter { item in
            !self.hiddenItems.contains(item) && !self.isVisible(item)
        }
        return hiddenItems + availableItems
    }

    public mutating func toggleHidden(_ item: NagramBottomBarItemId) {
        if item == .search {
            if self.hiddenItems.contains(.search) {
                self.hiddenItems.remove(.search)
                self.searchMode = .button
                self.externalItem = .search
            } else {
                self.hiddenItems.insert(.search)
                self.searchMode = .hidden
                if self.externalItem == .search {
                    self.externalItem = nil
                }
            }
            self.bottomItems.removeAll(where: { $0 == .search })
            self.normalize()
            return
        }
        if self.hiddenItems.contains(item) {
            self.hiddenItems.remove(item)
            if self.externalItem != item && !self.bottomItems.contains(item) {
                self.bottomItems.append(item)
            }
        } else {
            self.hiddenItems.insert(item)
            self.bottomItems.removeAll(where: { $0 == item })
            if self.externalItem == item {
                self.externalItem = nil
            }
        }
        self.normalize()
    }

    public mutating func hide(_ item: NagramBottomBarItemId) {
        if !self.hiddenItems.contains(item) {
            self.hiddenItems.insert(item)
        }
        if item == .search {
            self.searchMode = .hidden
        }
        self.bottomItems.removeAll(where: { $0 == item })
        if self.externalItem == item {
            self.externalItem = nil
        }
        self.normalize()
    }

    public mutating func show(_ item: NagramBottomBarItemId) {
        if item == .search {
            self.hiddenItems.remove(.search)
            if self.searchMode == .hidden {
                self.searchMode = .button
            }
            self.normalize()
            return
        }
        self.hiddenItems.remove(item)
        if self.externalItem != item && !self.bottomItems.contains(item) {
            self.bottomItems.append(item)
        }
        self.normalize()
    }

    public mutating func setVisible(_ item: NagramBottomBarItemId, visible: Bool) {
        if visible {
            self.show(item)
        } else {
            self.hide(item)
        }
    }

    public mutating func moveBottomItem(from sourceIndex: Int, to targetIndex: Int) {
        guard self.bottomItems.indices.contains(sourceIndex) else {
            return
        }
        let item = self.bottomItems.remove(at: sourceIndex)
        let index = max(0, min(targetIndex, self.bottomItems.count))
        self.bottomItems.insert(item, at: index)
        self.normalize()
    }

    public mutating func moveToExternal(_ item: NagramBottomBarItemId) {
        if item == .search {
            self.hiddenItems.remove(.search)
            self.searchMode = .button
            self.bottomItems.removeAll(where: { $0 == .search })
            self.externalItem = .search
            self.normalize()
            return
        }
        self.hiddenItems.remove(item)
        let replacementIndex = self.bottomItems.firstIndex(of: item) ?? self.bottomItems.count
        self.bottomItems.removeAll(where: { $0 == item })
        if let previous = self.externalItem, previous != item, !self.hiddenItems.contains(previous) {
            let index = max(0, min(replacementIndex, self.bottomItems.count))
            self.bottomItems.insert(previous, at: index)
        }
        self.externalItem = item
        self.normalize()
    }

    public mutating func moveToBottom(_ item: NagramBottomBarItemId, at targetIndex: Int) {
        if item == .search {
            self.hiddenItems.remove(.search)
            self.searchMode = .button
            self.bottomItems.removeAll(where: { $0 == .search })
            self.externalItem = .search
            self.normalize()
            return
        }
        self.hiddenItems.remove(item)
        if self.externalItem == item {
            self.externalItem = nil
        }
        self.bottomItems.removeAll(where: { $0 == item })
        let index = max(0, min(targetIndex, self.bottomItems.count))
        self.bottomItems.insert(item, at: index)
        self.normalize()
    }

    public mutating func setSearchMode(_ mode: NagramBottomBarSearchMode) {
        self.searchMode = mode
        if mode == .hidden {
            self.hiddenItems.insert(.search)
        } else {
            self.hiddenItems.remove(.search)
        }
        self.normalize()
    }

    public mutating func reset() {
        self = NagramBottomBarSettings()
    }

    private mutating func normalize() {
        self.bottomItems.removeAll(where: { $0 == .search })

        if self.searchMode == .hidden || self.hiddenItems.contains(.search) {
            self.searchMode = .hidden
            self.hiddenItems.insert(.search)
            if self.externalItem == .search {
                self.externalItem = nil
            }
        } else {
            if self.searchMode != .bar {
                self.searchMode = .button
            }
            self.hiddenItems.remove(.search)
            if let externalItem = self.externalItem, externalItem != .search, !self.hiddenItems.contains(externalItem), !self.bottomItems.contains(externalItem) {
                self.bottomItems.append(externalItem)
            }
            self.externalItem = self.searchMode == .bar ? nil : .search
        }

        var seen = Set<NagramBottomBarItemId>()
        self.bottomItems = self.bottomItems.compactMap { item in
            guard !seen.contains(item), !self.hiddenItems.contains(item), self.externalItem != item else {
                return nil
            }
            seen.insert(item)
            return item
        }

        if let externalItem = self.externalItem {
            if self.hiddenItems.contains(externalItem) {
                self.externalItem = nil
            } else {
                seen.insert(externalItem)
            }
        }

        self.hiddenItems = self.hiddenItems.filter { NagramBottomBarItemId.allCases.contains($0) }
        for item in self.hiddenItems {
            seen.insert(item)
        }

        for item in NagramBottomBarItemId.allCases where !seen.contains(item) && item != .search {
            self.bottomItems.append(item)
            seen.insert(item)
        }
        self.buttonWidthFillRatio = max(0, min(100, self.buttonWidthFillRatio))
    }
}

public extension NagramBottomBarSettings {
    private enum Keys {
        static let marker = "nagram.bottomBarLayout.version"
        static let isBottomBarVisible = "nagram.bottomBarLayout.isBottomBarVisible"
        static let bottomItems = "nagram.bottomBarLayout.bottomItems"
        static let externalItem = "nagram.bottomBarLayout.externalItem"
        static let hiddenItems = "nagram.bottomBarLayout.hiddenItems"
        static let topSearchVisible = "nagram.bottomBarLayout.topSearchVisible"
        static let showLabels = "nagram.bottomBarLayout.showLabels"
        static let widthMode = "nagram.bottomBarLayout.widthMode"
        static let slotMode = "nagram.bottomBarLayout.slotMode"
        static let buttonWidthFillRatio = "nagram.bottomBarLayout.buttonWidthFillRatio"
        static let alignment = "nagram.bottomBarLayout.alignment"
        static let searchMode = "nagram.bottomBarLayout.searchMode"
    }

    static func load(from defaults: UserDefaults = .standard) -> NagramBottomBarSettings {
        if defaults.object(forKey: Keys.marker) == nil {
            let migratedSettings = self.legacySettings(from: defaults)
            migratedSettings.save(to: defaults)
            return migratedSettings
        }

        let bottomItems = Self.itemIds(forKey: Keys.bottomItems, defaults: defaults)
        let hiddenItems = Set(Self.itemIds(forKey: Keys.hiddenItems, defaults: defaults))
        let externalItem = defaults.string(forKey: Keys.externalItem).flatMap(NagramBottomBarItemId.init(rawValue:))
        let widthMode = defaults.string(forKey: Keys.widthMode).flatMap(NagramBottomBarWidthMode.init(rawValue:)) ?? .full
        let buttonWidthFillRatio = (defaults.object(forKey: Keys.buttonWidthFillRatio) as? NSNumber)?.int32Value ?? (widthMode == .full ? 100 : 0)
        let searchMode = defaults.string(forKey: Keys.searchMode).flatMap(NagramBottomBarSearchMode.init(rawValue:)) ?? .button

        return NagramBottomBarSettings(
            isBottomBarVisible: defaults.object(forKey: Keys.isBottomBarVisible) as? Bool ?? true,
            bottomItems: bottomItems.isEmpty ? Self.defaultBottomItems : bottomItems,
            externalItem: externalItem,
            hiddenItems: hiddenItems,
            topSearchVisible: defaults.object(forKey: Keys.topSearchVisible) as? Bool ?? true,
            showLabels: defaults.object(forKey: Keys.showLabels) as? Bool ?? true,
            widthMode: widthMode,
            slotMode: defaults.string(forKey: Keys.slotMode).flatMap(NagramBottomBarSlotMode.init(rawValue:)) ?? .visibleOnly,
            buttonWidthFillRatio: buttonWidthFillRatio,
            alignment: defaults.string(forKey: Keys.alignment).flatMap(NagramBottomBarAlignment.init(rawValue:)) ?? .center,
            searchMode: hiddenItems.contains(.search) ? .hidden : searchMode
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(1, forKey: Keys.marker)
        defaults.set(self.isBottomBarVisible, forKey: Keys.isBottomBarVisible)
        defaults.set(self.bottomItems.map(\.rawValue), forKey: Keys.bottomItems)
        if let externalItem = self.externalItem {
            defaults.set(externalItem.rawValue, forKey: Keys.externalItem)
        } else {
            defaults.removeObject(forKey: Keys.externalItem)
        }
        defaults.set(NagramBottomBarItemId.allCases.filter { self.hiddenItems.contains($0) }.map(\.rawValue), forKey: Keys.hiddenItems)
        defaults.set(self.topSearchVisible, forKey: Keys.topSearchVisible)
        defaults.set(self.showLabels, forKey: Keys.showLabels)
        defaults.set(self.widthMode.rawValue, forKey: Keys.widthMode)
        defaults.set(self.slotMode.rawValue, forKey: Keys.slotMode)
        defaults.set(self.buttonWidthFillRatio, forKey: Keys.buttonWidthFillRatio)
        defaults.set(self.alignment.rawValue, forKey: Keys.alignment)
        defaults.set(self.searchMode.rawValue, forKey: Keys.searchMode)

        defaults.set(!self.isBottomBarVisible, forKey: "nagram.hideTabBar")
        defaults.set(!self.isVisible(.contacts), forKey: "nagram.hideTabBarContacts")
        defaults.set(!self.isVisible(.chats), forKey: "nagram.hideTabBarChats")
        defaults.set(!self.isVisible(.settings), forKey: "nagram.hideTabBarSettings")
        defaults.set(!self.topSearchVisible, forKey: "nagram.showTabBarSearch")
        defaults.set(self.buttonWidthFillRatio >= 100, forKey: "nagram.wideTabBar")
    }

    private static func itemIds(forKey key: String, defaults: UserDefaults) -> [NagramBottomBarItemId] {
        guard let values = defaults.object(forKey: key) as? [Any] else {
            return []
        }
        return values.compactMap { value -> NagramBottomBarItemId? in
            if let value = value as? String {
                return NagramBottomBarItemId(rawValue: value)
            }
            if let value = value as? NSString {
                return NagramBottomBarItemId(rawValue: value as String)
            }
            return nil
        }
    }

    private static func legacySettings(from defaults: UserDefaults) -> NagramBottomBarSettings {
        let hideAll = defaults.object(forKey: "nagram.hideTabBar") as? Bool ?? false
        let hideContacts = defaults.object(forKey: "nagram.hideTabBarContacts") as? Bool ?? false
        let hideChats = defaults.object(forKey: "nagram.hideTabBarChats") as? Bool ?? false
        let hideSettings = defaults.object(forKey: "nagram.hideTabBarSettings") as? Bool ?? false
        let hideTopSearch = defaults.object(forKey: "nagram.showTabBarSearch") as? Bool ?? false
        let wideTabBar = defaults.object(forKey: "nagram.wideTabBar") as? Bool ?? true

        var hiddenItems = Set<NagramBottomBarItemId>()
        if hideContacts {
            hiddenItems.insert(.contacts)
        }
        if hideChats {
            hiddenItems.insert(.chats)
        }
        if hideSettings {
            hiddenItems.insert(.settings)
        }

        return NagramBottomBarSettings(
            isBottomBarVisible: !hideAll,
            bottomItems: Self.defaultBottomItems,
            externalItem: .search,
            hiddenItems: hiddenItems,
            topSearchVisible: !hideTopSearch,
            showLabels: true,
            widthMode: wideTabBar ? .full : .adaptive,
            slotMode: wideTabBar ? .visibleOnly : .preserveHidden,
            buttonWidthFillRatio: wideTabBar ? 100 : 0,
            alignment: wideTabBar ? .center : .left,
            searchMode: .button
        )
    }
}
