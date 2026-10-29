import ComponentFlow
import Display
import NagramSettings
import NagramStrings
import TelegramPresentationData
import UIKit

public final class NagramChatToolsComponent: Component {
    /// An entry of the manage menu, opened from the manage tool.
    public struct ManageItem: Equatable {
        public let id: String
        public let title: String
        public let symbol: String

        public init(id: String, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    private let theme: PresentationTheme
    private let languageCode: String
    private let tools: [NagramChatToolId]
    private let size: NagramChatToolsSize
    private let isMuted: Bool
    private let hasPinnedMessages: Bool
    private let isTranslateEnabled: Bool
    private let manageItems: [ManageItem]
    private let action: (NagramChatToolId) -> Void
    private let manageAction: (String) -> Void

    public init(theme: PresentationTheme, languageCode: String, tools: [NagramChatToolId], size: NagramChatToolsSize, isMuted: Bool, hasPinnedMessages: Bool, isTranslateEnabled: Bool, manageItems: [ManageItem], action: @escaping (NagramChatToolId) -> Void, manageAction: @escaping (String) -> Void) {
        self.theme = theme
        self.languageCode = languageCode
        self.tools = tools
        self.size = size
        self.isMuted = isMuted
        self.hasPinnedMessages = hasPinnedMessages
        self.isTranslateEnabled = isTranslateEnabled
        self.manageItems = manageItems
        self.action = action
        self.manageAction = manageAction
    }

    public static func == (lhs: NagramChatToolsComponent, rhs: NagramChatToolsComponent) -> Bool {
        return lhs.theme === rhs.theme && lhs.languageCode == rhs.languageCode && lhs.tools == rhs.tools && lhs.size == rhs.size && lhs.isMuted == rhs.isMuted && lhs.hasPinnedMessages == rhs.hasPinnedMessages && lhs.isTranslateEnabled == rhs.isTranslateEnabled && lhs.manageItems == rhs.manageItems
    }

    private struct Metrics {
        let height: CGFloat
        let symbolSize: CGFloat
        let titleFontSize: CGFloat?
        let imagePadding: CGFloat
        let minimumWidth: CGFloat

        init(size: NagramChatToolsSize) {
            switch size {
            case .compact:
                self.height = 36.0
                self.symbolSize = 15.0
                self.titleFontSize = nil
                self.imagePadding = 0.0
                self.minimumWidth = 44.0
            case .standard:
                self.height = 44.0
                self.symbolSize = 14.0
                self.titleFontSize = 10.0
                self.imagePadding = 2.0
                self.minimumWidth = 52.0
            case .large:
                self.height = 56.0
                self.symbolSize = 16.0
                self.titleFontSize = 12.0
                self.imagePadding = 3.0
                self.minimumWidth = 64.0
            }
        }
    }

    public final class View: UIScrollView {
        private var component: NagramChatToolsComponent?
        private var buttons: [NagramChatToolId: UIButton] = [:]

        public override init(frame: CGRect) {
            super.init(frame: frame)
            self.showsHorizontalScrollIndicator = false
            self.contentInsetAdjustmentBehavior = .never
            // Once scrolled away from the origin, a rightward drag scrolls the strip back instead of starting the navigation back swipe.
            self.disablesInteractiveTransitionGestureRecognizerNow = { [weak self] in
                guard let self else {
                    return false
                }
                return self.contentOffset.x > .ulpOfOne
            }
        }

        required public init?(coder: NSCoder) {
            preconditionFailure()
        }

        // The strip is covered edge to edge by buttons, so a drag that starts on one has to be able to scroll.
        public override func touchesShouldCancel(in view: UIView) -> Bool {
            return true
        }

        private func button(for tool: NagramChatToolId) -> UIButton {
            if let current = self.buttons[tool] {
                return current
            }
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "Nagram.ChatTools." + tool.rawValue
            if tool != .manage {
                button.addAction(UIAction(handler: { [weak self] _ in
                    self?.component?.action(tool)
                }), for: .touchUpInside)
            }
            self.buttons[tool] = button
            self.addSubview(button)
            return button
        }

        fileprivate func update(component: NagramChatToolsComponent, availableSize: CGSize) -> CGSize {
            self.component = component
            let metrics = Metrics(size: component.size)
            let tools = component.tools

            let visible = Set(tools)
            for (tool, button) in self.buttons where !visible.contains(tool) {
                button.isHidden = true
            }

            let inset: CGFloat = 8.0
            let minimumWidth = tools.isEmpty ? metrics.minimumWidth : max(metrics.minimumWidth, (availableSize.width - inset * 2.0) / CGFloat(tools.count))
            var offset = inset
            for tool in tools {
                let button = self.button(for: tool)
                button.isHidden = false

                let symbol: String
                let titleKey: String
                switch tool {
                case .search:
                    symbol = "magnifyingglass"
                    titleKey = "search"
                case .media:
                    symbol = "photo.on.rectangle"
                    titleKey = "media"
                case .pinned:
                    symbol = "pin"
                    titleKey = "pinned"
                case .beginning:
                    symbol = "arrow.up.to.line"
                    titleKey = "beginning"
                case .notifications:
                    symbol = component.isMuted ? "bell" : "bell.slash"
                    titleKey = component.isMuted ? "unmute" : "notifications"
                case .cache:
                    symbol = "internaldrive"
                    titleKey = "cache"
                case .latest:
                    symbol = "arrow.down.to.line"
                    titleKey = "latest"
                case .mentions:
                    symbol = "at"
                    titleKey = "mentions"
                case .select:
                    symbol = "checkmark.circle"
                    titleKey = "select"
                case .translate:
                    symbol = component.isTranslateEnabled ? "character.bubble.fill" : "character.bubble"
                    titleKey = component.isTranslateEnabled ? "translateOff" : "translate"
                case .manage:
                    symbol = "slider.horizontal.3"
                    titleKey = "manage"
                }
                let title = ngI18n("Nagram.ChatTools." + titleKey, component.languageCode)

                var configuration = UIButton.Configuration.plain()
                configuration.image = UIImage(systemName: symbol)
                configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: metrics.symbolSize, weight: .regular)
                configuration.imagePlacement = .top
                configuration.imagePadding = metrics.imagePadding
                var titleWidth: CGFloat = 0.0
                if let titleFontSize = metrics.titleFontSize {
                    let font = UIFont.systemFont(ofSize: titleFontSize)
                    configuration.title = title
                    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                        var attributes = attributes
                        attributes.font = font
                        return attributes
                    }
                    titleWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
                }
                configuration.baseForegroundColor = component.theme.rootController.navigationBar.accentTextColor
                configuration.contentInsets = NSDirectionalEdgeInsets(top: 2.0, leading: 6.0, bottom: 2.0, trailing: 6.0)
                button.configuration = configuration
                button.accessibilityLabel = title
                button.isEnabled = tool != .pinned || component.hasPinnedMessages

                if tool == .manage {
                    button.menu = UIMenu(children: component.manageItems.map { item in
                        return UIAction(title: item.title, image: UIImage(systemName: item.symbol), handler: { [weak self] _ in
                            self?.component?.manageAction(item.id)
                        })
                    })
                    button.showsMenuAsPrimaryAction = true
                }

                let width = max(minimumWidth, titleWidth + 16.0)
                button.frame = CGRect(x: offset, y: 0.0, width: width, height: metrics.height)
                offset += width
            }
            self.contentSize = CGSize(width: offset + inset, height: metrics.height)
            self.alwaysBounceHorizontal = self.contentSize.width > availableSize.width
            self.contentOffset.x = min(max(0.0, self.contentOffset.x), max(0.0, self.contentSize.width - availableSize.width))
            return CGSize(width: availableSize.width, height: metrics.height)
        }
    }

    public func makeView() -> View {
        return View(frame: .zero)
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}
