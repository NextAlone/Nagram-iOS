import Foundation

enum NagramSettingsSyncKeys {
    private static let cloudPrefix = "nagram.settings."

    private static let explicitKeys: Set<String> = [
        "nagram.forceCopyEnabled",
        "nagram.skipSensitiveContentWarning",
        "nagram.hideReactions",
        "nagram.disableScrollToNextChannel",
        "nagram.disableScrollToNextTopic",
        "nagram.disableGalleryCamera",
        "nagram.disableGalleryCameraPreview",
        "nagram.disableSendAsButton",
        "nagram.hideRecordingButton",
        "nagram.secondsInMessages",
        "nagram.showForwardedMessageDate",
        "nagram.hideChannelBottomButton",
        "nagram.hideSponsoredMessages",
        "nagram.hidePrivateChatActivities",
        "nagram.confirmCalls",
        "nagram.showDC",
        "nagram.controlHighlightEnabled",
        "nagram.glassTransparencyMode",
        "nagram.glassTransparencyPercent",
        "nagram.stickerSize",
        "nagram.stickerTimestamp",
        "nagram.videoPIPSwipeDirection",
        "nagram.chatListSwipeAction",
        "nagram.openArchiveOnPull",
        "nagram.showArchiveInFolders",
        "nagram.hideSavedAndArchivedMessagesInList",
        "nagram.disableCommunityChatGrouping",
        "nagram.chatListStartupFolderMode",
        "nagram.chatListFolderTabsCompact",
        "nagram.hideAllChatsFolder",
        "nagram.showFoldersInShareSheet",
        "nagram.chatListFolderTabDisplayMode",
        "nagram.chatListMessagePreviewStyle",
        "nagram.chatListLines",
        "nagram.chatListCompact",
        "nagram.recentChatsEnabled",
        "nagram.tapMessageRowToOpenContextMenu",
        "nagram.messageDoubleTapAction",
        "nagram.messageDoubleTapActionWithoutEditPermission",
        "nagram.showProfileId",
        "nagram.uploadSpeedBoost",
        "nagram.downloadSpeedBoost",
        "nagram.translationProvider",
        "nagram.translationLLMAPIFormat",
        "nagram.translationLLMBaseURL",
        "nagram.translationLLMEndpoint",
        "nagram.translationLLMModel",
        "nagram.translationLLMPrompt",
        "nagram.translationLLMUseContext",
        "nagram.translationLLMTemperatureTenths",
        "nagram.sendWithReturnKey",
        "nagram.showTextStyleToolbar",
        "nagram.enablePanguOnSending",
        "nagram.enablePanguOnEditing",
        "nagram.enablePanguOnReceiving",
        "nagram.wideChannelPosts",
        "nagram.recentStickerLimit",
        "nagram.hideStories",
        "nagram.showRegDate",
        "nagram.groupProfileSettingItems",
        "nagram.hidePhoneInSettings",
        "nagram.bottomBarLayout.version",
        "nagram.bottomBarLayout.isBottomBarVisible",
        "nagram.bottomBarLayout.bottomItems",
        "nagram.bottomBarLayout.externalItem",
        "nagram.bottomBarLayout.hiddenItems",
        "nagram.bottomBarLayout.topSearchVisible",
        "nagram.bottomBarLayout.showLabels",
        "nagram.bottomBarLayout.widthMode",
        "nagram.bottomBarLayout.slotMode",
        "nagram.bottomBarLayout.buttonWidthFillRatio",
        "nagram.bottomBarLayout.alignment",
        "nagram.bottomBarLayout.searchMode",
        "nagram.hideTabBar",
        "nagram.hideTabBarContacts",
        "nagram.hideTabBarChats",
        "nagram.hideTabBarSettings",
        "nagram.showTabBarSearch",
        "nagram.wideTabBar",
        "nagram.messageMenu.order",
        "nagram.messageMenu.disabled",
        "nagram.messageMenu.enabledDefaultDisabled",
        "nagram.regexFilters.rules",
        "nagram.regexFilters.disabledPeerIds"
    ]

    private static let syncedPrefixes: [String] = [
        "nagram.chatListStartupSpecificFolder.",
        "nagram.recentChatFolders.",
        "nagram.autoTranslate."
    ]

    static func shouldSync(localKey: String) -> Bool {
        if explicitKeys.contains(localKey) {
            return true
        }
        return syncedPrefixes.contains(where: { localKey.hasPrefix($0) })
    }

    static func cloudKey(for localKey: String) -> String {
        return cloudPrefix + localKey
    }

    static func localKey(fromCloudKey cloudKey: String) -> String? {
        guard cloudKey.hasPrefix(cloudPrefix) else {
            return nil
        }
        let index = cloudKey.index(cloudKey.startIndex, offsetBy: cloudPrefix.count)
        let localKey = String(cloudKey[index...])
        return self.shouldSync(localKey: localKey) ? localKey : nil
    }
}

final class NagramSettingsCloudSync {
    static let shared = NagramSettingsCloudSync()
    private static let enabledKey = "nagram.iCloudSyncEnabled"

    private let store = NSUbiquitousKeyValueStore.default
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var isStarted = false
    private var isApplyingCloudChange = false

    private init() {}

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        return defaults.bool(forKey: self.enabledKey)
    }

    func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        guard defaults === UserDefaults.standard else {
            return
        }
        if enabled {
            self.start()
        } else {
            self.stop()
        }
    }

    func start() {
        guard Self.isEnabled() else {
            return
        }

        self.lock.lock()
        if self.isStarted {
            self.lock.unlock()
            return
        }
        self.isStarted = true
        self.lock.unlock()

        self.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self.store,
            queue: nil
        ) { [weak self] notification in
            self?.handleCloudChange(notification)
        }

        _ = self.store.synchronize()
        self.mergeInitialValues()
    }

    private func stop() {
        self.lock.lock()
        let observer = self.observer
        self.observer = nil
        self.isStarted = false
        self.lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func set(_ value: Any, forKey key: String, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key)
        guard defaults === UserDefaults.standard, Self.isEnabled() else {
            return
        }
        self.start()
        self.exportValue(value, forKey: key)
    }

    func removeObject(forKey key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        guard defaults === UserDefaults.standard, Self.isEnabled() else {
            return
        }
        self.start()
        self.removeCloudValue(forKey: key)
    }

    private func mergeInitialValues() {
        let cloudValues = self.store.dictionaryRepresentation
        for (cloudKey, value) in cloudValues {
            guard let localKey = NagramSettingsSyncKeys.localKey(fromCloudKey: cloudKey) else {
                continue
            }
            self.applyCloudValue(value, forKey: localKey)
        }

        let localValues = UserDefaults.standard.dictionaryRepresentation()
        for (localKey, value) in localValues {
            guard NagramSettingsSyncKeys.shouldSync(localKey: localKey) else {
                continue
            }
            let cloudKey = NagramSettingsSyncKeys.cloudKey(for: localKey)
            if self.store.object(forKey: cloudKey) == nil {
                self.store.set(self.cloudCompatibleValue(value), forKey: cloudKey)
            }
        }
        _ = self.store.synchronize()
    }

    private func handleCloudChange(_ notification: Notification) {
        guard Self.isEnabled() else {
            return
        }

        guard let changedCloudKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        var didApplyChange = false
        for cloudKey in changedCloudKeys {
            guard let localKey = NagramSettingsSyncKeys.localKey(fromCloudKey: cloudKey) else {
                continue
            }
            if let value = self.store.object(forKey: cloudKey) {
                self.applyCloudValue(value, forKey: localKey)
            } else {
                self.applyCloudRemoval(forKey: localKey)
            }
            didApplyChange = true
        }

        if didApplyChange {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        }
    }

    private func exportValue(_ value: Any, forKey key: String) {
        guard NagramSettingsSyncKeys.shouldSync(localKey: key), !self.isApplyingCloudChange else {
            return
        }
        self.store.set(self.cloudCompatibleValue(value), forKey: NagramSettingsSyncKeys.cloudKey(for: key))
        _ = self.store.synchronize()
    }

    private func removeCloudValue(forKey key: String) {
        guard NagramSettingsSyncKeys.shouldSync(localKey: key), !self.isApplyingCloudChange else {
            return
        }
        self.store.removeObject(forKey: NagramSettingsSyncKeys.cloudKey(for: key))
        _ = self.store.synchronize()
    }

    private func applyCloudValue(_ value: Any, forKey key: String) {
        let previousValue = UserDefaults.standard.object(forKey: key)
        self.isApplyingCloudChange = true
        UserDefaults.standard.set(value, forKey: key)
        self.isApplyingCloudChange = false
        self.postRelatedNotifications(forKey: key, previousValue: previousValue, newValue: value)
    }

    private func applyCloudRemoval(forKey key: String) {
        let previousValue = UserDefaults.standard.object(forKey: key)
        self.isApplyingCloudChange = true
        UserDefaults.standard.removeObject(forKey: key)
        self.isApplyingCloudChange = false
        self.postRelatedNotifications(forKey: key, previousValue: previousValue, newValue: nil)
    }

    private func cloudCompatibleValue(_ value: Any) -> Any {
        if let value = value as? Int32 {
            return NSNumber(value: value)
        }
        return value
    }

    private func postRelatedNotifications(forKey key: String, previousValue: Any?, newValue: Any?) {
        if key == "nagram.regexFilters.rules" || key == "nagram.regexFilters.disabledPeerIds" {
            NotificationCenter.default.post(name: .nagramRegexFiltersDidChange, object: nil)
        }

        let recentChatFoldersPrefix = "nagram.recentChatFolders."
        if key.hasPrefix(recentChatFoldersPrefix) {
            let startIndex = key.index(key.startIndex, offsetBy: recentChatFoldersPrefix.count)
            guard let accountPeerId = Int64(String(key[startIndex...])) else {
                return
            }
            let previousFilterIds = self.stringSet(from: previousValue)
            let newFilterIds = self.stringSet(from: newValue)
            for filterIdString in previousFilterIds.union(newFilterIds) {
                guard let filterId = Int32(filterIdString) else {
                    continue
                }
                NotificationCenter.default.post(
                    name: .nagramRecentChatFolderSettingsDidChange,
                    object: nil,
                    userInfo: ["accountPeerId": accountPeerId, "filterId": filterId]
                )
            }
        }
    }

    private func stringSet(from value: Any?) -> Set<String> {
        if let values = value as? [String] {
            return Set(values)
        }
        if let values = value as? [Any] {
            return Set(values.compactMap { $0 as? String })
        }
        return Set()
    }
}
