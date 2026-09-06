import Foundation
import NagramSettings
import SwiftSignalKit
import UIKit

// MARK: NAGRAM — 增强开关的响应式桥接。
// 用 UserDefaults.didChangeNotification 把开关变化转成 Signal，供需即时刷新的功能（如 hideStories）订阅。
// 独立模块：依赖 SwiftSignalKit，不污染纯 Foundation 的 NagramSettings 数据层。
public func nagramBoolSignal(_ key: String, defaultValue: Bool) -> Signal<Bool, NoError> {
    let initial = Signal<Bool, NoError>.single(NagramDemoMode.userDefaults.object(forKey: key) as? Bool ?? defaultValue)
    let changes = Signal<Bool, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            subscriber.putNext(NagramDemoMode.userDefaults.object(forKey: key) as? Bool ?? defaultValue)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}

public func nagramStringSignal(_ key: String, defaultValue: String) -> Signal<String, NoError> {
    let initial = Signal<String, NoError>.single(NagramDemoMode.userDefaults.string(forKey: key) ?? defaultValue)
    let changes = Signal<String, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            subscriber.putNext(NagramDemoMode.userDefaults.string(forKey: key) ?? defaultValue)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}

public func nagramRecentStickerLimitSignal() -> Signal<Int, NoError> {
    let initial = Signal<Int, NoError>.single(NagramSettings.shared.recentStickerLimitValue)
    let changes = Signal<Int, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            subscriber.putNext(NagramSettings.shared.recentStickerLimitValue)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}

public func nagramAutoTranslateSignal(accountPeerId: Int64, peerId: Int64, threadId: Int64?) -> Signal<Bool, NoError> {
    return nagramBoolSignal(NagramSettings.autoTranslateKey(accountPeerId: accountPeerId, peerId: peerId, threadId: threadId), defaultValue: false)
}

public func nagramBottomBarSettingsSignal() -> Signal<NagramBottomBarSettings, NoError> {
    let initial = Signal<NagramBottomBarSettings, NoError>.single(NagramSettings.shared.bottomBarSettings)
    let changes = Signal<NagramBottomBarSettings, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            subscriber.putNext(NagramSettings.shared.bottomBarSettings)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}

public func nagramGlassTransparencySignal() -> Signal<Int32, NoError> {
    let initial = Signal<Int32, NoError>.single(0)
    let changes = Signal<Int32, NoError> { subscriber in
        var version: Int32 = 0
        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            version += 1
            subscriber.putNext(version)
        }
        let accessibilityObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            version += 1
            subscriber.putNext(version)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(defaultsObserver)
            NotificationCenter.default.removeObserver(accessibilityObserver)
        }
    }
    return initial |> then(changes)
}

public func nagramRegexFiltersSignal() -> Signal<Int32, NoError> {
    let initial = Signal<Int32, NoError>.single(0)
    let changes = Signal<Int32, NoError> { subscriber in
        var version: Int32 = 0
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("NagramRegexFiltersDidChange"),
            object: nil,
            queue: nil
        ) { _ in
            version += 1
            subscriber.putNext(version)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return initial |> then(changes)
}
