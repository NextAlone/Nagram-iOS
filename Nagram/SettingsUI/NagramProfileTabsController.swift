import AccountContext
import Display
import ItemListUI
import NagramSettings
import NagramSettingsSignal
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData

public func nagramProfilePaneTitle(_ pane: NagramProfilePane, strings: PresentationStrings) -> String {
    switch pane {
    case .botPreview: return strings.PeerInfo_PaneBotPreviews
    case .members: return strings.PeerInfo_PaneMembers
    case .stories: return strings.PeerInfo_PaneStories
    case .gifts: return strings.PeerInfo_PaneGifts
    case .media: return strings.PeerInfo_PaneMedia
    case .savedMessagesChats: return strings.DialogList_TabTitle
    case .savedMessages: return strings.PeerInfo_SavedMessagesTabTitle
    case .files: return strings.PeerInfo_PaneFiles
    case .music: return strings.PeerInfo_PaneAudio
    case .voice: return strings.PeerInfo_PaneVoiceAndVideo
    case .links: return strings.PeerInfo_PaneLinks
    case .gifs: return strings.PeerInfo_PaneGifs
    case .polls: return strings.PeerInfo_PanePolls
    case .groupsInCommon: return strings.PeerInfo_PaneGroups
    case .similarChannels: return strings.PeerInfo_PaneRecommended
    case .similarBots: return strings.PeerInfo_PaneRecommendedBots
    case .storyArchive: return strings.PeerInfo_PaneArchivedStories
    }
}

private extension NagramProfilePaneScope {
    func title(strings: PresentationStrings) -> String {
        switch self {
        case .user: return ngI18n("Nagram.ProfileTabs.Users", strings.baseLanguageCode)
        case .bot: return strings.ChatListFolder_CategoryBots
        case .group: return strings.ChatListFolder_CategoryGroups
        case .channel: return strings.ChatListFolder_CategoryChannels
        case .myProfile: return strings.Settings_MyProfile
        case .savedMessages: return strings.DialogList_SavedMessages
        }
    }
}

private func profileTabSettingsTitle(_ pane: NagramProfilePane, strings: PresentationStrings) -> String {
    switch pane {
    case .botPreview: return ngI18n("Nagram.ProfileTabs.BotPreview", strings.baseLanguageCode)
    case .savedMessagesChats: return ngI18n("Nagram.ProfileTabs.SavedMessagesChats", strings.baseLanguageCode)
    case .savedMessages: return ngI18n("Nagram.ProfileTabs.SavedMessagesFromChat", strings.baseLanguageCode)
    default: return nagramProfilePaneTitle(pane, strings: strings)
    }
}

private enum ProfileTabEntry: ItemListNodeEntry {
    case scope(index: Int, scope: NagramProfilePaneScope, title: String)
    case pane(index: Int, scope: NagramProfilePaneScope, id: NagramProfilePane, title: String, visible: Bool)
    case footer(String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int {
        switch self {
        case let .scope(index, _, _), let .pane(index, _, _, _, _): return index
        case .footer: return .max
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .scope(_, scope, title):
            let openScope = arguments as! (NagramProfilePaneScope) -> Void
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: { openScope(scope) })
        case let .pane(_, scope, pane, title, visible):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: visible, sectionId: self.section, style: .blocks, updated: { visible in
                NagramSettings.shared.setProfilePaneHidden(!visible, for: pane, in: scope)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func nagramProfileTabsController(context: AccountContext, scope: NagramProfilePaneScope? = nil) -> ViewController {
    var openScope: ((NagramProfilePaneScope) -> Void)?
    let settings: Signal<NagramProfilePaneSettings, NoError>
    if let scope {
        settings = nagramProfilePaneSettingsSignal()
        |> map { $0[scope] ?? NagramProfilePaneSettings() }
        |> distinctUntilChanged
    } else {
        settings = .single(NagramProfilePaneSettings())
    }
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, settings)
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings
        let title: String
        var entries: [ProfileTabEntry]
        if let scope {
            title = scope.title(strings: strings)
            entries = scope.panes.enumerated().map { index, pane in
                .pane(index: index, scope: scope, id: pane, title: profileTabSettingsTitle(pane, strings: strings), visible: !settings.isHidden(pane))
            }
            let footer = NagramLocalization.shared.localizedString("Nagram.ProfileTabs.Footer", strings.baseLanguageCode, args: strings.ChatList_ReorderTabs)
            entries.append(.footer(footer))
        } else {
            title = ngI18n("Nagram.ProfileTabs", strings.baseLanguageCode)
            entries = NagramProfilePaneScope.allCases.enumerated().map { index, scope in
                .scope(index: index, scope: scope, title: scope.title(strings: strings))
            }
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back))
        let list = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        let selectScope: (NagramProfilePaneScope) -> Void = { scope in openScope?(scope) }
        return (state, (list, selectScope))
    }
    let controller = ItemListController(context: context, state: signal)
    openScope = { [weak controller] scope in
        (controller?.navigationController as? NavigationController)?.pushViewController(nagramProfileTabsController(context: context, scope: scope), animated: true)
    }
    return controller
}
