import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NagramSettings
import NagramStrings
import TelegramUIPreferences

// MARK: NAGRAM — 增强设置页 UI。
// 顶部 3 段(通用/消息/其他)用 ItemListControllerTitle.sectionControl;段内用 section header 分层。
// 数据驱动:nagramGroups() 描述「tab → 段内分组(header/footer/行)」,加开关只改这张表。
// 行类型 NagramRow:toggle(开关)/ choice(disclosure + ActionSheet 弹选,下载加速)/ slider(行内百分比滑杆,贴纸尺寸)。
// 刷新机制:本地 updatePromise + bump()。toggle/choice 改值后调 bump() 触发列表重建(在 setter 返回之后,
// 不在 UserDefaults.didChange 同步回调内,故无 Swift 独占访问重入崩溃);slider 拖动时本节点自显示,不 bump。
// 文案全部走 ngI18n(key, lang) 本地化(zh-hans/en/zh-hant/ja)。
private enum NagramTab: Int32, CaseIterable {
    case general
    case chat
    case other

    var titleKey: String {
        switch self {
        case .general: return "Nagram.Tab.General"
        case .chat: return "Nagram.Tab.Chat"
        case .other: return "Nagram.Tab.Other"
        }
    }
}

// 行类型:开关 / 单选(disclosure + ActionSheet) / 行内滑杆。
private enum NagramRow {
    case toggle(titleKey: String, get: () -> Bool, set: (Bool) -> Void)
    case toggleWithEnabled(titleKey: String, get: () -> Bool, set: (Bool) -> Void, enabled: () -> Bool)
    case choice(titleKey: String, prefix: String, options: [String], current: () -> String, set: (String) -> Void)
    case slider(minValue: Int32, maxValue: Int32, get: () -> Int32, set: (Int32) -> Void)
    case navigation(titleKey: String, action: () -> Void)
}

private struct NagramGroup {
    let tab: NagramTab
    let headerKey: String?
    let footerKey: String?
    let rows: [NagramRow]
}

private func nagramGroups(hideCalls: @escaping () -> Bool, setHideCalls: @escaping (Bool) -> Void, messageMenuAction: @escaping () -> Void) -> [NagramGroup] {
    let tabBarSubitemEnabled: () -> Bool = {
        return !NagramSettings.shared.hideTabBar
    }
    return [
        // 通用
        NagramGroup(tab: .general, headerKey: "Nagram.Section.Interface", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.HideTabBar", get: { NagramSettings.shared.hideTabBar }, set: { NagramSettings.shared.hideTabBar = $0 }),
            .toggleWithEnabled(titleKey: "Nagram.HideTabBarCalls", get: hideCalls, set: setHideCalls, enabled: tabBarSubitemEnabled),
            .toggleWithEnabled(titleKey: "Nagram.HideTabBarContacts", get: { NagramSettings.shared.hideTabBarContacts }, set: { NagramSettings.shared.hideTabBarContacts = $0 }, enabled: tabBarSubitemEnabled),
            .toggleWithEnabled(titleKey: "Nagram.HideTabBarChatList", get: { NagramSettings.shared.hideTabBarChats }, set: { NagramSettings.shared.hideTabBarChats = $0 }, enabled: tabBarSubitemEnabled),
            .toggleWithEnabled(titleKey: "Nagram.HideTabBarSettings", get: { NagramSettings.shared.hideTabBarSettings }, set: { NagramSettings.shared.hideTabBarSettings = $0 }, enabled: tabBarSubitemEnabled),
            .toggleWithEnabled(titleKey: "Nagram.ShowTabBarSearch", get: { NagramSettings.shared.showTabBarSearch }, set: { NagramSettings.shared.showTabBarSearch = $0 }, enabled: tabBarSubitemEnabled),
            .toggleWithEnabled(titleKey: "Nagram.WideTabBar", get: { NagramSettings.shared.wideTabBar }, set: { NagramSettings.shared.wideTabBar = $0 }, enabled: tabBarSubitemEnabled),
            .toggle(titleKey: "Nagram.HideStories", get: { NagramSettings.shared.hideStories }, set: { NagramSettings.shared.hideStories = $0 }),
        ]),
        NagramGroup(tab: .general, headerKey: "Nagram.Section.Camera", footerKey: "Nagram.Section.Camera.Footer", rows: [
            .toggle(titleKey: "Nagram.DisableGalleryCamera", get: { NagramSettings.shared.disableGalleryCamera }, set: { NagramSettings.shared.disableGalleryCamera = $0 }),
            .toggle(titleKey: "Nagram.DisableGalleryCameraPreview", get: { NagramSettings.shared.disableGalleryCameraPreview }, set: { NagramSettings.shared.disableGalleryCameraPreview = $0 }),
        ]),
        NagramGroup(tab: .general, headerKey: "Nagram.Section.Network", footerKey: nil, rows: [
            .choice(titleKey: "Nagram.DownloadSpeedBoost", prefix: "Nagram.DownloadSpeedBoost", options: ["none", "medium", "maximum"], current: { NagramSettings.shared.downloadSpeedBoost }, set: { NagramSettings.shared.downloadSpeedBoost = $0 }),
            .toggle(titleKey: "Nagram.UploadSpeedBoost", get: { NagramSettings.shared.uploadSpeedBoost }, set: { NagramSettings.shared.uploadSpeedBoost = $0 }),
        ]),
        // 消息
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.MessageDisplay", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.SecondsInMessages", get: { NagramSettings.shared.secondsInMessages }, set: { NagramSettings.shared.secondsInMessages = $0 }),
            .toggle(titleKey: "Nagram.HideReactions", get: { NagramSettings.shared.hideReactions }, set: { NagramSettings.shared.hideReactions = $0 }),
            .toggle(titleKey: "Nagram.HideChannelBottomButton", get: { NagramSettings.shared.hideChannelBottomButton }, set: { NagramSettings.shared.hideChannelBottomButton = $0 }),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.MessageMenu", footerKey: nil, rows: [
            .navigation(titleKey: "Nagram.MessageMenu", action: messageMenuAction),
        ]),
        // 贴纸尺寸:单独成段,header 即标题,行内滑杆中央显示当前 %。
        NagramGroup(tab: .chat, headerKey: "Nagram.StickerSize", footerKey: nil, rows: [
            .slider(minValue: 50, maxValue: 200, get: { NagramSettings.shared.stickerSize }, set: { NagramSettings.shared.stickerSize = $0 }),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.Stickers", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.StickerTimestamp", get: { NagramSettings.shared.stickerTimestamp }, set: { NagramSettings.shared.stickerTimestamp = $0 }),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.Sending", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.DisableSendAsButton", get: { NagramSettings.shared.disableSendAsButton }, set: { NagramSettings.shared.disableSendAsButton = $0 }),
            .toggle(titleKey: "Nagram.SendWithReturnKey", get: { NagramSettings.shared.sendWithReturnKey }, set: { NagramSettings.shared.sendWithReturnKey = $0 }),
            .toggle(titleKey: "Nagram.HideRecordingButton", get: { NagramSettings.shared.hideRecordingButton }, set: { NagramSettings.shared.hideRecordingButton = $0 }),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.Gesture", footerKey: "Nagram.Section.Gesture.Footer", rows: [
            .toggle(titleKey: "Nagram.DisableScrollToNextChannel", get: { NagramSettings.shared.disableScrollToNextChannel }, set: { NagramSettings.shared.disableScrollToNextChannel = $0 }),
            .toggle(titleKey: "Nagram.DisableScrollToNextTopic", get: { NagramSettings.shared.disableScrollToNextTopic }, set: { NagramSettings.shared.disableScrollToNextTopic = $0 }),
            .toggle(titleKey: "Nagram.VideoPIPSwipeUp", get: { NagramSettings.shared.videoPIPSwipeDirection == "up" }, set: { NagramSettings.shared.videoPIPSwipeDirection = $0 ? "up" : "none" }),
        ]),
        // 其他
        NagramGroup(tab: .other, headerKey: "Nagram.Section.Profile", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.ShowProfileId", get: { NagramSettings.shared.showProfileId }, set: { NagramSettings.shared.showProfileId = $0 }),
            .toggle(titleKey: "Nagram.ShowDC", get: { NagramSettings.shared.showDC }, set: { NagramSettings.shared.showDC = $0 }),
            .toggle(titleKey: "Nagram.ShowRegDate", get: { NagramSettings.shared.showRegDate }, set: { NagramSettings.shared.showRegDate = $0 }),
        ]),
        NagramGroup(tab: .other, headerKey: "Nagram.Section.Calls", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.ConfirmCalls", get: { NagramSettings.shared.confirmCalls }, set: { NagramSettings.shared.confirmCalls = $0 }),
        ]),
        NagramGroup(tab: .other, headerKey: "Nagram.Section.Privacy", footerKey: "Nagram.ForceCopy.Footer", rows: [
            .toggle(titleKey: "Nagram.ForceCopy", get: { NagramSettings.shared.forceCopyEnabled }, set: { NagramSettings.shared.forceCopyEnabled = $0 }),
        ]),
    ]
}

private final class NagramSettingsArguments {
    let toggle: (Int, Bool) -> Void
    let disclosureAction: (Int) -> Void
    let sliderUpdated: (Int, Int32) -> Void
    init(toggle: @escaping (Int, Bool) -> Void, disclosureAction: @escaping (Int) -> Void, sliderUpdated: @escaping (Int, Int32) -> Void) {
        self.toggle = toggle
        self.disclosureAction = disclosureAction
        self.sliderUpdated = sliderUpdated
    }
}

private enum NagramSettingsEntry: ItemListNodeEntry {
    case header(stableId: Int32, section: Int32, text: String)
    case toggle(stableId: Int32, section: Int32, title: String, value: Bool, enabled: Bool, index: Int)
    case disclosure(stableId: Int32, section: Int32, title: String, label: String, index: Int)
    case slider(stableId: Int32, section: Int32, minValue: Int32, maxValue: Int32, value: Int32, index: Int)
    case footer(stableId: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _): return section
        case let .toggle(_, section, _, _, _, _): return section
        case let .disclosure(_, section, _, _, _): return section
        case let .slider(_, section, _, _, _, _): return section
        case let .footer(_, section, _): return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(stableId, _, _): return stableId
        case let .toggle(stableId, _, _, _, _, _): return stableId
        case let .disclosure(stableId, _, _, _, _): return stableId
        case let .slider(stableId, _, _, _, _, _): return stableId
        case let .footer(stableId, _, _): return stableId
        }
    }

    static func ==(lhs: NagramSettingsEntry, rhs: NagramSettingsEntry) -> Bool {
        switch lhs {
        case let .header(lId, lSec, lText):
            if case let .header(rId, rSec, rText) = rhs { return lId == rId && lSec == rSec && lText == rText }
            return false
        case let .toggle(lId, lSec, lTitle, lValue, lEnabled, lIndex):
            if case let .toggle(rId, rSec, rTitle, rValue, rEnabled, rIndex) = rhs { return lId == rId && lSec == rSec && lTitle == rTitle && lValue == rValue && lEnabled == rEnabled && lIndex == rIndex }
            return false
        case let .disclosure(lId, lSec, lTitle, lLabel, lIndex):
            if case let .disclosure(rId, rSec, rTitle, rLabel, rIndex) = rhs { return lId == rId && lSec == rSec && lTitle == rTitle && lLabel == rLabel && lIndex == rIndex }
            return false
        case let .slider(lId, lSec, lMin, lMax, lValue, lIndex):
            if case let .slider(rId, rSec, rMin, rMax, rValue, rIndex) = rhs { return lId == rId && lSec == rSec && lMin == rMin && lMax == rMax && lValue == rValue && lIndex == rIndex }
            return false
        case let .footer(lId, lSec, lText):
            if case let .footer(rId, rSec, rText) = rhs { return lId == rId && lSec == rSec && lText == rText }
            return false
        }
    }

    static func <(lhs: NagramSettingsEntry, rhs: NagramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSettingsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, title, value, enabled, index):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: section, style: .blocks, updated: { value in
                arguments.toggle(index, value)
            })
        case let .disclosure(_, section, title, label, index):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.disclosureAction(index)
            })
        case let .slider(_, section, minValue, maxValue, value, index):
            return NagramSliderItem(theme: presentationData.theme, minValue: minValue, maxValue: maxValue, value: value, sectionId: section, updated: { newValue in
                arguments.sliderUpdated(index, newValue)
            })
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

public func nagramSettingsController(context: AccountContext) -> ViewController {
    var currentShowCallsTab = CallListSettings.defaultSettings.showTab
    var pushControllerImpl: ((ViewController) -> Void)?
    let groups = nagramGroups(hideCalls: {
        return !currentShowCallsTab
    }, setHideCalls: { hidden in
        currentShowCallsTab = !hidden
        let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedShowTab(!hidden)
        }).startStandalone()
    }, messageMenuAction: {
        pushControllerImpl?(nagramMessageMenuSettingsController(context: context))
    })
    let flatRows: [NagramRow] = groups.flatMap { $0.rows }

    let tabPromise = ValuePromise<Int32>(0, ignoreRepeated: true)

    // 本地刷新计数:toggle/choice 改值后 bump() 触发重建。slider 不 bump(节点自显示)。
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let arguments = NagramSettingsArguments(toggle: { index, value in
        switch flatRows[index] {
        case let .toggle(_, _, set), let .toggleWithEnabled(_, _, set, _):
            set(value)
            bump()
        default:
            break
        }
    }, disclosureAction: { index in
        let row = flatRows[index]
        if case let .choice(titleKey, prefix, options, _, set) = row {
            // 参照 InstalledStickerPacksController.openSuggestOptions:disclosure 点击弹 ActionSheet 选档。
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let actionSheet = ActionSheetController(presentationData: presentationData)
            let dismissAction: () -> Void = { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            }
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: ngI18n(titleKey, lang))]
            for option in options {
                items.append(ActionSheetButtonItem(title: ngI18n("\(prefix).\(option)", lang), color: .accent, action: {
                    dismissAction()
                    set(option)
                    bump()
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
            ])
            presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        } else if case let .navigation(_, action) = row {
            action()
        }
    }, sliderUpdated: { index, value in
        // 只写值,不 bump:滑杆节点拖动时自更新中央「X%」,无需重建列表 → 避开重入崩溃。
        if case let .slider(_, _, _, set) = flatRows[index] {
            set(value)
        }
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        tabPromise.get(),
        updatePromise.get(),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> Bool in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self)?.showTab ?? CallListSettings.defaultSettings.showTab
        }
    )
    |> deliverOnMainQueue
    |> map { presentationData, selectedTab, _, showCallsTab -> (ItemListControllerState, (ItemListNodeState, Any)) in
        currentShowCallsTab = showCallsTab
        let lang = presentationData.strings.baseLanguageCode

        // stableId 必须全局唯一且稳定:遍历所有 group 全局递增分配,当前 tab 只取子集。
        // 否则切 tab 时同 stableId 指向不同类型 entry,ItemList diff 会用错 item 类型 update node 而崩溃。
        var entries: [NagramSettingsEntry] = []
        var stableId: Int32 = 0
        var globalRowIndex = 0
        for (groupIndex, group) in groups.enumerated() {
            let isCurrent = group.tab.rawValue == selectedTab
            let sectionId = Int32(groupIndex)

            let headerStableId = stableId
            stableId += 1
            if isCurrent, let headerKey = group.headerKey {
                entries.append(.header(stableId: headerStableId, section: sectionId, text: ngI18n(headerKey, lang)))
            }

            for row in group.rows {
                let rowStableId = stableId
                stableId += 1
                let rowIndex = globalRowIndex
                globalRowIndex += 1
                if isCurrent {
                    switch row {
                    case let .toggle(titleKey, get, _):
                        entries.append(.toggle(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), value: get(), enabled: true, index: rowIndex))
                    case let .toggleWithEnabled(titleKey, get, _, enabled):
                        entries.append(.toggle(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), value: get(), enabled: enabled(), index: rowIndex))
                    case let .choice(titleKey, prefix, _, current, _):
                        entries.append(.disclosure(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), label: ngI18n("\(prefix).\(current())", lang), index: rowIndex))
                    case let .slider(minValue, maxValue, get, _):
                        entries.append(.slider(stableId: rowStableId, section: sectionId, minValue: minValue, maxValue: maxValue, value: get(), index: rowIndex))
                    case let .navigation(titleKey, _):
                        entries.append(.disclosure(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), label: "", index: rowIndex))
                    }
                }
            }

            let footerStableId = stableId
            stableId += 1
            if isCurrent, let footerKey = group.footerKey {
                entries.append(.footer(stableId: footerStableId, section: sectionId, text: ngI18n(footerKey, lang)))
            }
        }

        let tabTitles = NagramTab.allCases.map { ngI18n($0.titleKey, lang) }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .sectionControl(tabTitles, Int(selectedTab)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    controller.titleControlValueChanged = { index in
        tabPromise.set(Int32(index))
    }
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c, animated: true)
    }
    return controller
}
