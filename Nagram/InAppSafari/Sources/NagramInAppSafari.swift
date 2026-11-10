import Foundation
import UIKit
import SafariServices

// MARK: NAGRAM — "Safari (In-App)" in Open Links In: links open in SFSafariViewController.

/// The `WebBrowserSettings.defaultWebBrowser` value of the in-app Safari option. Upstream already maps this value to
/// Safari wherever a link is handed to an external browser, so those paths keep working unchanged.
public let nagramInAppSafariBrowserIdentifier = "inAppSafari"

/// SFSafariViewController opens only http(s) URLs; anything else must take the external-browser path.
public func nagramInAppSafariCanOpen(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
        return false
    }
    return scheme == "http" || scheme == "https"
}

/// Presents `url` in SFSafariViewController over the topmost controller of `window`. Returns false when it could
/// not be presented, so the caller can open the link the way it did before.
@discardableResult
public func nagramPresentInAppSafari(url: URL, window: UIWindow?, barTintColor: UIColor, controlTintColor: UIColor) -> Bool {
    guard nagramInAppSafariCanOpen(url), var presenter = window?.rootViewController else {
        return false
    }
    while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
        presenter = presented
    }
    let controller = SFSafariViewController(url: url)
    controller.preferredBarTintColor = barTintColor
    controller.preferredControlTintColor = controlTintColor
    presenter.present(controller, animated: true)
    return true
}
