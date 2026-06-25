import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import TabBarComponent
import GlassControls
import NagramSettings

final class TabBarControllerNode: ASDisplayNode {
    private struct Params: Equatable {
        let layout: ContainerViewLayout
        let toolbar: Toolbar?
        let isTabBarHidden: Bool
        let currentControllerSearchState: ViewController.TabBarSearchState?
        let nagramBottomBarSettings: NagramBottomBarSettings
        
        init(
            layout: ContainerViewLayout,
            toolbar: Toolbar?,
            isTabBarHidden: Bool,
            currentControllerSearchState: ViewController.TabBarSearchState?,
            nagramBottomBarSettings: NagramBottomBarSettings
        ) {
            self.layout = layout
            self.toolbar = toolbar
            self.isTabBarHidden = isTabBarHidden
            self.currentControllerSearchState = currentControllerSearchState
            self.nagramBottomBarSettings = nagramBottomBarSettings
        }
    }
    
    private struct LayoutResult {
        let params: Params
        let bottomInset: CGFloat
        
        init(params: Params, bottomInset: CGFloat) {
            self.params = params
            self.bottomInset = bottomInset
        }
    }
    
    private final class View: UIView {
        var onLayout: (() -> Void)?
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            self.onLayout?()
        }
    }
    
    private var theme: PresentationTheme
    private var strings: PresentationStrings
    private let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    private let itemHasDoubleTapAction: (Int) -> Bool
    private let itemDoubleTapped: (Int) -> Void
    private let contextAction: (Int, ContextExtractedContentContainingView, ContextGesture) -> Void
    
    private let tabBarView = ComponentView<Empty>()
    
    private let disabledOverlayNode: ASDisplayNode
    private var toolbar: ComponentView<Empty>?
    private let toolbarActionSelected: (ToolbarActionOption) -> Void
    private let disabledPressed: () -> Void
    private let activateSearch: () -> Void
    private let deactivateSearch: () -> Void
    
    private(set) var tabBarItems: [TabBarNodeItem] = []
    private(set) var selectedIndex: Int = 0

    private weak var currentController: ViewController?
    
    private var layoutResult: LayoutResult?
    private var isUpdateRequested: Bool = false
    private var isChangingSelectedIndex: Bool = false
    
    func setCurrentController(_ controller: ViewController?) -> () -> Void {
        guard controller !== self.currentController else {
            return {}
        }
        
        let previousNode = self.currentController?.displayNode
        self.currentController = controller
        if let currentControllerNode = self.currentController?.displayNode {
            if let previousNode {
                self.insertSubnode(currentControllerNode, aboveSubnode: previousNode)
            } else {
                self.insertSubnode(currentControllerNode, at: 0)
            }
            if let tabBarView = self.tabBarView.view {
                self.view.bringSubviewToFront(tabBarView)
            }
        }
        
        return { [weak self, weak previousNode] in
            if previousNode !== self?.currentController?.displayNode {
                previousNode?.removeFromSupernode()
            }
        }
    }

    var currentSearchNode: ASDisplayNode? {
        if let tabBarComponentView = self.tabBarView.view as? TabBarComponent.View {
            return tabBarComponentView.currentSearchNode
        }
        return nil
    }
    
    init(theme: PresentationTheme, strings: PresentationStrings, itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void, itemHasDoubleTapAction: @escaping (Int) -> Bool, itemDoubleTapped: @escaping (Int) -> Void, contextAction: @escaping (Int, ContextExtractedContentContainingView, ContextGesture) -> Void, swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void, toolbarActionSelected: @escaping (ToolbarActionOption) -> Void, disabledPressed: @escaping () -> Void, activateSearch: @escaping () -> Void, deactivateSearch: @escaping () -> Void) {
        self.theme = theme
        self.strings = strings
        self.itemSelected = itemSelected
        self.itemHasDoubleTapAction = itemHasDoubleTapAction
        self.itemDoubleTapped = itemDoubleTapped
        self.contextAction = contextAction
        self.disabledOverlayNode = ASDisplayNode()
        self.disabledOverlayNode.backgroundColor = theme.rootController.tabBar.backgroundColor.withAlphaComponent(0.5)
        self.disabledOverlayNode.alpha = 0.0
        self.toolbarActionSelected = toolbarActionSelected
        self.disabledPressed = disabledPressed
        self.activateSearch = activateSearch
        self.deactivateSearch = deactivateSearch

        super.init()
        
        self.setViewBlock({
            return View(frame: CGRect())
        })
        
        (self.view as? View)?.onLayout = { [weak self] in
            guard let self else {
                return
            }
            if self.isUpdateRequested {
                self.isUpdateRequested = false
                if let layoutResult = self.layoutResult {
                    let _ = self.updateImpl(params: layoutResult.params, transition: .immediate)
                }
            }
        }
        
        self.backgroundColor = theme.list.plainBackgroundColor
        
        //self.addSubnode(self.tabBarNode)
        //self.addSubnode(self.disabledOverlayNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.disabledOverlayNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.disabledTapGesture(_:))))
    }
    
    @objc private func disabledTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.disabledPressed()
        }
    }
    
    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.backgroundColor = theme.list.plainBackgroundColor
        
        self.disabledOverlayNode.backgroundColor = theme.rootController.tabBar.backgroundColor.withAlphaComponent(0.5)
        self.requestUpdate()
    }
    
    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(node: self.disabledOverlayNode, alpha: value ? 0.0 : 1.0)
    }
    
    var tabBarHidden = NagramSettings.shared.hideTabBar { // MARK: NAGRAM — 初值读开关
        didSet {
            if self.tabBarHidden != oldValue {
                self.requestUpdate()
            }
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, toolbar: Toolbar?, transition: ContainedViewLayoutTransition) -> CGFloat {
        let params = Params(layout: layout, toolbar: toolbar, isTabBarHidden: self.tabBarHidden, currentControllerSearchState: self.currentController?.tabBarSearchState, nagramBottomBarSettings: NagramSettings.shared.bottomBarSettings)
        if let layoutResult = self.layoutResult, layoutResult.params == params {
            return layoutResult.bottomInset
        } else {
            let bottomInset = self.updateImpl(params: params, transition: transition)
            self.layoutResult = LayoutResult(params: params, bottomInset: bottomInset)
            return bottomInset
        }
    }
    
    private func requestUpdate() {
        self.isUpdateRequested = true
        self.view.setNeedsLayout()
    }

    private func nagramItemId(for item: UITabBarItem) -> NagramBottomBarItemId? {
        switch item.animationName {
        case "TabContacts":
            return .contacts
        case "TabCalls":
            return .calls
        case "TabChats":
            return .chats
        case "TabSettings":
            return .settings
        default:
            if item.ringSelection {
                return .settings
            }
            return nil
        }
    }
    
    private func updateImpl(params: Params, transition: ContainedViewLayoutTransition) -> CGFloat {
        var panelsBottomInset: CGFloat = params.layout.insets(options: []).bottom
        if params.layout.metrics.widthClass == .regular, let inputHeight = params.layout.inputHeight, inputHeight != 0.0 {
            panelsBottomInset = inputHeight + 8.0
        }
        if panelsBottomInset == 0.0 {
            panelsBottomInset = 8.0
        } else {
            panelsBottomInset = max(panelsBottomInset, 8.0)
        }

        var tabBarBottomInset: CGFloat = panelsBottomInset
        if let currentController = self.currentController {
            if let tabBarSearchState = currentController.tabBarSearchState, tabBarSearchState.isActive, let inputHeight = params.layout.inputHeight, inputHeight != 0.0 {
                tabBarBottomInset = max(tabBarBottomInset, inputHeight + 8.0)
            }
        }

        var sideInset: CGFloat = 12.0
        if tabBarBottomInset <= 28.0 {
            sideInset = 20.0
        }
        
        let bottomBarSettings = params.nagramBottomBarSettings
        let tabBarItemsById: [NagramBottomBarItemId: (index: Int, item: TabBarNodeItem)] = Dictionary(uniqueKeysWithValues: self.tabBarItems.enumerated().compactMap { index, item -> (NagramBottomBarItemId, (Int, TabBarNodeItem))? in
            guard let id = self.nagramItemId(for: item.item) else {
                return nil
            }
            return (id, (index, item))
        })
        let makeComponentItem: (NagramBottomBarItemId) -> TabBarComponent.Item? = { [weak self] id in
            guard let self else {
                return nil
            }
            if id == .search {
                return TabBarComponent.Item(
                    content: .customItem(TabBarComponent.Item.Content.CustomItem(id: AnyHashable("nagram.search"), title: self.strings.Common_Search, icon: .bundleIcon(name: "Navigation/Search"))),
                    action: { [weak self] _ in
                        self?.activateSearch()
                    },
                    doubleTapAction: nil,
                    contextAction: nil
                )
            }
            guard let item = tabBarItemsById[id] else {
                return nil
            }
            let index = item.index
            return TabBarComponent.Item(
                content: .tabBarItem(item.item.item),
                action: { [weak self] isLongTap in
                    self?.itemSelected(index, isLongTap, [])
                },
                doubleTapAction: self.itemHasDoubleTapAction(index) ? { [weak self] in
                    self?.itemDoubleTapped(index)
                } : nil,
                contextAction: { [weak self] gesture, sourceView in
                    self?.contextAction(index, sourceView, gesture)
                }
            )
        }

        let visibleComponentItems: [TabBarComponent.Item] = bottomBarSettings.visibleBottomItems.compactMap { makeComponentItem($0) }
        let externalComponentItem: TabBarComponent.Item?
        if let externalItemId = bottomBarSettings.externalItem, externalItemId != .search, !bottomBarSettings.hiddenItems.contains(externalItemId) {
            externalComponentItem = makeComponentItem(externalItemId)
        } else {
            externalComponentItem = nil
        }
        
        var selectedId: AnyHashable?
        if self.selectedIndex < self.tabBarItems.count {
            let selectedItem = self.tabBarItems[self.selectedIndex].item
            let isBottomSelected = visibleComponentItems.contains(where: { item in
                if case let .tabBarItem(tabBarItem) = item.content {
                    return tabBarItem === selectedItem
                } else {
                    return false
                }
            })
            let isExternalSelected: Bool
            if let externalComponentItem, case let .tabBarItem(tabBarItem) = externalComponentItem.content {
                isExternalSelected = tabBarItem === selectedItem
            } else {
                isExternalSelected = false
            }
            if isBottomSelected || isExternalSelected {
                selectedId = ObjectIdentifier(selectedItem)
            }
        }
        var tabBarTransition = ComponentTransition(transition)
        if self.isChangingSelectedIndex {
            self.isChangingSelectedIndex = false
            tabBarTransition = .spring(duration: 0.4)
        }
        if self.tabBarView.view == nil {
            tabBarTransition = .immediate
        }
        let nagramLayoutItemCount = max(visibleComponentItems.count, NagramBottomBarSettings.defaultBottomItems.count)
        let tabBarSearchState = self.currentController?.tabBarSearchState
        let searchIsVisible = bottomBarSettings.isVisible(.search)
        let hasVisibleSearch = searchIsVisible && tabBarSearchState != nil
        let hasVisibleTabBarContent = !visibleComponentItems.isEmpty || externalComponentItem != nil || hasVisibleSearch
        let tabBarSize = self.tabBarView.update(
            transition: tabBarTransition,
            component: AnyComponent(TabBarComponent(
                theme: self.theme,
                strings: self.strings,
                items: visibleComponentItems,
                externalItem: externalComponentItem,
                search: searchIsVisible ? tabBarSearchState.flatMap { tabBarSearchState in
                    return TabBarComponent.Search(
                        isActive: tabBarSearchState.isActive,
                        showsButton: bottomBarSettings.searchMode != .bar,
                        activate: { [weak self] in
                            guard let self else {
                                return
                            }
                            self.activateSearch()
                        },
                        deactivate: { [weak self] in
                            guard let self else {
                                return
                            }
                            self.deactivateSearch()
                        }
                    )
                } : nil,
                selectedId: selectedId,
                outerInsets: UIEdgeInsets(top: 0.0, left: sideInset, bottom: tabBarBottomInset, right: sideInset),
                layoutItemCount: nagramLayoutItemCount,
                isAdaptiveWidth: false,
                alignItemsToLeft: bottomBarSettings.alignment == .left,
                showItemTitles: bottomBarSettings.showLabels,
                buttonWidthFillRatio: CGFloat(bottomBarSettings.buttonWidthFillRatio) / 100.0
            )),
            environment: {},
            containerSize: CGSize(width: params.layout.size.width - sideInset * 2.0, height: 100.0)
        )
        let tabBarOriginX: CGFloat
        let onlySearchButton = hasVisibleSearch && bottomBarSettings.searchMode != .bar && visibleComponentItems.isEmpty && externalComponentItem == nil && tabBarSearchState?.isActive != true
        let fillsAvailableWidth = !onlySearchButton && (bottomBarSettings.buttonWidthFillRatio >= 100 || externalComponentItem != nil || hasVisibleSearch)
        if onlySearchButton {
            tabBarOriginX = params.layout.size.width - sideInset - tabBarSize.width
        } else if !fillsAvailableWidth && tabBarSearchState?.isActive != true {
            if bottomBarSettings.alignment == .left {
                tabBarOriginX = sideInset
            } else {
                tabBarOriginX = floor((params.layout.size.width - tabBarSize.width) * 0.5)
            }
        } else if bottomBarSettings.buttonWidthFillRatio < 100 && tabBarSearchState == nil {
            tabBarOriginX = sideInset
        } else {
            tabBarOriginX = floor((params.layout.size.width - tabBarSize.width) * 0.5)
        }
        let tabBarFrame = CGRect(origin: CGPoint(x: tabBarOriginX, y: params.layout.size.height - (params.isTabBarHidden ? 0.0 : (tabBarSize.height + tabBarBottomInset))), size: tabBarSize)
        
        if let tabBarComponentView = self.tabBarView.view {
            if tabBarComponentView.superview == nil {
                self.view.addSubview(tabBarComponentView)
            }
            transition.updateFrame(view: tabBarComponentView, frame: tabBarFrame)
            let tabBarContentAlpha: CGFloat = !params.isTabBarHidden && params.toolbar == nil && hasVisibleTabBarContent ? 1.0 : 0.0
            transition.updateAlpha(layer: tabBarComponentView.layer, alpha: tabBarContentAlpha)
            tabBarComponentView.isUserInteractionEnabled = tabBarContentAlpha > 0.0
        }
        
        transition.updateFrame(node: self.disabledOverlayNode, frame: tabBarFrame)
        
        let toolbarHeight = 44.0
        let toolbarFrame = CGRect(origin: CGPoint(x: sideInset, y: params.layout.size.height - panelsBottomInset - toolbarHeight), size: CGSize(width: params.layout.size.width - sideInset * 2.0, height: toolbarHeight))
        
        if let toolbarData = params.toolbar {
            let toolbar: ComponentView<Empty>
            var toolbarTransition = ComponentTransition(transition)
            if let current = self.toolbar {
                toolbar = current
            } else {
                toolbar = ComponentView()
                self.toolbar = toolbar
                toolbarTransition = .immediate
            }
            
            let _ = toolbar.update(
                transition: toolbarTransition,
                component: AnyComponent(GlassControlPanelComponent(
                    theme: self.theme,
                    leftItem: toolbarData.leftAction.flatMap { value in
                        return GlassControlPanelComponent.Item(
                            items: [GlassControlGroupComponent.Item(
                                id: "left_" + value.title,
                                content: .text(value.title),
                                action: value.isEnabled ? { [weak self] in
                                    guard let self else {
                                        return
                                    }
                                    self.toolbarActionSelected(.left)
                                } : nil
                            )],
                            background: .panel
                        )
                    },
                    centralItem: toolbarData.middleAction.flatMap { value in
                        return GlassControlPanelComponent.Item(
                            items: [GlassControlGroupComponent.Item(
                                id: "right_" + value.title,
                                content: .text(value.title),
                                action: value.isEnabled ? { [weak self] in
                                    guard let self else {
                                        return
                                    }
                                    self.toolbarActionSelected(.middle)
                                } : nil
                            )],
                            background: .panel
                        )
                    },
                    rightItem: toolbarData.rightAction.flatMap { value in
                        return GlassControlPanelComponent.Item(
                            items: [GlassControlGroupComponent.Item(
                                id: "right_" + value.title,
                                content: .text(value.title),
                                action: value.isEnabled ? { [weak self] in
                                    guard let self else {
                                        return
                                    }
                                    self.toolbarActionSelected(.right)
                                } : nil
                            )],
                            background: .panel
                        )
                    },
                    centerAlignmentIfPossible: true
                )),
                environment: {},
                containerSize: toolbarFrame.size
            )
            
            if let toolbarView = toolbar.view {
                if toolbarView.superview == nil {
                    self.view.addSubview(toolbarView)
                    toolbarView.alpha = 0.0
                }
                toolbarTransition.setFrame(view: toolbarView, frame: toolbarFrame)
                ComponentTransition(transition).setAlpha(view: toolbarView, alpha: 1.0)
            }
        } else if let toolbar = self.toolbar {
            self.toolbar = nil
            if let toolbarView = toolbar.view {
                ComponentTransition(transition).setAlpha(view: toolbarView, alpha: 0.0, completion: { [weak toolbarView] _ in
                    toolbarView?.removeFromSuperview()
                })
            }
        }
        
        if params.toolbar == nil && !hasVisibleTabBarContent {
            return 0.0
        }
        return params.layout.size.height - tabBarFrame.minY
    }
    
    func frameForControllerTab(at index: Int) -> CGRect? {
        guard let tabBarView = self.tabBarView.view as? TabBarComponent.View else {
            return nil
        }
        guard self.tabBarItems.indices.contains(index) else {
            return nil
        }
        let itemId = AnyHashable(ObjectIdentifier(self.tabBarItems[index].item))
        guard let itemFrame = tabBarView.frameForItem(id: itemId) else {
            return nil
        }
        return self.view.convert(itemFrame, from: tabBarView)
    }
    
    func isPointInsideContentArea(point: CGPoint) -> Bool {
        guard let tabBarView = self.tabBarView.view else {
            return false
        }
        if point.y < tabBarView.frame.minY {
            return true
        }
        return false
    }
    
    func updateTabBarItems(items: [TabBarNodeItem]) {
        self.tabBarItems = items
        self.requestUpdate()
    }
    
    func updateSelectedIndex(index: Int) {
        self.selectedIndex = index
        self.isChangingSelectedIndex = true
        self.requestUpdate()
    }
}
