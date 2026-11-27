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

private enum ProfileTabEntry: ItemListNodeEntry {
    case pane(index: Int, id: NagramProfilePane, title: String, visible: Bool)
    case footer(String)

    var section: ItemListSectionId { return 0 }

    var stableId: NagramProfilePane? {
        switch self {
        case let .pane(_, id, _, _): return id
        case .footer: return nil
        }
    }

    private var sortIndex: Int {
        switch self {
        case let .pane(index, _, _, _): return index
        case .footer: return NagramProfilePane.allCases.count
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .pane(_, pane, title, visible):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: visible, sectionId: self.section, style: .blocks, updated: { visible in
                NagramSettings.shared.setProfilePaneHidden(!visible, for: pane)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func nagramProfileTabsController(context: AccountContext) -> ViewController {
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        nagramProfilePaneSettingsSignal()
    )
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings
        let lang = strings.baseLanguageCode
        var entries = settings.ordered(NagramProfilePane.allCases).enumerated().map { index, pane in
            ProfileTabEntry.pane(index: index, id: pane, title: nagramProfilePaneTitle(pane, strings: strings), visible: !settings.isHidden(pane))
        }
        entries.append(.footer(ngI18n("Nagram.ProfileTabs.Footer", lang)))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text(ngI18n("Nagram.ProfileTabs", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back))
        let list = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (list, ()))
    }
    return ItemListController(context: context, state: signal)
}
