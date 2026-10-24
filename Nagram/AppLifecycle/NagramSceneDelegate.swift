import UIKit

@objc(NagramSceneDelegate)
final class NagramSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var launchShortcut: UIApplicationShortcutItem?

    private var appDelegate: AppDelegate {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else {
            preconditionFailure("NagramSceneDelegate requires AppDelegate")
        }
        return delegate
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            preconditionFailure("Nagram requires a UIWindowScene")
        }
        self.window = self.appDelegate.connectScene(windowScene)
        self.scene(scene, openURLContexts: connectionOptions.urlContexts)
        for activity in connectionOptions.userActivities {
            self.scene(scene, continue: activity)
        }
        self.launchShortcut = connectionOptions.shortcutItem
        // Notification responses, including cold launches, remain owned by
        // UNUserNotificationCenterDelegate to avoid handling the same response twice.
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene {
            self.appDelegate.disconnectScene(windowScene)
        }
        self.launchShortcut = nil
        self.window = nil
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        self.appDelegate.handleWillEnterForeground()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        self.appDelegate.handleDidBecomeActive()
        if let shortcut = self.launchShortcut {
            self.launchShortcut = nil
            self.appDelegate.handleShortcutItem(shortcut, completionHandler: { _ in })
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        self.appDelegate.handleWillResignActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        self.appDelegate.handleDidEnterBackground()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            let url = context.url
            // MARK: NAGRAM — 「注册 Telegram 链接」关闭时，外部 tg:// / telegram:// 先交给官方 Telegram；
            // 没装官方 Telegram 时回落到 Nagram 自己处理。
            if !nagramForwardTelegramSchemeUrl(url, fallback: { [weak self] in
                self?.appDelegate.handleOpenURL(url)
            }) {
                self.appDelegate.handleOpenURL(url)
            }
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        self.appDelegate.handleUserActivity(userActivity)
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        self.appDelegate.handleShortcutItem(shortcutItem, completionHandler: completionHandler)
    }

    @available(iOS 26.0, *)
    func preferredWindowingControlStyle(for windowScene: UIWindowScene) -> UIWindowScene.WindowingControlStyle {
        return .minimal
    }
}
