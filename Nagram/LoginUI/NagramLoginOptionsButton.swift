import Foundation
import UIKit
import Display

// MARK: NAGRAM — 登录页右上角的账号按钮。
//
// Shared by the splash screen and the phone entry screen so the two entry
// points cannot drift apart. The badge counts accounts that exist in the
// keychain but are not signed in on this device.
public final class NagramLoginOptionsButton: UIButton {
    private let badgeBackgroundView: UIView
    private let badgeLabel: UILabel
    private var badgeCount: Int = 0

    public static let preferredSize = CGSize(width: 44.0, height: 44.0)

    // MARK: NAGRAM — 图标在这里统一，两个入口不会各画各的。
    //
    // "Add user" rather than a plain person silhouette: on a login screen there
    // is no profile to show yet, and every item behind this button (scan a QR
    // code, import a session, pick a saved account) is a way to put an account
    // on the device. The asset is 24x24, which `layoutSubviews` relies on when
    // it parks the badge on the glyph's corner.
    public static func defaultIcon(color: UIColor) -> UIImage? {
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/AddUser"), color: color)
    }

    public init(icon: UIImage?, accessibilityLabel: String) {
        self.badgeBackgroundView = UIView()
        self.badgeBackgroundView.backgroundColor = UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        self.badgeBackgroundView.isHidden = true
        self.badgeBackgroundView.isUserInteractionEnabled = false

        self.badgeLabel = UILabel()
        self.badgeLabel.textColor = .white
        self.badgeLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        self.badgeLabel.textAlignment = .center

        super.init(frame: CGRect(origin: CGPoint(), size: NagramLoginOptionsButton.preferredSize))

        self.setImage(icon, for: .normal)
        self.accessibilityLabel = accessibilityLabel
        self.badgeBackgroundView.addSubview(self.badgeLabel)
        self.addSubview(self.badgeBackgroundView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setBadgeCount(_ count: Int) {
        self.badgeCount = count
        self.badgeBackgroundView.isHidden = count <= 0
        self.badgeLabel.text = count > 99 ? "99+" : "\(count)"
        self.setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard self.badgeCount > 0 else {
            return
        }
        self.badgeLabel.sizeToFit()
        let height: CGFloat = 16.0
        let width = max(height, self.badgeLabel.bounds.width + 9.0)
        // Sits on the icon's top trailing corner rather than the button's, so it
        // hugs the glyph instead of floating in the 44pt tap target.
        let iconSide: CGFloat = 24.0
        let iconOrigin = CGPoint(x: (self.bounds.width - iconSide) / 2.0, y: (self.bounds.height - iconSide) / 2.0)
        self.badgeBackgroundView.frame = CGRect(
            x: min(self.bounds.width - width, iconOrigin.x + iconSide - width / 2.0),
            y: max(0.0, iconOrigin.y - height / 3.0),
            width: width,
            height: height
        )
        self.badgeBackgroundView.layer.cornerRadius = height / 2.0
        self.badgeLabel.frame = self.badgeBackgroundView.bounds
    }
}
