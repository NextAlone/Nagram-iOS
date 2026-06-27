import AccountContext
import Display
import FaceScanScreen
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit
import UndoUI

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

    var deepLinkSection: String {
        switch self {
        case .general: return "general"
        case .chat: return "chat"
        case .other: return "other"
        }
    }
}

private final class NagramSettingsRowTag: ItemListItemTag {
    let index: Int

    init(index: Int) {
        self.index = index
    }

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? NagramSettingsRowTag {
            return self.index == other.index
        }
        return false
    }
}

// 行类型:开关 / 单选(disclosure + ActionSheet) / 行内滑杆。
private enum NagramRow {
    case toggle(titleKey: String, get: () -> Bool, set: (Bool) -> Void)
    case toggleWithEnabled(titleKey: String, get: () -> Bool, set: (Bool) -> Void, enabled: () -> Bool, enableInteractiveChanges: Bool)
    case choice(titleKey: String, prefix: String, options: [String], current: () -> String, set: (String) -> Void)
    case startupFolder(titleKey: String)
    case slider(minValue: Int32, maxValue: Int32, get: () -> Int32, set: (Int32) -> Void)
    case navigation(titleKey: String, action: () -> Void)
}

private struct NagramDeepLinkRequest {
    let section: String?
    let row: String?
}

private struct NagramDeepLinkTarget {
    let tab: NagramTab
    let rowIndex: Int?
}

private func normalizedNagramDeepLinkToken(_ value: String) -> String {
    return String(value.lowercased().filter { $0.isLetter || $0.isNumber })
}

private func nagramRowTitleKey(_ row: NagramRow) -> String {
    switch row {
    case let .toggle(titleKey, _, _):
        return titleKey
    case let .toggleWithEnabled(titleKey, _, _, _, _):
        return titleKey
    case let .choice(titleKey, _, _, _, _):
        return titleKey
    case let .startupFolder(titleKey):
        return titleKey
    case .slider:
        return "Nagram.StickerSize"
    case let .navigation(titleKey, _):
        return titleKey
    }
}

private func nagramRowDeepLinkAliases(titleKey: String) -> [String] {
    switch titleKey {
    case "Nagram.HideTabBar":
        return ["MainTabsStyle", "TabStyle"]
    case "Nagram.BottomBarLayout":
        return ["MainTabsStyle", "TabStyle", "HideTabBar", "HideCallsTab", "HideCallTab", "HideContactsTab", "HideContactTab", "HideChatsTab", "HideChatListTab", "HideSettingsTab", "ShowSearchTab", "SearchTab", "WideTabBar"]
    case "Nagram.HideTabBarCalls":
        return ["HideCallsTab", "HideCallTab"]
    case "Nagram.HideTabBarContacts":
        return ["HideContactsTab", "HideContactTab"]
    case "Nagram.HideTabBarChatList":
        return ["HideChatsTab", "HideChatListTab"]
    case "Nagram.HideTabBarSettings":
        return ["HideSettingsTab"]
    case "Nagram.ShowTabBarSearch":
        return ["ShowSearchTab", "SearchTab"]
    case "Nagram.HideStories":
        return ["DisableStories"]
    case "Nagram.DisableGalleryCamera":
        return ["DisableInAppCamera", "inappCamera"]
    case "Nagram.DisableGalleryCameraPreview":
        return ["DisableCameraPreview"]
    case "Nagram.DownloadSpeedBoost":
        return ["enhancedFileLoader", "downloadSpeedBoost"]
    case "Nagram.UploadSpeedBoost":
        return ["uploadSpeedBoost"]
    case "Nagram.SecondsInMessages":
        return ["showSeconds", "ShowSeconds"]
    case "Nagram.HideReactions":
        return ["disableReactionsWhenSelecting", "HideReactions"]
    case "Nagram.HideChannelBottomButton":
        return ["HideChannelBottomButton"]
    case "Nagram.HideSponsoredMessages":
        return ["HideSponsoredMessages", "DisableSponsoredMessages"]
    case "Nagram.ChatListMessagePreviewStyle":
        return ["ChatListLines", "CompactMessagePreview", "MessagePreviewStyle"]
    case "Nagram.ChatListCompact":
        return ["CompactChatList", "CompactChatListLayout"]
    case "Nagram.PanguOnReceiving":
        return ["PanguOnReceiving", "PanguOnRecv", "PanguReceiving"]
    case "Nagram.PanguOnSending":
        return ["PanguOnSending", "PanguSending"]
    case "Nagram.PanguOnEditing":
        return ["PanguOnEditing", "PanguEditing"]
    case "Nagram.MessageMenu":
        return ["MessageMenu", "DisableActionBarButton"]
    case "Nagram.RegexFilters":
        return ["RegexFilters", "Filters", "MessageFilters"]
    case "Nagram.StickerSize":
        return ["stickerSize"]
    case "Nagram.StickerTimestamp":
        return ["StickerTimestamp", "StickerTime"]
    case "Nagram.DisableSendAsButton":
        return ["hideSendAsChannel", "DisableSendAsButton"]
    case "Nagram.SendWithReturnKey":
        return ["SendWithReturnKey", "ReturnKeySend"]
    case "Nagram.HideRecordingButton":
        return ["HideRecordingButton", "HideRecordButton"]
    case "Nagram.RecentChats":
        return ["RecentChats", "recent_dialogs", "ShowRecentChatsInSidebar"]
    case "Nagram.ChatListSwipeAction":
        return ["ChatListSwipeAction"]
    case "Nagram.ChatListStartupFolder":
        return ["DefaultFolder", "StartupFolder", "RememberLastFolder"]
    case "Nagram.DisableScrollToNextChannel":
        return ["DisableScrollToNextChannel"]
    case "Nagram.DisableScrollToNextTopic":
        return ["DisableScrollToNextTopic"]
    case "Nagram.VideoPIPSwipeUp":
        return ["VideoPIPSwipeUp", "VideoPIPSwipeDirection"]
    case "Nagram.ShowProfileId":
        return ["ShowProfileId", "ShowId", "ShowIdAndDc"]
    case "Nagram.ShowDC":
        return ["ShowDC", "ShowDataCenter", "ShowIdAndDc"]
    case "Nagram.ControlHighlight":
        return ["ControlHighlight", "GlassHighlight", "LiquidGlassHighlight"]
    case "Nagram.ShowRegDate":
        return ["ShowRegDate", "RegistrationDate"]
    case "Nagram.HidePhoneInSettings":
        return ["HidePhone", "hidePhoneInSettings"]
    case "Nagram.ConfirmCalls":
        return ["AskBeforeCalling", "ConfirmCalls"]
    case "Nagram.DisableFiltering":
        return ["DisableFiltering"]
    case "Nagram.ForceCopy":
        return ["ForceCopy", "ForceCopyEnabled"]
    default:
        return []
    }
}

private func nagramChatListStartupFolderLabel(accountPeerId: Int64, strings: PresentationStrings, lang: String) -> String {
    switch NagramSettings.shared.chatListStartupFolderModeValue {
    case .telegramDefault:
        return ngI18n("Nagram.ChatListStartupFolder.telegram", lang)
    case .last:
        return ngI18n("Nagram.ChatListStartupFolder.last", lang)
    case .specific:
        guard let folderId = NagramSettings.shared.chatListStartupSpecificFolderId(accountPeerId: accountPeerId) else {
            return ngI18n("Nagram.ChatListStartupFolder.notSet", lang)
        }
        if folderId == NagramSettings.chatListAllChatsFolderId {
            return strings.ChatList_Tabs_AllChats
        }
        return "\(ngI18n("Nagram.ChatListStartupFolder.specific", lang)) #\(folderId)"
    }
}

private func nagramRowDeepLinkTokens(_ row: NagramRow) -> [String] {
    let titleKey = nagramRowTitleKey(row)
    var values = [titleKey]
    if titleKey.hasPrefix("Nagram.") {
        values.append(String(titleKey.dropFirst("Nagram.".count)))
    }
    values.append(contentsOf: nagramRowDeepLinkAliases(titleKey: titleKey))
    return values.map(normalizedNagramDeepLinkToken)
}

private func nagramRowDeepLinkKey(_ row: NagramRow) -> String {
    let titleKey = nagramRowTitleKey(row)
    if titleKey.hasPrefix("Nagram.") {
        return String(titleKey.dropFirst("Nagram.".count))
    }
    return titleKey
}

private func nagramSettingsDeepLink(tab: NagramTab, row: NagramRow) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "t.me"
    components.path = "/nasettings/\(tab.deepLinkSection)"
    components.queryItems = [
        URLQueryItem(name: "r", value: nagramRowDeepLinkKey(row))
    ]
    return components.url?.absoluteString ?? "https://t.me/nasettings/\(tab.deepLinkSection)?r=\(nagramRowDeepLinkKey(row))"
}

private func nagramTabForDeepLinkSection(_ section: String?) -> NagramTab? {
    guard let section else {
        return nil
    }
    switch normalizedNagramDeepLinkToken(section) {
    case "general", "g", "interface", "camera", "network":
        return .general
    case "chat", "chats", "c", "message", "messages", "stickers", "gesture":
        return .chat
    case "other", "o", "account", "a", "about", "privacy", "profile", "calls", "experimental", "e", "emoji":
        return .other
    default:
        return nil
    }
}

private func parseNagramDeepLinkRequest(_ deepLinkPath: String?) -> NagramDeepLinkRequest? {
    guard var raw = deepLinkPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return nil
    }
    if raw.lowercased().hasPrefix("nagram") {
        raw = String(raw.dropFirst("nagram".count))
        if raw.hasPrefix("/") {
            raw = String(raw.dropFirst())
        }
    }

    let urlString: String
    if raw.isEmpty {
        urlString = "nagram://settings"
    } else if raw.hasPrefix("?") {
        urlString = "nagram://settings\(raw)"
    } else {
        urlString = "nagram://settings/\(raw)"
    }

    guard let components = URLComponents(string: urlString) else {
        return nil
    }

    let pathComponents = components.path.split(separator: "/").map(String.init)
    let section = pathComponents.first
    var row: String?
    for item in components.queryItems ?? [] {
        switch item.name.lowercased() {
        case "r", "row":
            if let value = item.value, !value.isEmpty {
                row = value
            }
        default:
            break
        }
    }
    return NagramDeepLinkRequest(section: section, row: row)
}

private func nagramDeepLinkTarget(deepLinkPath: String?, groups: [NagramGroup]) -> NagramDeepLinkTarget {
    let request = parseNagramDeepLinkRequest(deepLinkPath)
    var selectedTab = nagramTabForDeepLinkSection(request?.section) ?? .general
    var rowIndex: Int?

    let rowCandidates = [request?.row, request?.section].compactMap { value -> String? in
        guard let value, nagramTabForDeepLinkSection(value) == nil else {
            return nil
        }
        return normalizedNagramDeepLinkToken(value)
    }

    if !rowCandidates.isEmpty {
        var globalRowIndex = 0
        scan: for group in groups {
            for row in group.rows {
                let tokens = nagramRowDeepLinkTokens(row)
                if rowCandidates.contains(where: { tokens.contains($0) }) {
                    selectedTab = group.tab
                    rowIndex = globalRowIndex
                    break scan
                }
                globalRowIndex += 1
            }
        }
    }

    return NagramDeepLinkTarget(tab: selectedTab, rowIndex: rowIndex)
}

private struct NagramGroup {
    let tab: NagramTab
    let headerKey: String?
    let footerKey: String?
    let rows: [NagramRow]
}

private func nagramGroups(
    hideCalls: @escaping () -> Bool,
    setHideCalls: @escaping (Bool) -> Void,
    sensitiveContentConfiguration: @escaping () -> ContentSettingsConfiguration?,
    setSensitiveContentEnabled: @escaping (Bool) -> Void,
    bottomBarLayoutAction: @escaping () -> Void,
    messageMenuAction: @escaping () -> Void,
    regexFiltersAction: @escaping () -> Void
) -> [NagramGroup] {
    let sensitiveContentEnabled: () -> Bool = {
        return sensitiveContentConfiguration()?.sensitiveContentEnabled ?? false
    }
    let sensitiveContentCanAdjust: () -> Bool = {
        return sensitiveContentConfiguration()?.canAdjustSensitiveContent ?? false
    }
    if NagramSettings.shared.chatListCompact && NagramSettings.shared.chatListMessagePreviewStyle != NagramChatListMessagePreviewStyle.two.rawValue {
        NagramSettings.shared.chatListMessagePreviewStyle = NagramChatListMessagePreviewStyle.two.rawValue
    }
    return [
        // 通用
        NagramGroup(tab: .general, headerKey: "Nagram.Section.Interface", footerKey: nil, rows: [
            .navigation(titleKey: "Nagram.BottomBarLayout", action: bottomBarLayoutAction),
            .startupFolder(titleKey: "Nagram.ChatListStartupFolder"),
            .choice(titleKey: "Nagram.ChatListMessagePreviewStyle", prefix: "Nagram.ChatListMessagePreviewStyle", options: ["three", "two"], current: { NagramSettings.shared.chatListMessagePreviewStyleMode.rawValue }, set: { value in
                if NagramSettings.shared.chatListCompact && value == NagramChatListMessagePreviewStyle.three.rawValue {
                    return
                }
                NagramSettings.shared.chatListMessagePreviewStyle = value
            }),
            .toggle(titleKey: "Nagram.ChatListCompact", get: { NagramSettings.shared.chatListCompact }, set: { value in
                NagramSettings.shared.chatListCompact = value
                if value {
                    NagramSettings.shared.chatListMessagePreviewStyle = NagramChatListMessagePreviewStyle.two.rawValue
                }
            }),
            .toggle(titleKey: "Nagram.ControlHighlight", get: { NagramSettings.shared.controlHighlightEnabled }, set: { NagramSettings.shared.controlHighlightEnabled = $0 }),
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
            .toggle(titleKey: "Nagram.HideSponsoredMessages", get: { NagramSettings.shared.hideSponsoredMessages }, set: { NagramSettings.shared.hideSponsoredMessages = $0 }),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.Pangu", footerKey: "Nagram.PanguInfo", rows: [
            .toggle(titleKey: "Nagram.PanguOnReceiving", get: { NagramSettings.shared.enablePanguOnReceiving }, set: { NagramSettings.shared.enablePanguOnReceiving = $0 }),
            .toggle(titleKey: "Nagram.PanguOnSending", get: { NagramSettings.shared.enablePanguOnSending }, set: { NagramSettings.shared.enablePanguOnSending = $0 }),
            .toggle(titleKey: "Nagram.PanguOnEditing", get: { NagramSettings.shared.enablePanguOnEditing }, set: { NagramSettings.shared.enablePanguOnEditing = $0 }),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.MessageMenu", footerKey: nil, rows: [
            .navigation(titleKey: "Nagram.MessageMenu", action: messageMenuAction),
        ]),
        NagramGroup(tab: .chat, headerKey: "Nagram.Section.Filtering", footerKey: "Nagram.RegexFilters.Main.Footer", rows: [
            .navigation(titleKey: "Nagram.RegexFilters", action: regexFiltersAction),
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
            .toggle(titleKey: "Nagram.RecentChats", get: { NagramSettings.shared.recentChatsEnabled }, set: { NagramSettings.shared.recentChatsEnabled = $0 }),
            .toggle(titleKey: "Nagram.TapMessageRowToOpenContextMenu", get: { NagramSettings.shared.tapMessageRowToOpenContextMenu }, set: { NagramSettings.shared.tapMessageRowToOpenContextMenu = $0 }),
            .choice(titleKey: "Nagram.MessageDoubleTapAction", prefix: "Nagram.MessageDoubleTapAction", options: NagramMessageDoubleTapAction.allCases.map { $0.rawValue }, current: { NagramSettings.shared.messageDoubleTapActionValue.rawValue }, set: { NagramSettings.shared.messageDoubleTapAction = $0 }),
            .choice(titleKey: "Nagram.ChatListSwipeAction", prefix: "Nagram.ChatListSwipeAction", options: ["both", "switch", "quick", "none"], current: { NagramSettings.shared.chatListSwipeActionMode.rawValue }, set: { NagramSettings.shared.chatListSwipeAction = $0 }),
            .toggle(titleKey: "Nagram.DisableScrollToNextChannel", get: { NagramSettings.shared.disableScrollToNextChannel }, set: { NagramSettings.shared.disableScrollToNextChannel = $0 }),
            .toggle(titleKey: "Nagram.DisableScrollToNextTopic", get: { NagramSettings.shared.disableScrollToNextTopic }, set: { NagramSettings.shared.disableScrollToNextTopic = $0 }),
            .toggle(titleKey: "Nagram.VideoPIPSwipeUp", get: { NagramSettings.shared.videoPIPSwipeDirection == "up" }, set: { NagramSettings.shared.videoPIPSwipeDirection = $0 ? "up" : "none" }),
        ]),
        // 其他
        NagramGroup(tab: .other, headerKey: "Nagram.Section.Profile", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.ShowProfileId", get: { NagramSettings.shared.showProfileId }, set: { NagramSettings.shared.showProfileId = $0 }),
            .toggle(titleKey: "Nagram.ShowDC", get: { NagramSettings.shared.showDC }, set: { NagramSettings.shared.showDC = $0 }),
            .toggle(titleKey: "Nagram.ShowRegDate", get: { NagramSettings.shared.showRegDate }, set: { NagramSettings.shared.showRegDate = $0 }),
            .toggle(titleKey: "Nagram.HidePhoneInSettings", get: { NagramSettings.shared.hidePhoneInSettings }, set: { NagramSettings.shared.hidePhoneInSettings = $0 }),
        ]),
        NagramGroup(tab: .other, headerKey: "Nagram.Section.Calls", footerKey: nil, rows: [
            .toggle(titleKey: "Nagram.ConfirmCalls", get: { NagramSettings.shared.confirmCalls }, set: { NagramSettings.shared.confirmCalls = $0 }),
        ]),
        NagramGroup(tab: .other, headerKey: "Nagram.Section.Privacy", footerKey: "Nagram.DisableFiltering.Footer", rows: [
            .toggleWithEnabled(titleKey: "Nagram.DisableFiltering", get: sensitiveContentEnabled, set: setSensitiveContentEnabled, enabled: sensitiveContentCanAdjust, enableInteractiveChanges: false),
        ]),
        NagramGroup(tab: .other, headerKey: nil, footerKey: "Nagram.ForceCopy.Footer", rows: [
            .toggle(titleKey: "Nagram.ForceCopy", get: { NagramSettings.shared.forceCopyEnabled }, set: { NagramSettings.shared.forceCopyEnabled = $0 }),
        ]),
    ]
}

private final class NagramSettingsArguments {
    let toggle: (Int, Bool) -> Void
    let disclosureAction: (Int) -> Void
    let sliderUpdated: (Int, Int32) -> Void
    let copyDeepLink: (Int) -> Void

    init(toggle: @escaping (Int, Bool) -> Void, disclosureAction: @escaping (Int) -> Void, sliderUpdated: @escaping (Int, Int32) -> Void, copyDeepLink: @escaping (Int) -> Void) {
        self.toggle = toggle
        self.disclosureAction = disclosureAction
        self.sliderUpdated = sliderUpdated
        self.copyDeepLink = copyDeepLink
    }
}

private enum NagramSettingsEntry: ItemListNodeEntry {
    case header(stableId: Int32, section: Int32, text: String)
    case toggle(stableId: Int32, section: Int32, title: String, value: Bool, enabled: Bool, enableInteractiveChanges: Bool, index: Int)
    case disclosure(stableId: Int32, section: Int32, title: String, label: String, index: Int)
    case slider(stableId: Int32, section: Int32, minValue: Int32, maxValue: Int32, value: Int32, index: Int)
    case footer(stableId: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _): return section
        case let .toggle(_, section, _, _, _, _, _): return section
        case let .disclosure(_, section, _, _, _): return section
        case let .slider(_, section, _, _, _, _): return section
        case let .footer(_, section, _): return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(stableId, _, _): return stableId
        case let .toggle(stableId, _, _, _, _, _, _): return stableId
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
        case let .toggle(lId, lSec, lTitle, lValue, lEnabled, lEnableInteractiveChanges, lIndex):
            if case let .toggle(rId, rSec, rTitle, rValue, rEnabled, rEnableInteractiveChanges, rIndex) = rhs { return lId == rId && lSec == rSec && lTitle == rTitle && lValue == rValue && lEnabled == rEnabled && lEnableInteractiveChanges == rEnableInteractiveChanges && lIndex == rIndex }
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

    var tag: ItemListItemTag? {
        switch self {
        case let .toggle(_, _, _, _, _, _, index):
            return NagramSettingsRowTag(index: index)
        case let .disclosure(_, _, _, _, index):
            return NagramSettingsRowTag(index: index)
        case let .slider(_, _, _, _, _, index):
            return NagramSettingsRowTag(index: index)
        default:
            return nil
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSettingsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, title, value, enabled, enableInteractiveChanges, index):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enableInteractiveChanges: enableInteractiveChanges, enabled: enabled, sectionId: section, style: .blocks, updated: { value in
                arguments.toggle(index, value)
            }, longTapAction: {
                arguments.copyDeepLink(index)
            }, tag: self.tag)
        case let .disclosure(_, section, title, label, index):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.disclosureAction(index)
            }, longTapAction: {
                arguments.copyDeepLink(index)
            }, tag: self.tag)
        case let .slider(_, section, minValue, maxValue, value, index):
            return NagramSliderItem(theme: presentationData.theme, minValue: minValue, maxValue: maxValue, value: value, sectionId: section, updated: { newValue in
                arguments.sliderUpdated(index, newValue)
            }, longTapAction: {
                arguments.copyDeepLink(index)
            }, tag: self.tag)
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

public func nagramSettingsController(context: AccountContext, deepLinkPath: String? = nil) -> ViewController {
    var currentShowCallsTab = CallListSettings.defaultSettings.showTab
    var currentContentSettingsConfiguration: ContentSettingsConfiguration?
    let contentSettingsConfigurationPromise = Promise<ContentSettingsConfiguration?>()
    contentSettingsConfigurationPromise.set(.single(nil)
    |> then(contentSettingsConfiguration(network: context.account.network)
    |> map(Optional.init)))

    let updateSensitiveContentDisposable = MetaDisposable()
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var presentAgeVerificationImpl: ((@escaping () -> Void) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    let groups = nagramGroups(hideCalls: {
        return !currentShowCallsTab
    }, setHideCalls: { hidden in
        currentShowCallsTab = !hidden
        var bottomBarSettings = NagramSettings.shared.bottomBarSettings
        bottomBarSettings.setVisible(.calls, visible: !hidden)
        if bottomBarSettings.searchMode == .bar && !bottomBarSettings.visibleBottomItems.isEmpty {
            bottomBarSettings.setSearchMode(.button)
        }
        NagramSettings.shared.bottomBarSettings = bottomBarSettings
        let _ = updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedShowTab(!hidden)
        }).startStandalone()
    }, sensitiveContentConfiguration: {
        return currentContentSettingsConfiguration
    }, setSensitiveContentEnabled: { value in
        let update = {
            if var settings = currentContentSettingsConfiguration {
                settings.sensitiveContentEnabled = value
                currentContentSettingsConfiguration = settings
                contentSettingsConfigurationPromise.set(.single(settings))
            }
            updateSensitiveContentDisposable.set(updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: value).start())
        }
        if value {
            if requireAgeVerification(context: context) {
                presentAgeVerificationImpl?(update)
            } else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let alertController = textAlertController(context: context, title: presentationData.strings.SensitiveContent_Enable_Title, text: presentationData.strings.SensitiveContent_Enable_Text, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .defaultAction, title: presentationData.strings.SensitiveContent_Enable_Confirm, action: {
                        update()
                    })
                ])
                presentControllerImpl?(alertController, nil)
            }
        } else {
            update()
        }
    }, bottomBarLayoutAction: {
        pushControllerImpl?(nagramBottomBarSettingsController(context: context))
    }, messageMenuAction: {
        pushControllerImpl?(nagramMessageMenuSettingsController(context: context))
    }, regexFiltersAction: {
        pushControllerImpl?(nagramRegexFilterSettingsController(context: context))
    })
    let flatRows: [NagramRow] = groups.flatMap { $0.rows }
    let flatRowDeepLinks: [String] = groups.flatMap { group in
        group.rows.map { nagramSettingsDeepLink(tab: group.tab, row: $0) }
    }
    let deepLinkTarget = nagramDeepLinkTarget(deepLinkPath: deepLinkPath, groups: groups)
    let autoOpenNavigationAction: (() -> Void)? = deepLinkTarget.rowIndex.flatMap { rowIndex -> (() -> Void)? in
        guard flatRows.indices.contains(rowIndex), case let .navigation(_, action) = flatRows[rowIndex] else {
            return nil
        }
        return action
    }

    let tabPromise = ValuePromise<Int32>(deepLinkTarget.tab.rawValue, ignoreRepeated: true)

    // 本地刷新计数:toggle/choice 改值后 bump() 触发重建。slider 不 bump(节点自显示)。
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    let arguments = NagramSettingsArguments(toggle: { index, value in
        switch flatRows[index] {
        case let .toggle(_, _, set), let .toggleWithEnabled(_, _, set, _, _):
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
            let effectiveOptions = titleKey == "Nagram.ChatListMessagePreviewStyle" && NagramSettings.shared.chatListCompact ? ["two"] : options
            for option in effectiveOptions {
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
        } else if case let .startupFolder(titleKey) = row {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let accountPeerId = context.account.peerId.toInt64()
            let _ = (context.engine.peers.updatedChatListFilters()
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { filters in
                let actionSheet = ActionSheetController(presentationData: presentationData)
                let dismissAction: () -> Void = { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                }
                let setMode: (NagramChatListStartupFolderMode, Int32?) -> Void = { mode, folderId in
                    NagramSettings.shared.chatListStartupFolderMode = mode.rawValue
                    if let folderId {
                        NagramSettings.shared.setChatListStartupSpecificFolderId(folderId, accountPeerId: accountPeerId)
                    }
                    bump()
                }
                var modeItems: [ActionSheetItem] = [
                    ActionSheetTextItem(title: ngI18n(titleKey, lang)),
                    ActionSheetButtonItem(title: ngI18n("Nagram.ChatListStartupFolder.telegram", lang), color: .accent, action: {
                        dismissAction()
                        setMode(.telegramDefault, nil)
                    }),
                    ActionSheetButtonItem(title: ngI18n("Nagram.ChatListStartupFolder.last", lang), color: .accent, action: {
                        dismissAction()
                        setMode(.last, nil)
                    })
                ]
                var folderItems: [ActionSheetItem] = [
                    ActionSheetButtonItem(title: presentationData.strings.ChatList_Tabs_AllChats, color: .accent, action: {
                        dismissAction()
                        setMode(.specific, NagramSettings.chatListAllChatsFolderId)
                    })
                ]
                for filter in filters {
                    if case let .filter(id, title, _, _) = filter {
                        folderItems.append(ActionSheetButtonItem(title: title.text, color: .accent, action: {
                            dismissAction()
                            setMode(.specific, id)
                        }))
                    }
                }
                modeItems.append(ActionSheetTextItem(title: ngI18n("Nagram.ChatListStartupFolder.specific", lang)))
                actionSheet.setItemGroups([
                    ActionSheetItemGroup(items: modeItems),
                    ActionSheetItemGroup(items: folderItems),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
                ])
                presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            })
        } else if case let .navigation(_, action) = row {
            action()
        }
    }, sliderUpdated: { index, value in
        // 只写值,不 bump:滑杆节点拖动时自更新中央「X%」,无需重建列表 → 避开重入崩溃。
        if case let .slider(_, _, _, set) = flatRows[index] {
            set(value)
        }
    }, copyDeepLink: { index in
        guard flatRowDeepLinks.indices.contains(index) else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        UIPasteboard.general.string = flatRowDeepLinks[index]
        HapticFeedback().tap()
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.Conversation_LinkCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in
            return false
        }), nil)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        tabPromise.get(),
        updatePromise.get(),
        contentSettingsConfigurationPromise.get(),
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
        |> map { sharedData -> Bool in
            return sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self)?.showTab ?? CallListSettings.defaultSettings.showTab
        }
    )
    |> deliverOnMainQueue
    |> map { presentationData, selectedTab, _, contentSettingsConfiguration, showCallsTab -> (ItemListControllerState, (ItemListNodeState, Any)) in
        currentShowCallsTab = showCallsTab
        currentContentSettingsConfiguration = contentSettingsConfiguration
        let lang = presentationData.strings.baseLanguageCode

        // stableId 必须全局唯一且稳定:遍历所有 group 全局递增分配,当前 tab 只取子集。
        // 否则切 tab 时同 stableId 指向不同类型 entry,ItemList diff 会用错 item 类型 update node 而崩溃。
        var entries: [NagramSettingsEntry] = []
        var initialScrollToItem: ListViewScrollToItem?
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
                    if deepLinkTarget.rowIndex == rowIndex {
                        initialScrollToItem = ListViewScrollToItem(index: entries.count, position: .visible, animated: false, curve: .Default(duration: nil), directionHint: .Down)
                    }
                    switch row {
                    case let .toggle(titleKey, get, _):
                        entries.append(.toggle(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), value: get(), enabled: true, enableInteractiveChanges: true, index: rowIndex))
                    case let .toggleWithEnabled(titleKey, get, _, enabled, enableInteractiveChanges):
                        entries.append(.toggle(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), value: get(), enabled: enabled(), enableInteractiveChanges: enableInteractiveChanges, index: rowIndex))
                    case let .choice(titleKey, prefix, _, current, _):
                        let currentValue = titleKey == "Nagram.ChatListMessagePreviewStyle" && NagramSettings.shared.chatListCompact ? NagramChatListMessagePreviewStyle.two.rawValue : current()
                        entries.append(.disclosure(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), label: ngI18n("\(prefix).\(currentValue)", lang), index: rowIndex))
                    case let .startupFolder(titleKey):
                        entries.append(.disclosure(stableId: rowStableId, section: sectionId, title: ngI18n(titleKey, lang), label: nagramChatListStartupFolderLabel(accountPeerId: context.account.peerId.toInt64(), strings: presentationData.strings, lang: lang), index: rowIndex))
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
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: deepLinkTarget.rowIndex.map { NagramSettingsRowTag(index: $0) }, initialScrollToItem: initialScrollToItem, animateChanges: false)

        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        updateSensitiveContentDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    if let autoOpenNavigationAction {
        var didAutoOpenNavigation = false
        controller.afterLayout {
            guard !didAutoOpenNavigation else {
                return
            }
            didAutoOpenNavigation = true
            Queue.mainQueue().after(0.15, {
                autoOpenNavigationAction()
            })
        }
    } else if let rowIndex = deepLinkTarget.rowIndex {
        let targetTag = NagramSettingsRowTag(index: rowIndex)
        controller.afterLayout { [weak controller] in
            guard let controller else {
                return
            }
            var didHighlight = false
            for delay in [0.35, 0.75, 1.15] {
                Queue.mainQueue().after(delay, { [weak controller] in
                    guard !didHighlight, let itemNode = controller?.itemNode(forTag: targetTag) as? ItemListItemNode else {
                        return
                    }
                    didHighlight = true
                    itemNode.displayHighlight()
                })
            }
        }
    }
    controller.titleControlValueChanged = { index in
        tabPromise.set(Int32(index))
    }
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    presentAgeVerificationImpl = { [weak controller] update in
        guard let controller else {
            return
        }
        presentAgeVerification(context: context, parentController: controller, completion: {
            update()
        })
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c, animated: true)
    }
    return controller
}
