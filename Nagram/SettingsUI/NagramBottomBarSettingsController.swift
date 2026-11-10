import AccountContext
import AsyncDisplayKit
import ComponentFlow
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TabBarComponent
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData
import UIKit

private final class NagramBottomBarArguments {
    let update: ((inout NagramBottomBarSettings) -> Void) -> Void
    let option: (NagramBottomBarOption) -> Void
    let reset: () -> Void
    let setHeaderButtonVisible: (NagramBottomBarSwitchOption, Bool) -> Void
    let setTitle: (String) -> Void
    let appWindow: () -> UIWindow?

    init(update: @escaping ((inout NagramBottomBarSettings) -> Void) -> Void, option: @escaping (NagramBottomBarOption) -> Void, reset: @escaping () -> Void, setHeaderButtonVisible: @escaping (NagramBottomBarSwitchOption, Bool) -> Void, setTitle: @escaping (String) -> Void, appWindow: @escaping () -> UIWindow?) {
        self.update = update
        self.option = option
        self.reset = reset
        self.setHeaderButtonVisible = setHeaderButtonVisible
        self.setTitle = setTitle
        self.appWindow = appWindow
    }
}

private enum NagramBottomBarSwitchOption: Int32 {
    case topSearch
    case labels
    case editButton
    case composeButton
    case settingsButton
}

private enum NagramBottomBarOption: Int32 {
    case alignment
    case searchMode
}

private enum NagramBottomBarEntry: ItemListNodeEntry {
    case preview(section: Int32, settings: NagramBottomBarSettings, strings: PresentationStrings, itemTitles: [NagramBottomBarItemId: String], topSearchTitle: String, topSearchVisibleHint: String, topSearchHiddenHint: String, bottomBarTitle: String, emptyBottomTitle: String)
    case header(stableId: Int32, section: Int32, text: String)
    case toggle(stableId: Int32, section: Int32, title: String, value: Bool, option: NagramBottomBarSwitchOption)
    case visibility(stableId: Int32, section: Int32, title: String, settings: NagramBottomBarSettings, itemTitles: [NagramBottomBarItemId: String])
    case slider(stableId: Int32, section: Int32, title: String, value: Int32)
    case disclosure(stableId: Int32, section: Int32, title: String, label: String, option: NagramBottomBarOption)
    case reset(stableId: Int32, section: Int32, title: String)
    case footer(stableId: Int32, section: Int32, text: String)
    case title(stableId: Int32, section: Int32, title: String, text: String, placeholder: String)

    var section: ItemListSectionId {
        switch self {
        case let .preview(section, _, _, _, _, _, _, _, _):
            return section
        case let .header(_, section, _):
            return section
        case let .toggle(_, section, _, _, _):
            return section
        case let .visibility(_, section, _, _, _):
            return section
        case let .slider(_, section, _, _):
            return section
        case let .disclosure(_, section, _, _, _):
            return section
        case let .reset(_, section, _):
            return section
        case let .footer(_, section, _):
            return section
        case let .title(_, section, _, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case .preview:
            return 0
        case let .header(stableId, _, _):
            return stableId
        case let .toggle(stableId, _, _, _, _):
            return stableId
        case let .visibility(stableId, _, _, _, _):
            return stableId
        case let .slider(stableId, _, _, _):
            return stableId
        case let .disclosure(stableId, _, _, _, _):
            return stableId
        case let .reset(stableId, _, _):
            return stableId
        case let .footer(stableId, _, _):
            return stableId
        case let .title(stableId, _, _, _, _):
            return stableId
        }
    }

    static func ==(lhs: NagramBottomBarEntry, rhs: NagramBottomBarEntry) -> Bool {
        switch lhs {
        case let .preview(lSection, lSettings, lStrings, lItemTitles, lTopSearchTitle, lTopSearchVisibleHint, lTopSearchHiddenHint, lBottomBarTitle, lEmptyBottomTitle):
            if case let .preview(rSection, rSettings, rStrings, rItemTitles, rTopSearchTitle, rTopSearchVisibleHint, rTopSearchHiddenHint, rBottomBarTitle, rEmptyBottomTitle) = rhs {
                return lSection == rSection && lSettings == rSettings && lStrings.baseLanguageCode == rStrings.baseLanguageCode && lItemTitles == rItemTitles && lTopSearchTitle == rTopSearchTitle && lTopSearchVisibleHint == rTopSearchVisibleHint && lTopSearchHiddenHint == rTopSearchHiddenHint && lBottomBarTitle == rBottomBarTitle && lEmptyBottomTitle == rEmptyBottomTitle
            }
            return false
        case let .header(lId, lSection, lText):
            if case let .header(rId, rSection, rText) = rhs {
                return lId == rId && lSection == rSection && lText == rText
            }
            return false
        case let .toggle(lId, lSection, lTitle, lValue, lOption):
            if case let .toggle(rId, rSection, rTitle, rValue, rOption) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue && lOption == rOption
            }
            return false
        case let .visibility(lId, lSection, lTitle, lSettings, lItemTitles):
            if case let .visibility(rId, rSection, rTitle, rSettings, rItemTitles) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lSettings == rSettings && lItemTitles == rItemTitles
            }
            return false
        case let .slider(lId, lSection, lTitle, lValue):
            if case let .slider(rId, rSection, rTitle, rValue) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue
            }
            return false
        case let .disclosure(lId, lSection, lTitle, lLabel, lOption):
            if case let .disclosure(rId, rSection, rTitle, rLabel, rOption) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lLabel == rLabel && lOption == rOption
            }
            return false
        case let .reset(lId, lSection, lTitle):
            if case let .reset(rId, rSection, rTitle) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle
            }
            return false
        case let .footer(lId, lSection, lText):
            if case let .footer(rId, rSection, rText) = rhs {
                return lId == rId && lSection == rSection && lText == rText
            }
            return false
        case let .title(lId, lSection, lTitle, lText, lPlaceholder):
            if case let .title(rId, rSection, rTitle, rText, rPlaceholder) = rhs {
                return lId == rId && lSection == rSection && lTitle == rTitle && lText == rText && lPlaceholder == rPlaceholder
            }
            return false
        }
    }

    static func <(lhs: NagramBottomBarEntry, rhs: NagramBottomBarEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    var tag: ItemListItemTag? {
        switch self {
        case let .toggle(_, _, _, _, option):
            switch option {
            case .topSearch:
                return NagramSettingsFocusTag("TopSearch")
            case .labels:
                return NagramSettingsFocusTag("ShowLabels")
            case .editButton:
                return NagramSettingsFocusTag("EditButton")
            case .composeButton:
                return NagramSettingsFocusTag("ComposeButton")
            case .settingsButton:
                return NagramSettingsFocusTag("SettingsButton")
            }
        case .title:
            return NagramSettingsFocusTag("ChatListTitle")
        case .visibility:
            return NagramSettingsFocusTag("Visibility")
        case .slider:
            return NagramSettingsFocusTag("ButtonWidth")
        case let .disclosure(_, _, _, _, option):
            switch option {
            case .alignment:
                return NagramSettingsFocusTag("Alignment")
            case .searchMode:
                return NagramSettingsFocusTag("SearchStyle")
            }
        case .preview, .header, .reset, .footer:
            return nil
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramBottomBarArguments
        switch self {
        case let .preview(_, settings, strings, itemTitles, topSearchTitle, topSearchVisibleHint, topSearchHiddenHint, bottomBarTitle, emptyBottomTitle):
            return NagramBottomBarPreviewItem(
                theme: presentationData.theme,
                settings: settings,
                strings: strings,
                itemTitles: itemTitles,
                topSearchTitle: topSearchTitle,
                topSearchVisibleHint: topSearchVisibleHint,
                topSearchHiddenHint: topSearchHiddenHint,
                bottomBarTitle: bottomBarTitle,
                emptyBottomTitle: emptyBottomTitle,
                sectionId: self.section,
                update: arguments.update,
                appWindow: arguments.appWindow
            )
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, title, value, option):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                switch option {
                case .topSearch:
                    arguments.update { $0.topSearchVisible = value }
                case .labels:
                    arguments.update { $0.showLabels = value }
                case .editButton, .composeButton, .settingsButton:
                    arguments.setHeaderButtonVisible(option, value)
                }
            }, tag: self.tag)
        case let .title(_, section, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: .regular(capitalization: true, autocorrection: false), spacing: 8.0, clearType: .onFocus, tag: self.tag, sectionId: section, textUpdated: { value in
                arguments.setTitle(value)
            }, action: {})
        case let .visibility(_, section, title, settings, itemTitles):
            let visibleBottomItems = Set(settings.visibleBottomItems)
            let chips = NagramBottomBarItemId.allCases.map { id in
                let isSelected = settings.isVisible(id)
                let isEnabled = id == .search || !isSelected || !visibleBottomItems.contains(id) || settings.canHide(id)
                return NagramBottomBarChipRowItem.Chip(id: id.rawValue, title: itemTitles[id] ?? id.rawValue, isSelected: isSelected, isEnabled: isEnabled)
            }
            return NagramBottomBarChipRowItem(theme: presentationData.theme, title: title, chips: chips, sectionId: section, selected: { rawValue in
                guard let id = NagramBottomBarItemId(rawValue: rawValue) else {
                    return
                }
                arguments.update { settings in
                    if id == .search {
                        settings.toggleHidden(.search)
                    } else {
                        if settings.isVisible(id) {
                            settings.hide(id)
                        } else {
                            settings.moveToBottom(id, at: settings.bottomItems.count)
                        }
                    }
                }
            })
        case let .slider(_, section, title, value):
            return NagramSliderItem(theme: presentationData.theme, minValue: 0, maxValue: 100, value: value, title: title, sectionId: section, updated: { value in
                arguments.update { settings in
                    settings.buttonWidthFillRatio = value
                    settings.widthMode = value >= 100 ? .full : .adaptive
                    settings.slotMode = value <= 0 ? .preserveHidden : .visibleOnly
                }
            }, tag: self.tag)
        case let .disclosure(_, section, title, label, option):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.option(option)
            }, tag: self.tag)
        case let .reset(_, section, title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: {
                arguments.reset()
            })
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func nagramBottomBarSettingsCanUseSearchBar(_ settings: NagramBottomBarSettings) -> Bool {
    return settings.isVisible(.search) && settings.visibleBottomItems.isEmpty
}

private func nagramBottomBarSettingsNormalizedForLayout(_ settings: NagramBottomBarSettings) -> NagramBottomBarSettings {
    var result = settings
    if result.searchMode == .bar && !nagramBottomBarSettingsCanUseSearchBar(result) {
        result.setSearchMode(.button)
    }
    return result
}

private func nagramBottomBarSettings(_ settings: NagramBottomBarSettings, applyingShowCallsTab showCallsTab: Bool) -> NagramBottomBarSettings {
    var result = settings
    result.setVisible(.calls, visible: showCallsTab)
    return nagramBottomBarSettingsNormalizedForLayout(result)
}

public func nagramBottomBarSettingsController(context: AccountContext, focusOnRow: String? = nil) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var currentShowCallsTab = CallListSettings.defaultSettings.showTab
    var pendingShowCallsTab: Bool?

    let saveSettings: (NagramBottomBarSettings) -> Void = { settings in
        let normalizedSettings = nagramBottomBarSettingsNormalizedForLayout(settings)
        let nextShowCallsTab = normalizedSettings.isVisible(.calls)
        NagramSettings.shared.bottomBarSettings = normalizedSettings
        if nextShowCallsTab != currentShowCallsTab {
            currentShowCallsTab = nextShowCallsTab
            pendingShowCallsTab = nextShowCallsTab
            let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, {
                $0.withUpdatedShowTab(nextShowCallsTab)
            }).startStandalone()
        }
    }

    let arguments = NagramBottomBarArguments(update: { update in
        var settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
        update(&settings)
        saveSettings(settings)
        bump()
    }, option: { option in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }

        let titleKey: String
        let items: [(String, (inout NagramBottomBarSettings) -> Void)]
        switch option {
        case .alignment:
            titleKey = "Nagram.BottomBarLayout.Alignment"
            items = [
                ("Nagram.BottomBarLayout.Alignment.spaceBetween", { $0.alignment = .spaceBetween }),
                ("Nagram.BottomBarLayout.Alignment.leftCenter", { $0.alignment = .leftCenter }),
                ("Nagram.BottomBarLayout.Alignment.center", { $0.alignment = .center }),
            ]
        case .searchMode:
            titleKey = "Nagram.BottomBarLayout.SearchStyle"
            let settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
            items = [
                ("Nagram.BottomBarLayout.SearchStyle.button", { $0.setSearchMode(.button) })
            ] + (nagramBottomBarSettingsCanUseSearchBar(settings) ? [
                ("Nagram.BottomBarLayout.SearchStyle.bar", { $0.setSearchMode(.bar) })
            ] : [])
        }

        var actionItems: [ActionSheetItem] = [ActionSheetTextItem(title: ngI18n(titleKey, lang))]
        for (key, apply) in items {
            actionItems.append(ActionSheetButtonItem(title: ngI18n(key, lang), color: .accent, action: {
                dismissAction()
                var settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
                apply(&settings)
                saveSettings(settings)
                bump()
            }))
        }
        if option == .searchMode && items.count == 1 {
            actionItems.append(ActionSheetTextItem(title: ngI18n("Nagram.BottomBarLayout.SearchStyle.BarDisabled", lang)))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: actionItems),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, reset: {
        saveSettings(NagramBottomBarSettings())
        NagramSettings.shared.hideChatListEditButton = false
        NagramSettings.shared.hideChatListComposeButton = false
        NagramSettings.shared.hideChatListSettingsButton = false
        NagramSettings.shared.chatListTitle = ""
        bump()
    }, setHeaderButtonVisible: { option, visible in
        switch option {
        case .editButton:
            NagramSettings.shared.hideChatListEditButton = !visible
        case .composeButton:
            NagramSettings.shared.hideChatListComposeButton = !visible
        case .settingsButton:
            NagramSettings.shared.hideChatListSettingsButton = !visible
        case .topSearch, .labels:
            return
        }
        bump()
    }, setTitle: { value in
        NagramSettings.shared.chatListTitle = value
    }, appWindow: {
        return context.sharedContext.mainWindow?.viewController?.view.window
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get(),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> Bool in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self)?.showTab ?? CallListSettings.defaultSettings.showTab
        }
    )
    |> map { presentationData, _, showCallsTab -> (ItemListControllerState, (ItemListNodeState, Any)) in
        if let pendingShowCallsTabValue = pendingShowCallsTab {
            if showCallsTab == pendingShowCallsTabValue {
                pendingShowCallsTab = nil
            }
            currentShowCallsTab = pendingShowCallsTabValue
        } else {
            currentShowCallsTab = showCallsTab
        }
        let lang = presentationData.strings.baseLanguageCode
        let settings = nagramBottomBarSettings(NagramSettings.shared.bottomBarSettings, applyingShowCallsTab: currentShowCallsTab)
        let itemTitles: [NagramBottomBarItemId: String] = [
            .contacts: ngI18n("Nagram.BottomBarLayout.Item.contacts", lang),
            .calls: ngI18n("Nagram.BottomBarLayout.Item.calls", lang),
            .chats: ngI18n("Nagram.BottomBarLayout.Item.chats", lang),
            .settings: ngI18n("Nagram.BottomBarLayout.Item.settings", lang),
            .search: ngI18n("Nagram.BottomBarLayout.Item.search", lang)
        ]

        let alignmentLabel: String
        switch settings.alignment {
        case .spaceBetween:
            alignmentLabel = ngI18n("Nagram.BottomBarLayout.Alignment.spaceBetween", lang)
        case .leftCenter:
            alignmentLabel = ngI18n("Nagram.BottomBarLayout.Alignment.leftCenter", lang)
        case .center:
            alignmentLabel = ngI18n("Nagram.BottomBarLayout.Alignment.center", lang)
        }

        // The fallback settings button only exists while the bottom bar has no Settings entry.
        let showsSettingsButtonOption = !settings.isBottomBarVisible || !settings.isVisible(.settings)
        var entries: [NagramBottomBarEntry] = [
            .preview(
                section: 0,
                settings: settings,
                strings: presentationData.strings,
                itemTitles: itemTitles,
                topSearchTitle: ngI18n("Nagram.BottomBarLayout.TopBar", lang),
                topSearchVisibleHint: ngI18n("Nagram.BottomBarLayout.TopSearchHint.visible", lang),
                topSearchHiddenHint: ngI18n("Nagram.BottomBarLayout.TopSearchHint.hidden", lang),
                bottomBarTitle: ngI18n("Nagram.BottomBarLayout.BottomBar", lang),
                emptyBottomTitle: ngI18n("Nagram.BottomBarLayout.EmptyBottom", lang)
            ),
            .header(stableId: 1, section: 1, text: ngI18n("Nagram.BottomBarLayout.TopBar", lang)),
            .title(stableId: 2, section: 1, title: ngI18n("Nagram.BottomBarLayout.ChatListTitle", lang), text: NagramSettings.shared.chatListTitle, placeholder: presentationData.strings.DialogList_Title),
            .toggle(stableId: 3, section: 1, title: ngI18n("Nagram.BottomBarLayout.TopSearch", lang), value: settings.topSearchVisible, option: .topSearch),
            .toggle(stableId: 4, section: 1, title: ngI18n("Nagram.BottomBarLayout.EditButton", lang), value: !NagramSettings.shared.hideChatListEditButton, option: .editButton),
            .toggle(stableId: 5, section: 1, title: ngI18n("Nagram.BottomBarLayout.ComposeButton", lang), value: !NagramSettings.shared.hideChatListComposeButton, option: .composeButton),
        ]
        if showsSettingsButtonOption {
            entries.append(.toggle(stableId: 6, section: 1, title: ngI18n("Nagram.BottomBarLayout.SettingsButton", lang), value: !NagramSettings.shared.hideChatListSettingsButton, option: .settingsButton))
            entries.append(.footer(stableId: 7, section: 1, text: ngI18n("Nagram.BottomBarLayout.SettingsButton.Footer", lang)))
        }
        entries.append(contentsOf: [
            .header(stableId: 10, section: 2, text: ngI18n("Nagram.BottomBarLayout.BottomBar", lang)),
            .visibility(stableId: 11, section: 2, title: ngI18n("Nagram.BottomBarLayout.Visibility", lang), settings: settings, itemTitles: itemTitles),
            .disclosure(stableId: 12, section: 2, title: ngI18n("Nagram.BottomBarLayout.SearchStyle", lang), label: settings.searchMode == .bar ? ngI18n("Nagram.BottomBarLayout.SearchStyle.bar", lang) : ngI18n("Nagram.BottomBarLayout.SearchStyle.button", lang), option: .searchMode),
            .toggle(stableId: 13, section: 2, title: ngI18n("Nagram.BottomBarLayout.ShowLabels", lang), value: settings.showLabels, option: .labels),
            .slider(stableId: 14, section: 2, title: ngI18n("Nagram.BottomBarLayout.ButtonWidth", lang), value: settings.buttonWidthFillRatio),
            .disclosure(stableId: 15, section: 2, title: ngI18n("Nagram.BottomBarLayout.Alignment", lang), label: settings.buttonWidthFillRatio >= 100 ? ngI18n("Nagram.BottomBarLayout.Alignment.disabled", lang) : alignmentLabel, option: .alignment),
            .reset(stableId: 20, section: 3, title: ngI18n("Nagram.BottomBarLayout.Reset", lang)),
            .footer(stableId: 21, section: 3, text: ngI18n("Nagram.BottomBarLayout.Footer", lang))
        ])

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.BottomBarLayout", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, initialScrollToItem: nagramFocusScrollToItem(entries: entries, focusOnRow: focusOnRow), animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    nagramHighlightFocusedRow(controller: controller, focusOnRow: focusOnRow)
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    return controller
}

private final class NagramBottomBarChipRowItem: ListViewItem, ItemListItem {
    struct Chip: Equatable {
        let id: String
        let title: String
        let isSelected: Bool
        let isEnabled: Bool
    }

    let theme: PresentationTheme
    let title: String
    let chips: [Chip]
    let sectionId: ItemListSectionId
    let selected: (String) -> Void

    init(theme: PresentationTheme, title: String, chips: [Chip], sectionId: ItemListSectionId, selected: @escaping (String) -> Void) {
        self.theme = theme
        self.title = title
        self.chips = chips
        self.sectionId = sectionId
        self.selected = selected
    }

    var selectable: Bool {
        return false
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NagramBottomBarChipRowItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NagramBottomBarChipRowItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class NagramBottomBarChipButton: UIButton {
    var chipId: String?
}

private final class NagramBottomBarChipRowItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode = ASDisplayNode()
    private let topStripeNode = ASDisplayNode()
    private let bottomStripeNode = ASDisplayNode()
    private let maskNode = ASImageNode()
    private let titleLabel = UILabel()
    private var buttons: [String: NagramBottomBarChipButton] = [:]
    private var item: NagramBottomBarChipRowItem?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        self.backgroundNode.isLayerBacked = true
        super.init(layerBacked: false)
        self.addSubnode(self.backgroundNode)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.titleLabel)
    }

    func asyncLayout() -> (_ item: NagramBottomBarChipRowItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = 16.0
            let contentHeight: CGFloat = 84.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: contentHeight), insets: itemListNeighborsGroupedInsets(neighbors, params))
            let insets = layout.insets
            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                self.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                self.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                self.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                if self.topStripeNode.supernode == nil {
                    self.insertSubnode(self.topStripeNode, aboveSubnode: self.backgroundNode)
                }
                if self.bottomStripeNode.supernode == nil {
                    self.insertSubnode(self.bottomStripeNode, aboveSubnode: self.backgroundNode)
                }
                if self.maskNode.supernode == nil {
                    self.insertSubnode(self.maskNode, aboveSubnode: self.bottomStripeNode)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    self.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    self.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    self.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    self.bottomStripeNode.isHidden = hasCorners
                }

                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentHeight + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentHeight + bottomStripeOffset), size: CGSize(width: params.width - params.rightInset - bottomStripeInset - separatorRightInset, height: separatorHeight))

                self.titleLabel.text = item.title
                self.titleLabel.font = Font.regular(17.0)
                self.titleLabel.textColor = item.theme.list.itemPrimaryTextColor
                self.titleLabel.frame = CGRect(x: params.leftInset + 16.0, y: 12.0, width: params.width - params.leftInset - params.rightInset - 32.0, height: 22.0)

                let availableWidth = params.width - params.leftInset - params.rightInset - 32.0
                let gap: CGFloat = 7.0
                let chipCount = max(1, item.chips.count)
                let chipWidth = floor((availableWidth - gap * CGFloat(chipCount - 1)) / CGFloat(chipCount))
                var activeIds = Set<String>()
                for (index, chip) in item.chips.enumerated() {
                    activeIds.insert(chip.id)
                    let button = self.button(for: chip.id)
                    button.chipId = chip.id
                    button.frame = CGRect(x: params.leftInset + 16.0 + CGFloat(index) * (chipWidth + gap), y: 44.0, width: chipWidth, height: 30.0)
                    self.configure(button: button, chip: chip, theme: item.theme)
                }
                for (id, button) in self.buttons {
                    button.isHidden = !activeIds.contains(id)
                }
            })
        }
    }

    private func button(for id: String) -> NagramBottomBarChipButton {
        if let current = self.buttons[id] {
            return current
        }
        let button = NagramBottomBarChipButton(type: .system)
        button.layer.cornerRadius = 15.0
        button.layer.borderWidth = UIScreenPixel
        button.titleLabel?.font = Font.medium(13.0)
        button.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchUpInside)
        self.view.addSubview(button)
        self.buttons[id] = button
        return button
    }

    private func configure(button: NagramBottomBarChipButton, chip: NagramBottomBarChipRowItem.Chip, theme: PresentationTheme) {
        button.setTitle(chip.title, for: .normal)
        button.isEnabled = chip.isEnabled
        if chip.isSelected {
            let selectedColor = theme.rootController.tabBar.selectedTextColor
            button.backgroundColor = selectedColor
            button.layer.borderColor = selectedColor.cgColor
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = theme.list.itemInputField.backgroundColor
            button.layer.borderColor = theme.list.itemBlocksSeparatorColor.cgColor
            button.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
        }
        button.alpha = chip.isEnabled ? 1.0 : 0.35
    }

    @objc private func buttonPressed(_ button: NagramBottomBarChipButton) {
        guard let chipId = button.chipId else {
            return
        }
        self.item?.selected(chipId)
    }
}

private final class NagramBottomBarPreviewItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let settings: NagramBottomBarSettings
    let strings: PresentationStrings
    let itemTitles: [NagramBottomBarItemId: String]
    let topSearchTitle: String
    let topSearchVisibleHint: String
    let topSearchHiddenHint: String
    let bottomBarTitle: String
    let emptyBottomTitle: String
    let sectionId: ItemListSectionId
    let update: ((inout NagramBottomBarSettings) -> Void) -> Void
    let appWindow: () -> UIWindow?

    init(theme: PresentationTheme, settings: NagramBottomBarSettings, strings: PresentationStrings, itemTitles: [NagramBottomBarItemId: String], topSearchTitle: String, topSearchVisibleHint: String, topSearchHiddenHint: String, bottomBarTitle: String, emptyBottomTitle: String, sectionId: ItemListSectionId, update: @escaping ((inout NagramBottomBarSettings) -> Void) -> Void, appWindow: @escaping () -> UIWindow?) {
        self.theme = theme
        self.settings = settings
        self.strings = strings
        self.itemTitles = itemTitles
        self.topSearchTitle = topSearchTitle
        self.topSearchVisibleHint = topSearchVisibleHint
        self.topSearchHiddenHint = topSearchHiddenHint
        self.bottomBarTitle = bottomBarTitle
        self.emptyBottomTitle = emptyBottomTitle
        self.sectionId = sectionId
        self.update = update
        self.appWindow = appWindow
    }

    var selectable: Bool {
        return false
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NagramBottomBarPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NagramBottomBarPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class NagramBottomBarPreviewItemNode: ListViewItemNode, ItemListItemNode, UIGestureRecognizerDelegate {
    private var item: NagramBottomBarPreviewItem?
    private let topSearchTitleLabel = UILabel()
    private let topSearchHintLabel = UILabel()
    private let bottomBarTitleLabel = UILabel()
    private let emptyBottomLabel = UILabel()
    private let backgroundView = UIView()
    private lazy var topSearchView = NavigationSearchView(action: {}, closeAction: {})
    private let tabBarComponentView = ComponentView<Empty>()
    private let externalDropView = UIView()
    private var itemFrames: [NagramBottomBarItemId: CGRect] = [:]
    private var componentIdsByItemId: [NagramBottomBarItemId: AnyHashable] = [:]
    private var itemIdsByComponentId: [AnyHashable: NagramBottomBarItemId] = [:]
    private var bottomFrame: CGRect = .zero
    private var externalFrame: CGRect = .zero
    private var draggingItem: NagramBottomBarItemId?
    private var panGestureRecognizer: UIPanGestureRecognizer?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.backgroundView)
        self.backgroundView.addSubview(self.topSearchTitleLabel)
        self.backgroundView.addSubview(self.topSearchView)
        self.backgroundView.addSubview(self.topSearchHintLabel)
        self.backgroundView.addSubview(self.bottomBarTitleLabel)
        self.backgroundView.addSubview(self.emptyBottomLabel)
        self.backgroundView.addSubview(self.externalDropView)

        self.topSearchView.isUserInteractionEnabled = false

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        self.backgroundView.addGestureRecognizer(panGesture)
        self.panGestureRecognizer = panGesture
    }

    func asyncLayout() -> (_ item: NagramBottomBarPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let height: CGFloat = 228.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item
                self.backgroundColor = item.theme.list.blocksBackgroundColor
                self.configure(theme: item.theme, params: params, height: height)
            })
        }
    }

    private func configure(theme: PresentationTheme, params: ListViewItemLayoutParams, height: CGFloat) {
        guard let item = self.item else {
            return
        }

        let controlLeftInset = params.leftInset + 16.0
        let controlRightInset = params.rightInset + 16.0
        let controlWidth = params.width - controlLeftInset - controlRightInset

        self.backgroundView.frame = CGRect(x: 0.0, y: 8.0, width: params.width, height: height - 16.0)
        self.backgroundView.backgroundColor = .clear
        self.backgroundView.layer.cornerRadius = 0.0
        self.backgroundView.clipsToBounds = false

        self.topSearchTitleLabel.frame = CGRect(x: controlLeftInset, y: 14.0, width: controlWidth, height: 18.0)
        self.topSearchTitleLabel.text = item.topSearchTitle
        self.topSearchTitleLabel.font = Font.regular(11.0)
        self.topSearchTitleLabel.textColor = theme.list.itemSecondaryTextColor

        let topSearchFrame = CGRect(x: controlLeftInset, y: 36.0, width: controlWidth, height: 42.0)
        self.topSearchView.frame = topSearchFrame
        self.topSearchView.update(size: topSearchFrame.size, theme: theme, strings: item.strings, isActive: false, isExpanded: true, transition: .immediate)
        self.topSearchView.alpha = item.settings.topSearchVisible ? 1.0 : 0.35

        self.topSearchHintLabel.frame = CGRect(x: controlLeftInset, y: 80.0, width: controlWidth, height: 16.0)
        self.topSearchHintLabel.text = item.settings.topSearchVisible ? item.topSearchVisibleHint : item.topSearchHiddenHint
        self.topSearchHintLabel.font = Font.regular(10.0)
        self.topSearchHintLabel.textColor = item.settings.topSearchVisible ? theme.list.itemSecondaryTextColor : theme.list.itemDisabledTextColor

        self.bottomBarTitleLabel.frame = CGRect(x: controlLeftInset, y: 104.0, width: controlWidth, height: 18.0)
        self.bottomBarTitleLabel.text = item.bottomBarTitle
        self.bottomBarTitleLabel.font = Font.regular(11.0)
        self.bottomBarTitleLabel.textColor = theme.list.itemSecondaryTextColor

        self.emptyBottomLabel.text = item.emptyBottomTitle
        self.emptyBottomLabel.textAlignment = .center
        self.emptyBottomLabel.font = Font.regular(13.0)
        self.emptyBottomLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyBottomLabel.backgroundColor = theme.list.itemInputField.backgroundColor
        self.emptyBottomLabel.layer.cornerRadius = 16.0
        self.emptyBottomLabel.layer.masksToBounds = true

        self.updateTabBarPreview(theme: theme, params: params)
    }

    private func updateTabBarPreview(theme: PresentationTheme, params: ListViewItemLayoutParams) {
        guard let item = self.item else {
            return
        }

        var previewSettings = item.settings
        previewSettings.isBottomBarVisible = true

        self.componentIdsByItemId.removeAll()
        self.itemIdsByComponentId.removeAll()
        self.itemFrames.removeAll()

        let makeComponentItem: (NagramBottomBarItemId) -> TabBarComponent.Item = { [weak self] id in
            let componentId = AnyHashable("nagram.preview.\(id.rawValue)")
            self?.componentIdsByItemId[id] = componentId
            self?.itemIdsByComponentId[componentId] = id

            let icon: TabBarComponent.Item.Content.CustomItem.Icon
            switch id {
            case .contacts:
                icon = .animation(name: "TabContacts", offset: .zero)
            case .calls:
                icon = .animation(name: "TabCalls", offset: .zero)
            case .chats:
                icon = .animation(name: "TabChats", offset: .zero)
            case .settings:
                icon = .animation(name: "TabSettings", offset: .zero)
            case .search:
                icon = .bundleIcon(name: "Navigation/Search")
            }

            return TabBarComponent.Item(
                content: .customItem(TabBarComponent.Item.Content.CustomItem(id: componentId, title: item.itemTitles[id] ?? id.rawValue, icon: icon)),
                action: { _ in },
                doubleTapAction: nil,
                contextAction: nil
            )
        }

        let visibleBottomItems = previewSettings.visibleBottomItems
        let visibleComponentItems = visibleBottomItems.map(makeComponentItem)
        let externalComponentItem: TabBarComponent.Item?
        if let externalItem = previewSettings.externalItem, externalItem != .search, !previewSettings.hiddenItems.contains(externalItem) {
            externalComponentItem = makeComponentItem(externalItem)
        } else {
            externalComponentItem = nil
        }

        let searchIsVisible = previewSettings.isVisible(.search)
        let search = searchIsVisible ? TabBarComponent.Search(
            isActive: false,
            showsButton: previewSettings.searchMode != .bar,
            activate: {},
            deactivate: {}
        ) : nil

        let selectedId = self.componentIdsByItemId[.chats] ?? visibleBottomItems.compactMap { self.componentIdsByItemId[$0] }.first ?? previewSettings.externalItem.flatMap { self.componentIdsByItemId[$0] }
        let layoutItemCount = max(visibleComponentItems.count, NagramBottomBarSettings.defaultBottomItems.count)
        // Lists on iPad and in split view inset their content; keep the bar inside those insets or it gets clipped.
        let previewSideInset: CGFloat = 12.0
        let previewLeft = params.leftInset + previewSideInset
        let availableWidth = max(120.0, params.width - params.leftInset - params.rightInset - previewSideInset * 2.0)
        let allButtonsHidden = visibleComponentItems.isEmpty && externalComponentItem == nil && !searchIsVisible
        if allButtonsHidden {
            self.emptyBottomLabel.isHidden = false
            self.emptyBottomLabel.frame = CGRect(x: previewLeft, y: 130.0, width: availableWidth, height: 64.0)
            self.tabBarComponentView.view?.isHidden = true
            self.bottomFrame = self.emptyBottomLabel.frame
            self.externalFrame = CGRect(x: previewLeft + availableWidth - 64.0, y: 130.0, width: 64.0, height: 64.0)
            self.externalDropView.isHidden = true
            return
        } else {
            self.emptyBottomLabel.isHidden = true
        }
        // Match the real bar (TabBarControllerNode): a regular-width window (iPad) lays it out compact, without titles,
        // and a landscape window at least 568pt wide keeps the custom layout instead of the system one.
        let window = item.appWindow()
        let isCompact = window?.traitCollection.horizontalSizeClass == .regular
        let windowSize = window?.bounds.size ?? .zero
        let isWide = windowSize.width > windowSize.height && windowSize.width >= 568.0
        let tabBarSize = self.tabBarComponentView.update(
            transition: .immediate,
            component: AnyComponent(TabBarComponent(
                theme: theme,
                strings: item.strings,
                items: visibleComponentItems,
                externalItem: externalComponentItem,
                search: search,
                selectedId: selectedId,
                outerInsets: .zero,
                isCompact: isCompact,
                usesSystemLayout: !isWide,
                layoutItemCount: layoutItemCount,
                isAdaptiveWidth: false,
                alignItemsToLeft: previewSettings.alignment == .spaceBetween,
                centerItemsInAvailableWidth: previewSettings.alignment == .center,
                showItemTitles: previewSettings.showLabels,
                buttonWidthFillRatio: CGFloat(previewSettings.buttonWidthFillRatio) / 100.0
            )),
            environment: {},
            containerSize: CGSize(width: availableWidth, height: 80.0)
        )

        if let tabBarView = self.tabBarComponentView.view {
            if tabBarView.superview !== self.backgroundView {
                self.backgroundView.addSubview(tabBarView)
            }
            tabBarView.isHidden = false

            let onlySearchButton = searchIsVisible && previewSettings.searchMode != .bar && visibleComponentItems.isEmpty && externalComponentItem == nil
            let fillsAvailableWidth = !onlySearchButton && (previewSettings.buttonWidthFillRatio >= 100 || externalComponentItem != nil || searchIsVisible)
            let tabBarX: CGFloat
            if onlySearchButton {
                tabBarX = previewLeft + availableWidth - tabBarSize.width
            } else if previewSettings.alignment == .spaceBetween && !fillsAvailableWidth {
                tabBarX = previewLeft
            } else {
                tabBarX = previewLeft + floor((availableWidth - tabBarSize.width) * 0.5)
            }
            let tabBarFrame = CGRect(origin: CGPoint(x: tabBarX, y: 130.0), size: tabBarSize)
            tabBarView.frame = tabBarFrame
            tabBarView.isUserInteractionEnabled = false
            tabBarView.alpha = item.settings.isBottomBarVisible ? 1.0 : 0.45

            for (componentId, itemId) in self.itemIdsByComponentId {
                if let componentView = tabBarView as? TabBarComponent.View, let frame = componentView.frameForItem(id: componentId) {
                    self.itemFrames[itemId] = self.backgroundView.convert(frame, from: componentView)
                }
            }

            let bottomItemFrames = visibleBottomItems.compactMap { self.itemFrames[$0] }
            self.bottomFrame = bottomItemFrames.reduce(CGRect.null) { partialResult, frame in
                return partialResult.isNull ? frame : partialResult.union(frame)
            }
            if self.bottomFrame.isNull {
                self.bottomFrame = CGRect(x: tabBarFrame.minX, y: tabBarFrame.minY, width: max(48.0, tabBarFrame.width - 72.0), height: 64.0)
            }

            // The alignment can move the standalone slot away from the trailing edge; follow the bar's own slot.
            let fixedExternalFrame: CGRect
            if !onlySearchButton, let componentView = tabBarView as? TabBarComponent.View, let slotFrame = componentView.standaloneSlotFrame {
                fixedExternalFrame = self.backgroundView.convert(slotFrame, from: componentView)
            } else {
                fixedExternalFrame = CGRect(x: previewLeft + availableWidth - 64.0, y: tabBarFrame.minY, width: 64.0, height: 64.0)
            }
            if let externalItem = previewSettings.externalItem, externalItem != .search, let frame = self.itemFrames[externalItem] {
                self.externalFrame = frame
            } else {
                self.externalFrame = fixedExternalFrame
            }

            let hasExternalSlotContent = searchIsVisible || externalComponentItem != nil
            self.externalDropView.isHidden = true
            self.externalDropView.frame = self.externalFrame
            self.externalDropView.layer.cornerRadius = 32.0
            self.externalDropView.layer.borderWidth = 1.0
            self.externalDropView.layer.borderColor = theme.list.itemBlocksSeparatorColor.cgColor
            self.externalDropView.backgroundColor = theme.list.itemInputField.backgroundColor.withAlphaComponent(0.55)
            if !hasExternalSlotContent {
                self.backgroundView.bringSubviewToFront(self.externalDropView)
            }
        }
    }

    @objc private func panGesture(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self.backgroundView)
        switch gesture.state {
        case .began:
            self.draggingItem = self.itemId(at: point)
        case .ended, .cancelled:
            guard let draggingItem = self.draggingItem else {
                return
            }
            self.draggingItem = nil
            if self.externalFrame.insetBy(dx: -16.0, dy: -16.0).contains(point) {
                self.item?.update { settings in
                    settings.moveToExternal(draggingItem)
                }
            } else if self.bottomFrame.insetBy(dx: -16.0, dy: -16.0).contains(point) {
                let visibleItems = self.previewVisibleBottomItems()
                var targetIndex = self.targetBottomIndex(at: point, visibleItems: visibleItems)
                if let sourceIndex = visibleItems.firstIndex(of: draggingItem), targetIndex > sourceIndex {
                    targetIndex -= 1
                }
                self.item?.update { settings in
                    settings.moveToBottom(draggingItem, at: targetIndex)
                }
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGestureRecognizer = self.panGestureRecognizer, gestureRecognizer === panGestureRecognizer {
            let point = gestureRecognizer.location(in: self.backgroundView)
            return self.itemId(at: point) != nil
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self.backgroundView)
        if self.topSearchView.frame.contains(point) || self.bottomBarTitleLabel.frame.contains(point) {
            return false
        }
        return true
    }

    private func itemId(at point: CGPoint) -> NagramBottomBarItemId? {
        if let item = self.item, item.settings.isVisible(.search), self.externalFrame.insetBy(dx: -8.0, dy: -8.0).contains(point) {
            return .search
        }
        if let match = self.itemFrames.first(where: { $0.value.insetBy(dx: -8.0, dy: -8.0).contains(point) }) {
            return match.key
        }
        return nil
    }

    private func previewVisibleBottomItems() -> [NagramBottomBarItemId] {
        guard let item = self.item else {
            return []
        }
        var settings = item.settings
        settings.isBottomBarVisible = true
        return settings.visibleBottomItems
    }

    private func targetBottomIndex(at point: CGPoint, visibleItems: [NagramBottomBarItemId]) -> Int {
        guard !visibleItems.isEmpty else {
            return 0
        }
        for (index, id) in visibleItems.enumerated() {
            guard let frame = self.itemFrames[id] else {
                continue
            }
            if point.x < frame.midX {
                return index
            }
        }
        return visibleItems.count
    }
}
