import Foundation
import NagramSettings
import SwiftSignalKit

// MARK: NAGRAM — 增强开关的响应式桥接。
// 用 UserDefaults.didChangeNotification 把开关变化转成 Signal，供需即时刷新的功能（如 hideStories）订阅。
// 独立模块：依赖 SwiftSignalKit，不污染纯 Foundation 的 NagramSettings 数据层。
public func nagramBoolSignal(_ key: String, defaultValue: Bool) -> Signal<Bool, NoError> {
    let initial = Signal<Bool, NoError>.single(UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue)
    let changes = Signal<Bool, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            subscriber.putNext(UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}
public func nagramBottomBarSettingsSignal() -> Signal<NagramBottomBarSettings, NoError> {
    let initial = Signal<NagramBottomBarSettings, NoError>.single(NagramSettings.shared.bottomBarSettings)
    let changes = Signal<NagramBottomBarSettings, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
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
