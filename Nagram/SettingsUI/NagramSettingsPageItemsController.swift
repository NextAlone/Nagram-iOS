import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData

private final class NagramSettingsPageItemsArguments {
    let update: (NagramSettingsPageItem, Bool) -> Void
    let reset: () -> Void

    init(update: @escaping (NagramSettingsPageItem, Bool) -> Void, reset: @escaping () -> Void) {
        self.update = update
        self.reset = reset
    }
}

private enum NagramSettingsPageItemsEntryStableId: Hashable {
    case item(NagramSettingsPageItem)
    case reset
    case footer
}

private enum NagramSettingsPageItemsEntry: ItemListNodeEntry {
    case item(NagramSettingsPageItem, Int32, String, Bool)
    case reset(Int32, String)
    case footer(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .item(_, section, _, _):
            return section
        case let .reset(section, _):
            return section
        case let .footer(section, _):
            return section
        }
    }

    var stableId: NagramSettingsPageItemsEntryStableId {
        switch self {
        case let .item(item, _, _, _):
            return .item(item)
        case .reset:
            return .reset
        case .footer:
            return .footer
        }
    }

    static func ==(lhs: NagramSettingsPageItemsEntry, rhs: NagramSettingsPageItemsEntry) -> Bool {
        switch lhs {
        case let .item(lhsItem, lhsSection, lhsTitle, lhsValue):
            if case let .item(rhsItem, rhsSection, rhsTitle, rhsValue) = rhs {
                return lhsItem == rhsItem && lhsSection == rhsSection && lhsTitle == rhsTitle && lhsValue == rhsValue
            }
            return false
        case let .reset(lhsSection, lhsTitle):
            if case let .reset(rhsSection, rhsTitle) = rhs {
                return lhsSection == rhsSection && lhsTitle == rhsTitle
            }
            return false
        case let .footer(lhsSection, lhsText):
            if case let .footer(rhsSection, rhsText) = rhs {
                return lhsSection == rhsSection && lhsText == rhsText
            }
            return false
        }
    }

    static func <(lhs: NagramSettingsPageItemsEntry, rhs: NagramSettingsPageItemsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case let .item(item, _, _, _):
            return NagramSettingsPageItem.allCases.firstIndex(of: item) ?? 0
        case .reset:
            return NagramSettingsPageItem.allCases.count
        case .footer:
            return NagramSettingsPageItem.allCases.count + 1
        }
    }

    var tag: ItemListItemTag? {
        if case let .item(item, _, _, _) = self {
            return NagramSettingsFocusTag(item.rawValue)
        }
        return nil
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSettingsPageItemsArguments
        switch self {
        case let .item(item, section, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                arguments.update(item, value)
            }, tag: self.tag)
        case let .reset(section, title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: {
                arguments.reset()
            })
        case let .footer(section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

/// Groups the switches the way the Settings screen groups its rows.
private func nagramSettingsPageItemSection(_ item: NagramSettingsPageItem) -> Int32 {
    switch item {
    case .emojiStatus, .profileColor, .setAvatar, .setUsername:
        return 0
    case .suggestions:
        return 1
    case .accounts, .addAccount:
        return 2
    case .myProfile, .wallet, .proxy, .miniApps:
        return 3
    case .savedMessages, .recentCalls, .contacts, .devices, .chatFolders:
        return 4
    case .notifications, .privacy, .dataAndStorage, .appearance, .powerSaving, .language:
        return 5
    case .premium, .stars, .ton, .business, .sendGift:
        return 6
    case .passport, .appleWatch:
        return 7
    case .support, .faq, .tips:
        return 8
    }
}

private func nagramSettingsPageItemTitle(_ item: NagramSettingsPageItem, strings: PresentationStrings) -> String {
    let lang = strings.baseLanguageCode
    switch item {
    case .emojiStatus:
        return strings.PeerInfo_SetEmojiStatus
    case .profileColor:
        return strings.PeerInfo_ChangeProfileColor
    case .setAvatar:
        return strings.Settings_SetProfilePhotoOrVideo
    case .setUsername:
        return strings.Settings_SetUsername
    case .suggestions, .accounts, .miniApps:
        return ngI18n("Nagram.SettingsPageItems.Item.\(item.rawValue)", lang)
    case .addAccount:
        return strings.Settings_AddAccount
    case .myProfile:
        return strings.Settings_MyProfile
    case .wallet:
        return strings.Settings_Money
    case .proxy:
        return strings.Settings_Proxy
    case .savedMessages:
        return strings.Settings_SavedMessages
    case .recentCalls:
        return strings.CallSettings_RecentCalls
    case .contacts:
        return strings.Contacts_Title
    case .devices:
        return strings.Settings_Devices
    case .chatFolders:
        return strings.Settings_ChatFolders
    case .notifications:
        return strings.Settings_NotificationsAndSounds
    case .privacy:
        return strings.Settings_PrivacySettings
    case .dataAndStorage:
        return strings.Settings_ChatSettings
    case .appearance:
        return strings.Settings_Appearance
    case .powerSaving:
        return strings.Settings_PowerSaving
    case .language:
        return strings.Settings_AppLanguage
    case .premium:
        return strings.Settings_Premium
    case .stars:
        return strings.Settings_Stars
    case .ton:
        return strings.Settings_MyTon
    case .business:
        return strings.Settings_Business
    case .sendGift:
        return strings.Settings_SendGift
    case .passport:
        return strings.Settings_Passport
    case .appleWatch:
        return strings.Settings_AppleWatch
    case .support:
        return strings.Settings_Support
    case .faq:
        return strings.Settings_FAQ
    case .tips:
        return strings.Settings_Tips
    }
}

public func nagramSettingsPageItemsController(context: AccountContext, focusOnRow: String? = nil) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    let arguments = NagramSettingsPageItemsArguments(update: { item, visible in
        NagramSettings.shared.setSettingsPageItemHidden(item, hidden: !visible)
        bump()
    }, reset: {
        NagramSettings.shared.hiddenSettingsPageItemsValue = ""
        bump()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let hiddenItems = NagramSettings.shared.hiddenSettingsPageItems
        var entries = NagramSettingsPageItem.allCases.map { item in
            NagramSettingsPageItemsEntry.item(
                item,
                nagramSettingsPageItemSection(item),
                nagramSettingsPageItemTitle(item, strings: presentationData.strings),
                !hiddenItems.contains(item)
            )
        }
        let resetSection = nagramSettingsPageItemSection(.tips) + 1
        entries.append(.reset(resetSection, ngI18n("Nagram.SettingsPageItems.Reset", lang)))
        entries.append(.footer(resetSection, ngI18n("Nagram.SettingsPageItems.Footer", lang)))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.SettingsPageItems", lang)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            initialScrollToItem: nagramFocusScrollToItem(entries: entries, focusOnRow: focusOnRow),
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    nagramHighlightFocusedRow(controller: controller, focusOnRow: focusOnRow)
    return controller
}
