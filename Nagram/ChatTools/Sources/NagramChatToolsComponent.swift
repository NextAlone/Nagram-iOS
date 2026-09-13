import ComponentFlow
import NagramStrings
import TelegramPresentationData
import UIKit

public final class NagramChatToolsComponent: Component {
    public enum Action: String, CaseIterable {
        case search, media, pinned, beginning, notifications, cache
    }

    private let theme: PresentationTheme
    private let languageCode: String
    private let isMuted: Bool
    private let hasPinnedMessages: Bool
    private let showNotifications: Bool
    private let action: (Action) -> Void

    public init(theme: PresentationTheme, languageCode: String, isMuted: Bool, hasPinnedMessages: Bool, showNotifications: Bool, action: @escaping (Action) -> Void) {
        self.theme = theme
        self.languageCode = languageCode
        self.isMuted = isMuted
        self.hasPinnedMessages = hasPinnedMessages
        self.showNotifications = showNotifications
        self.action = action
    }

    public static func == (lhs: NagramChatToolsComponent, rhs: NagramChatToolsComponent) -> Bool {
        return lhs.theme === rhs.theme && lhs.languageCode == rhs.languageCode && lhs.isMuted == rhs.isMuted && lhs.hasPinnedMessages == rhs.hasPinnedMessages && lhs.showNotifications == rhs.showNotifications
    }

    public final class View: UIScrollView {
        private var component: NagramChatToolsComponent?
        private var buttons: [Action: UIButton] = [:]

        public override init(frame: CGRect) {
            super.init(frame: frame)
            self.showsHorizontalScrollIndicator = false
            self.contentInsetAdjustmentBehavior = .never
            for action in Action.allCases {
                let button = UIButton(type: .system)
                button.accessibilityIdentifier = "Nagram.ChatTools." + action.rawValue
                button.addAction(UIAction(handler: { [weak self] _ in
                    self?.component?.action(action)
                }), for: .touchUpInside)
                self.buttons[action] = button
                self.addSubview(button)
            }
        }

        required public init?(coder: NSCoder) {
            preconditionFailure()
        }

        fileprivate func update(component: NagramChatToolsComponent, availableSize: CGSize) -> CGSize {
            self.component = component
            let actions = Action.allCases.filter { $0 != .notifications || component.showNotifications }
            self.buttons[.notifications]?.isHidden = !component.showNotifications
            let height: CGFloat = 56.0
            let inset: CGFloat = 8.0
            let minimumWidth = max(64.0, (availableSize.width - inset * 2.0) / CGFloat(actions.count))
            var offset = inset
            for action in actions {
                guard let button = self.buttons[action] else {
                    continue
                }
                let symbol: String
                switch action {
                case .search: symbol = "magnifyingglass"
                case .media: symbol = "photo.on.rectangle"
                case .pinned: symbol = "pin"
                case .beginning: symbol = "arrow.up.to.line"
                case .notifications: symbol = component.isMuted ? "bell" : "bell.slash"
                case .cache: symbol = "internaldrive"
                }
                let key = action == .notifications && component.isMuted ? "unmute" : action.rawValue
                let title = ngI18n("Nagram.ChatTools." + key, component.languageCode)
                var configuration = UIButton.Configuration.plain()
                configuration.image = UIImage(systemName: symbol)
                configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16.0, weight: .regular)
                configuration.imagePlacement = .top
                configuration.imagePadding = 3.0
                configuration.title = title
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes
                    attributes.font = UIFont.systemFont(ofSize: 12.0)
                    return attributes
                }
                configuration.baseForegroundColor = component.theme.rootController.navigationBar.accentTextColor
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 8.0, bottom: 4.0, trailing: 8.0)
                button.configuration = configuration
                button.accessibilityLabel = title
                button.isEnabled = action != .pinned || component.hasPinnedMessages
                let titleWidth = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12.0)]).width
                let width = max(minimumWidth, ceil(titleWidth) + 16.0)
                button.frame = CGRect(x: offset, y: 0.0, width: width, height: height)
                offset += width
            }
            self.contentSize = CGSize(width: offset + inset, height: height)
            self.alwaysBounceHorizontal = self.contentSize.width > availableSize.width
            self.contentOffset.x = min(max(0.0, self.contentOffset.x), max(0.0, self.contentSize.width - availableSize.width))
            return CGSize(width: availableSize.width, height: height)
        }
    }

    public func makeView() -> View {
        return View(frame: .zero)
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}
