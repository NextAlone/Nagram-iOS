import Foundation
import NagramSettings
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

public final class NagramTelegramSettingsCloudSync {
    public static let shared = NagramTelegramSettingsCloudSync()

    private struct SyncedEntry {
        let name: String
        let key: EngineDataBuffer
    }

    private static let cloudPrefix = "nagram.telegramSharedData."
    // Passcode、Proxy、联系人、缓存、日志、Siri/Spotlight 等敏感或设备相关配置不进 iCloud。
    // 语言（localizationSettings）也不进：它存的是整份已下载的语言包，官方中文就有约 800 KB，自定义语言包还带一份
    // base 包，会超过 iCloud 键值存储单值和总量各 1 MB 的上限而写不上去；启动时却会用云端的旧值覆盖本地，
    // 可能把刚切换的第三方语言包换回旧语言（疑为 I0047、I0051 的原因）。语言包可以从服务器重新下载，不需要同步。
    private static let syncedEntries: [SyncedEntry] = [
        SyncedEntry(name: "autodownloadSettings", key: SharedDataKeys.autodownloadSettings),
        SyncedEntry(name: "inAppNotificationSettings", key: ApplicationSpecificSharedDataKeys.inAppNotificationSettings),
        SyncedEntry(name: "automaticMediaDownloadSettings", key: ApplicationSpecificSharedDataKeys.automaticMediaDownloadSettings),
        SyncedEntry(name: "generatedMediaStoreSettings", key: ApplicationSpecificSharedDataKeys.generatedMediaStoreSettings),
        SyncedEntry(name: "voiceCallSettings", key: ApplicationSpecificSharedDataKeys.voiceCallSettings),
        SyncedEntry(name: "presentationThemeSettings", key: ApplicationSpecificSharedDataKeys.presentationThemeSettings),
        SyncedEntry(name: "instantPagePresentationSettings", key: ApplicationSpecificSharedDataKeys.instantPagePresentationSettings),
        SyncedEntry(name: "callListSettings", key: ApplicationSpecificSharedDataKeys.callListSettings),
        SyncedEntry(name: "musicPlaybackSettings", key: ApplicationSpecificSharedDataKeys.musicPlaybackSettings),
        SyncedEntry(name: "mediaInputSettings", key: ApplicationSpecificSharedDataKeys.mediaInputSettings),
        SyncedEntry(name: "experimentalUISettings", key: ApplicationSpecificSharedDataKeys.experimentalUISettings),
        SyncedEntry(name: "stickerSettings", key: ApplicationSpecificSharedDataKeys.stickerSettings),
        SyncedEntry(name: "webSearchSettings", key: ApplicationSpecificSharedDataKeys.webSearchSettings),
        SyncedEntry(name: "webBrowserSettings", key: ApplicationSpecificSharedDataKeys.webBrowserSettings),
        SyncedEntry(name: "translationSettings", key: ApplicationSpecificSharedDataKeys.translationSettings),
        SyncedEntry(name: "drawingSettings", key: ApplicationSpecificSharedDataKeys.drawingSettings),
        SyncedEntry(name: "mediaDisplaySettings", key: ApplicationSpecificSharedDataKeys.mediaDisplaySettings),
        SyncedEntry(name: "updateSettings", key: ApplicationSpecificSharedDataKeys.updateSettings),
        SyncedEntry(name: "chatSettings", key: ApplicationSpecificSharedDataKeys.chatSettings)
    ]
    private static let syncedKeys = Set(syncedEntries.map(\.key))
    private static let syncedEntriesByCloudKey = Dictionary(uniqueKeysWithValues: syncedEntries.map { (cloudKey(for: $0), $0) })

    /// 只在同步已开启的路径上访问。实例化 `NSUbiquitousKeyValueStore` 会在缺少
    /// `com.apple.developer.ubiquity-kvstore-identifier` entitlement 的构建里触发 SyncedDefaults 的
    /// "BUG IN CLIENT OF KVS" fault（iOS 15 上报为 EXC_GUARD 模拟崩溃），所以不能在单例初始化时创建。
    private var store: NSUbiquitousKeyValueStore {
        return NSUbiquitousKeyValueStore.default
    }
    private let sharedDataDisposable = MetaDisposable()
    private let lock = NSLock()

    private weak var accountManager: AccountManager<TelegramAccountManagerTypes>?
    private var cloudObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var isSyncing = false
    private var applyingCloudChangeCount = 0

    private init() {}

    public func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.lock.lock()
        self.accountManager = accountManager
        let shouldAddDefaultsObserver = self.defaultsObserver == nil
        self.lock.unlock()

        if shouldAddDefaultsObserver {
            self.defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: nil
            ) { [weak self] _ in
                self?.updateEnabledState()
            }
        }

        self.updateEnabledState()
    }

    private static func cloudKey(for entry: SyncedEntry) -> String {
        return cloudPrefix + entry.name
    }

    private func updateEnabledState() {
        if NagramSettings.isICloudSyncEnabled() {
            self.startSyncingIfNeeded()
        } else {
            self.stopSyncing()
        }
    }

    private func startSyncingIfNeeded() {
        guard let accountManager = self.accountManager else {
            return
        }

        self.lock.lock()
        if self.isSyncing {
            self.lock.unlock()
            return
        }
        self.isSyncing = true
        self.lock.unlock()

        self.cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self.store,
            queue: nil
        ) { [weak self] notification in
            self?.handleCloudChange(notification)
        }

        _ = self.store.synchronize()
        self.mergeInitialValues(accountManager: accountManager)
    }

    private func stopSyncing() {
        self.lock.lock()
        let observer = self.cloudObserver
        self.cloudObserver = nil
        self.isSyncing = false
        self.applyingCloudChangeCount = 0
        self.lock.unlock()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        self.sharedDataDisposable.set(nil)
    }

    private func mergeInitialValues(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let cloudValues = Self.syncedEntries.compactMap { entry -> (EngineDataBuffer, Data)? in
            guard let data = self.cloudData(forKey: Self.cloudKey(for: entry)) else {
                return nil
            }
            return (entry.key, data)
        }

        let subscribeToLocalChanges = { [weak self, weak accountManager] in
            guard let self, let accountManager, self.currentlySyncing else {
                return
            }
            self.subscribeToLocalChanges(accountManager: accountManager)
        }

        guard !cloudValues.isEmpty else {
            subscribeToLocalChanges()
            return
        }

        self.beginApplyingCloudChange()
        let _ = (accountManager.transaction { transaction -> Void in
            for (key, data) in cloudValues {
                transaction.updateSharedData(key, { current in
                    let updated = EnginePreferencesEntry(data: data)
                    if let current, current == updated {
                        return current
                    }
                    return updated
                })
            }
        }).start(completed: { [weak self] in
            self?.endApplyingCloudChange()
            subscribeToLocalChanges()
        })
    }

    private func subscribeToLocalChanges(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.sharedDataDisposable.set((accountManager.sharedData(keys: Self.syncedKeys)).start(next: { [weak self] sharedData in
            guard let self, self.currentlySyncing, !self.currentlyApplyingCloudChange else {
                return
            }

            for entry in Self.syncedEntries {
                let cloudKey = Self.cloudKey(for: entry)
                if let value = sharedData.entries[entry.key] {
                    self.store.set(value.data as NSData, forKey: cloudKey)
                } else {
                    self.store.removeObject(forKey: cloudKey)
                }
            }
            _ = self.store.synchronize()
        }))
    }

    private func handleCloudChange(_ notification: Notification) {
        guard self.currentlySyncing, NagramSettings.isICloudSyncEnabled() else {
            return
        }
        guard let accountManager = self.accountManager else {
            return
        }
        guard let changedCloudKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        var changedValues: [(EngineDataBuffer, Data?)] = []
        for cloudKey in changedCloudKeys {
            guard let entry = Self.syncedEntriesByCloudKey[cloudKey] else {
                continue
            }
            changedValues.append((entry.key, self.cloudData(forKey: cloudKey)))
        }
        guard !changedValues.isEmpty else {
            return
        }

        self.beginApplyingCloudChange()
        let _ = (accountManager.transaction { transaction -> Void in
            for (key, data) in changedValues {
                transaction.updateSharedData(key, { current in
                    guard let data else {
                        return nil
                    }
                    let updated = EnginePreferencesEntry(data: data)
                    if let current, current == updated {
                        return current
                    }
                    return updated
                })
            }
        }).start(completed: { [weak self] in
            self?.endApplyingCloudChange()
        })
    }

    private var currentlySyncing: Bool {
        self.lock.lock()
        let result = self.isSyncing
        self.lock.unlock()
        return result
    }

    private var currentlyApplyingCloudChange: Bool {
        self.lock.lock()
        let result = self.applyingCloudChangeCount > 0
        self.lock.unlock()
        return result
    }

    private func beginApplyingCloudChange() {
        self.lock.lock()
        self.applyingCloudChangeCount += 1
        self.lock.unlock()
    }

    private func endApplyingCloudChange() {
        self.lock.lock()
        self.applyingCloudChangeCount = max(0, self.applyingCloudChangeCount - 1)
        self.lock.unlock()
    }

    private func cloudData(forKey key: String) -> Data? {
        if let data = self.store.object(forKey: key) as? Data {
            return data
        }
        if let data = self.store.object(forKey: key) as? NSData {
            return data as Data
        }
        return nil
    }
}
