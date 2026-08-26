import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import AlertUI
import PresentationDataUtils
import AppBundle
import ContextUI
import TelegramStringFormatting
import ItemListPeerActionItem
import ItemListPeerItem
import UndoUI
import QrCodeUI

// MARK: NAGRAM
import NagramStrings

// MARK: NAGRAM
private enum InviteLinksBulkRevokeScope {
    case all
    case unavailable
}

private struct InviteLinksBulkRevokeResult {
    let successCount: Int
    let failureCount: Int
}

private let inviteLinksBulkRevokeDelay: Double = 0.5
private let inviteLinksOverlayDismissDelay: Double = 0.35

private func fetchAllPeerExportedInvitations(
    context: AccountContext,
    peerId: EnginePeer.Id,
    adminId: EnginePeer.Id?,
    offsetLink: ExportedInvitation? = nil,
    accumulatedInvitations: [ExportedInvitation] = [],
    expectedCount: Int32 = 0,
    fetchedCount: Int32 = 0,
    seenOffsetLinks: Set<String> = []
) -> Signal<[ExportedInvitation]?, NoError> {
    return context.engine.peers.direct_peerExportedInvitations(peerId: peerId, revoked: false, adminId: adminId, offsetLink: offsetLink)
    |> mapToSignal { result -> Signal<[ExportedInvitation]?, NoError> in
        guard let result, let page = result.list else {
            return .single(nil)
        }
        var invitations = accumulatedInvitations
        var existingLinks = Set(invitations.compactMap(\.link))
        for invitation in page {
            guard let link = invitation.link else {
                continue
            }
            if existingLinks.insert(link).inserted {
                invitations.append(invitation)
            }
        }
        let updatedExpectedCount = max(expectedCount, result.totalCount)
        let updatedFetchedCount = fetchedCount + Int32(page.count)
        // The server-reported total can exceed what pagination actually yields, so an empty page ends the
        // list instead of failing the whole fetch.
        if updatedFetchedCount >= updatedExpectedCount || page.isEmpty {
            return .single(invitations)
        }
        guard let nextOffset = page.reversed().first(where: { $0.link != nil && $0.date != nil }), let nextOffsetLink = nextOffset.link, nextOffsetLink != offsetLink?.link, !seenOffsetLinks.contains(nextOffsetLink) else {
            return .single(nil)
        }
        var updatedSeenOffsetLinks = seenOffsetLinks
        updatedSeenOffsetLinks.insert(nextOffsetLink)
        return fetchAllPeerExportedInvitations(
            context: context,
            peerId: peerId,
            adminId: adminId,
            offsetLink: nextOffset,
            accumulatedInvitations: invitations,
            expectedCount: updatedExpectedCount,
            fetchedCount: updatedFetchedCount,
            seenOffsetLinks: updatedSeenOffsetLinks
        )
    }
}

private func inviteLinksBulkRevokeCandidates(
    invitations: [ExportedInvitation],
    accountPeerId: EnginePeer.Id,
    protectedMainLink: String?,
    scope: InviteLinksBulkRevokeScope,
    now: Int32
) -> [ExportedInvitation] {
    return invitations.filter { invitation in
        guard case let .link(link, _, isPermanent, _, isRevoked, adminId, _, _, expireDate, usageLimit, count, _, _) = invitation else {
            return false
        }
        // Protect the current main link by both identity and the permanent flag. The explicit link check also
        // covers transient/cache states where the main invitation is not marked permanent yet.
        guard adminId == accountPeerId, link != protectedMainLink, !isPermanent, !isRevoked else {
            return false
        }
        switch scope {
        case .all:
            return true
        case .unavailable:
            let isExpired = expireDate.flatMap { $0 > 0 ? $0 : nil }.map { $0 <= now } ?? false
            let isUsageLimitReached = usageLimit.flatMap { $0 > 0 ? $0 : nil }.map { (count ?? 0) >= $0 } ?? false
            return isExpired || isUsageLimitReached
        }
    }
}

private func revokeInviteLinksSerially(
    context: AccountContext,
    peerId: EnginePeer.Id,
    links: [String]
) -> Signal<InviteLinksBulkRevokeResult, NoError> {
    let indexedLinks = Signal<(Int, String), NoError> { subscriber in
        for (index, link) in links.enumerated() {
            subscriber.putNext((index, link))
        }
        subscriber.putCompletion()
        return EmptyDisposable
    }
    return indexedLinks
    |> mapToQueue { index, link -> Signal<InviteLinksBulkRevokeResult, NoError> in
        var request = context.engine.peers.revokePeerExportedInvitation(peerId: peerId, link: link)
        if index != 0 {
            request = request |> delay(inviteLinksBulkRevokeDelay, queue: Queue.mainQueue())
        }
        return Signal { subscriber in
            let didSucceed = Atomic(value: false)
            return request.start(next: { result in
                if result != nil {
                    let _ = didSucceed.swap(true)
                }
            }, error: { _ in
                subscriber.putNext(InviteLinksBulkRevokeResult(successCount: 0, failureCount: 1))
                subscriber.putCompletion()
            }, completed: {
                let result: InviteLinksBulkRevokeResult
                if didSucceed.with({ $0 }) {
                    result = InviteLinksBulkRevokeResult(successCount: 1, failureCount: 0)
                } else {
                    result = InviteLinksBulkRevokeResult(successCount: 0, failureCount: 1)
                }
                subscriber.putNext(result)
                subscriber.putCompletion()
            })
        }
    }
    |> reduceLeft(value: InviteLinksBulkRevokeResult(successCount: 0, failureCount: 0), f: { accumulated, current in
        return InviteLinksBulkRevokeResult(
            successCount: accumulated.successCount + current.successCount,
            failureCount: accumulated.failureCount + current.failureCount
        )
    })
}

private final class InviteLinkListControllerArguments {
    let context: AccountContext
    let shareMainLink: (ExportedInvitation) -> Void
    let openMainLink: (ExportedInvitation) -> Void
    let copyLink: (ExportedInvitation) -> Void
    let mainLinkContextAction: (ExportedInvitation?, ASDisplayNode, ContextGesture?) -> Void
    let createLink: () -> Void
    // MARK: NAGRAM
    let bulkRevokeAdditionalLinks: () -> Void
    let openLink: (ExportedInvitation) -> Void
    let linkContextAction: (ExportedInvitation?, Bool, ASDisplayNode, ContextGesture?) -> Void
    let openAdmin: (ExportedInvitationCreator) -> Void
    let deleteAllRevokedLinks: () -> Void
    
    init(context: AccountContext, shareMainLink: @escaping (ExportedInvitation) -> Void, openMainLink: @escaping (ExportedInvitation) -> Void, copyLink: @escaping (ExportedInvitation) -> Void, mainLinkContextAction: @escaping (ExportedInvitation?, ASDisplayNode, ContextGesture?) -> Void, createLink: @escaping () -> Void, bulkRevokeAdditionalLinks: @escaping () -> Void, openLink: @escaping (ExportedInvitation?) -> Void, linkContextAction: @escaping (ExportedInvitation?, Bool, ASDisplayNode, ContextGesture?) -> Void, openAdmin: @escaping (ExportedInvitationCreator) -> Void, deleteAllRevokedLinks: @escaping () -> Void) {
        self.context = context
        self.shareMainLink = shareMainLink
        self.openMainLink = openMainLink
        self.copyLink = copyLink
        self.mainLinkContextAction = mainLinkContextAction
        self.createLink = createLink
        self.bulkRevokeAdditionalLinks = bulkRevokeAdditionalLinks
        self.openLink = openLink
        self.linkContextAction = linkContextAction
        self.openAdmin = openAdmin
        self.deleteAllRevokedLinks = deleteAllRevokedLinks
    }
}

private enum InviteLinksListSection: Int32 {
    case header
    case mainLink
    case links
    case revokedLinks
    case admins
}

private enum InviteLinksListEntry: ItemListNodeEntry {
    case header(PresentationTheme, NSAttributedString)
   
    case mainLinkHeader(PresentationTheme, String)
    case mainLink(PresentationTheme, ExportedInvitation?, [EnginePeer], Int32, Bool)
    case mainLinkOtherInfo(PresentationTheme, String)
    
    case linksHeader(PresentationTheme, String)
    case linksCreate(PresentationTheme, String)
    // MARK: NAGRAM
    case linksBulkRevoke(PresentationTheme, String)
    case link(Int32, PresentationTheme, ExportedInvitation?, Bool, Int32?)
    case linksInfo(PresentationTheme, String)
    
    case revokedLinksHeader(PresentationTheme, String)
    case revokedLinksDeleteAll(PresentationTheme, String)
    case revokedLink(Int32, PresentationTheme, ExportedInvitation?)
    
    case adminsHeader(PresentationTheme, String)
    case admin(Int32, PresentationTheme, ExportedInvitationCreator)
    
    var section: ItemListSectionId {
        switch self {
            case .header:
                return InviteLinksListSection.header.rawValue
            case .mainLinkHeader, .mainLink, .mainLinkOtherInfo:
                return InviteLinksListSection.mainLink.rawValue
            case .linksHeader, .linksCreate, .linksBulkRevoke, .link, .linksInfo:
                return InviteLinksListSection.links.rawValue
            case .revokedLinksHeader, .revokedLinksDeleteAll, .revokedLink:
                return InviteLinksListSection.revokedLinks.rawValue
            case .adminsHeader, .admin:
                return InviteLinksListSection.admins.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .header:
                return 0
            case .mainLinkHeader:
                return 1
            case .mainLink:
                return 2
            case .mainLinkOtherInfo:
                return 3
            case .linksHeader:
                return 4
            case .linksCreate:
                return 5
            case let .link(index, _, _, _, _):
                return 6 + index
            case .linksBulkRevoke:
                return 9999
            case .linksInfo:
                return 10000
            case .revokedLinksHeader:
                return 10001
            case .revokedLinksDeleteAll:
                return 10002
            case let .revokedLink(index, _, _):
                return 10003 + index
            case .adminsHeader:
                return 20001
            case let .admin(index, _, _):
                return 20002 + index
        }
    }
    
    static func ==(lhs: InviteLinksListEntry, rhs: InviteLinksListEntry) -> Bool {
        switch lhs {
            case let .header(lhsTheme, lhsText):
                if case let .header(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .mainLinkHeader(lhsTheme, lhsText):
                if case let .mainLinkHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .mainLink(lhsTheme, lhsInvite, lhsPeers, lhsImportersCount, lhsIsPublic):
                if case let .mainLink(rhsTheme, rhsInvite, rhsPeers, rhsImportersCount, rhsIsPublic) = rhs, lhsTheme === rhsTheme, lhsInvite == rhsInvite, lhsPeers == rhsPeers, lhsImportersCount == rhsImportersCount, lhsIsPublic == rhsIsPublic {
                    return true
                } else {
                    return false
                }
            case let .mainLinkOtherInfo(lhsTheme, lhsText):
                if case let .mainLinkOtherInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .linksHeader(lhsTheme, lhsText):
                if case let .linksHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .linksCreate(lhsTheme, lhsText):
                if case let .linksCreate(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .linksBulkRevoke(lhsTheme, lhsText):
                if case let .linksBulkRevoke(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .link(lhsIndex, lhsTheme, lhsLink, lhsCanEdit, lhsTick):
                if case let .link(rhsIndex, rhsTheme, rhsLink, rhsCanEdit, rhsTick) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsLink == rhsLink, lhsCanEdit == rhsCanEdit, lhsTick == rhsTick {
                    return true
                } else {
                    return false
                }
            case let .linksInfo(lhsTheme, lhsText):
                if case let .linksInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .revokedLinksHeader(lhsTheme, lhsText):
                if case let .revokedLinksHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .revokedLinksDeleteAll(lhsTheme, lhsText):
                if case let .revokedLinksDeleteAll(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .revokedLink(lhsIndex, lhsTheme, lhsLink):
                if case let .revokedLink(rhsIndex, rhsTheme, rhsLink) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsLink == rhsLink {
                    return true
                } else {
                    return false
                }
            case let .adminsHeader(lhsTheme, lhsText):
                if case let .adminsHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            case let .admin(lhsIndex, lhsTheme, lhsCreator):
                if case let .admin(rhsIndex, rhsTheme, rhsCreator) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsCreator == rhsCreator {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: InviteLinksListEntry, rhs: InviteLinksListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! InviteLinkListControllerArguments
        switch self {
            case let .header(theme, text):
                return InviteLinkHeaderItem(context: arguments.context, theme: theme, text: text, animationName: "Invite", sectionId: self.section)
            case let .mainLinkHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .mainLink(_, invite, peers, importersCount, isPublic):
                return ItemListPermanentInviteLinkItem(context: arguments.context, presentationData: presentationData, systemStyle: .glass, invite: invite, count: importersCount, peers: peers, displayButton: true, separateButtons: true, displayImporters: !isPublic, buttonColor: nil, sectionId: self.section, style: .blocks, copyAction: {
                    if let invite = invite {
                        arguments.copyLink(invite)
                    }
                }, shareAction: {
                    if let invite = invite {
                        arguments.shareMainLink(invite)
                    }
                }, contextAction: { node, gesture in
                    arguments.mainLinkContextAction(invite, node, gesture)
                }, viewAction: {
                    if let invite = invite {
                        arguments.openLink(invite)
                    }
                }, openCallAction: {
                })
            case let .mainLinkOtherInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section, linkAction: nil, style: .blocks, tag: nil)
            case let .linksHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .linksCreate(theme, text):
                return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesItemList.plusIconImage(theme), title: text, sectionId: self.section, editing: false, action: {
                    arguments.createLink()
                })
            // MARK: NAGRAM
            case let .linksBulkRevoke(theme, text):
                return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesItemList.deleteIconImage(theme), title: text, sectionId: self.section, color: .destructive, editing: false, action: {
                    arguments.bulkRevokeAdditionalLinks()
                })
            case let .link(_, _, invite, canEdit, _):
                return ItemListInviteLinkItem(context: arguments.context, presentationData: presentationData, systemStyle: .glass, invite: invite, share: false, sectionId: self.section, style: .blocks) { invite in
                    arguments.openLink(invite)
                } contextAction: { invite, node, gesture in
                    arguments.linkContextAction(invite, canEdit, node, gesture)
                }
            case let .linksInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .revokedLinksHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .revokedLinksDeleteAll(theme, text):
                return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesItemList.deleteIconImage(theme), title: text, sectionId: self.section, color: .destructive, editing: false, action: {
                    arguments.deleteAllRevokedLinks()
                })
            case let .revokedLink(_, _, invite):
                return ItemListInviteLinkItem(context: arguments.context, presentationData: presentationData, systemStyle: .glass, invite: invite, share: false, sectionId: self.section, style: .blocks) { invite in
                    arguments.openLink(invite)
                } contextAction: { invite, node, gesture in
                    arguments.linkContextAction(invite, false, node, gesture)
                }
            case let .adminsHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .admin(_, _, creator):
                return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: PresentationDateTimeFormat(), nameDisplayOrder: .firstLast, context: arguments.context, peer: EnginePeer(creator.peer.peer!), height: .peerList, aliasHandling: .standard, nameColor: .primary, nameStyle: .plain, presence: nil, text: .none, label: creator.count > 1 ? .disclosure("\(creator.count)") : .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: nil), revealOptions: nil, switchValue: nil, enabled: true, highlighted: false, selectable: true, sectionId: self.section, action: {
                    arguments.openAdmin(creator)
                }, setPeerIdWithRevealedOptions: { _, _ in }, removePeer: { _ in }, toggleUpdated: nil, contextAction: nil)
        }
    }
}

private func inviteLinkListControllerEntries(presentationData: PresentationData, exportedInvitation: EngineExportedPeerInvitation?, peer: EnginePeer?, invites: [ExportedInvitation]?, revokedInvites: [ExportedInvitation]?, importers: PeerInvitationImportersState?, creators: [ExportedInvitationCreator], admin: ExportedInvitationCreator?, tick: Int32) -> [InviteLinksListEntry] {
    var entries: [InviteLinksListEntry] = []
    
    if admin == nil {
        let helpText: String
        if case let .channel(peer) = peer, case .broadcast = peer.info {
            helpText = presentationData.strings.InviteLink_CreatePrivateLinkHelpChannel
        } else {
            helpText = presentationData.strings.InviteLink_CreatePrivateLinkHelp
        }
        entries.append(.header(presentationData.theme, NSAttributedString(string: helpText)))
    }
    
    let mainInvite: ExportedInvitation?
    var isPublic = false
    if let peer = peer, let address = peer.addressName, !address.isEmpty && admin == nil {
        mainInvite = .link(link: "t.me/\(address)", title: nil, isPermanent: true, requestApproval: false, isRevoked: false, adminId: EnginePeer.Id(0), date: 0, startDate: nil, expireDate: nil, usageLimit: nil, count: nil, requestedCount: nil, pricing: nil)
        isPublic = true
    } else if let invites = invites, let invite = invites.first(where: { $0.isPermanent && !$0.isRevoked }) {
        mainInvite = invite
    } else if let invite = exportedInvitation, admin == nil {
        mainInvite = invite
    } else {
        mainInvite = nil
    }
    
    entries.append(.mainLinkHeader(presentationData.theme, isPublic ? presentationData.strings.InviteLink_PublicLink.uppercased() : presentationData.strings.InviteLink_InviteLink.uppercased()))
    
    let importersCount: Int32
    if let count = importers?.count {
        importersCount = count
    } else if let mainInvite = mainInvite, case let .link(_, _, _, _, _, _, _, _, _, _, count, _, _) = mainInvite, let count = count {
        importersCount = count
    } else {
        importersCount = 0
    }
    
    entries.append(.mainLink(presentationData.theme, mainInvite, importers?.importers.prefix(3).compactMap { $0.peer.peer.flatMap(EnginePeer.init) } ?? [], importersCount, isPublic))
    if let adminPeer = admin?.peer.peer, let peer = peer {
        let string = presentationData.strings.InviteLink_OtherPermanentLinkInfo(EnginePeer(adminPeer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))
        entries.append(.mainLinkOtherInfo(presentationData.theme, string.string))
    }
    
    var additionalInvites: [ExportedInvitation]?
    if let invites = invites {
        additionalInvites = invites.filter { $0.link != mainInvite?.link }
    }
    
    var hasLinks = false
    if let additionalInvites = additionalInvites {
        hasLinks = !additionalInvites.isEmpty
    } else if let admin = admin, admin.count > 1 {
        hasLinks = true
    }
    
    if hasLinks || admin == nil {
        entries.append(.linksHeader(presentationData.theme, presentationData.strings.InviteLink_AdditionalLinks.uppercased()))
    }
    if admin == nil {
        entries.append(.linksCreate(presentationData.theme, presentationData.strings.InviteLink_Create))
    }
    
    var canEditLinks = true
    if let peer = admin?.peer.peer as? TelegramUser, peer.botInfo != nil {
        canEditLinks = false
    }
    
    if let additionalInvites = additionalInvites {
        var index: Int32 = 0
        for invite in additionalInvites {
            if case let .link(_, _, _, _, _, _, _, _, expireDate, _, _, _, _) = invite {
                entries.append(.link(index, presentationData.theme, invite, canEditLinks, expireDate != nil ? tick : nil))
                index += 1
            }
        }
    } else if let admin = admin, admin.count > 1 {
        var index: Int32 = 0
        for _ in 0 ..< admin.count - 1 {
            entries.append(.link(index, presentationData.theme, nil, false, nil))
            index += 1
        }
    }
    if admin == nil {
        // MARK: NAGRAM
        if hasLinks {
            entries.append(.linksBulkRevoke(presentationData.theme, ngI18n("Nagram.InviteLinks.BulkRevoke", presentationData.strings.baseLanguageCode)))
        }
        entries.append(.linksInfo(presentationData.theme, presentationData.strings.InviteLink_CreateNewInfo))
    }
    
    if let revokedInvites = revokedInvites {
        if !revokedInvites.isEmpty {
            entries.append(.revokedLinksHeader(presentationData.theme, presentationData.strings.InviteLink_RevokedLinks.uppercased()))
            if admin == nil {
                entries.append(.revokedLinksDeleteAll(presentationData.theme, presentationData.strings.InviteLink_DeleteAllRevokedLinks))
            }
            var index: Int32 = 0
            for invite in revokedInvites {
                entries.append(.revokedLink(index, presentationData.theme, invite))
                index += 1
            }
        }
    } else if let admin = admin, admin.revokedCount > 0 {
        entries.append(.revokedLinksHeader(presentationData.theme, presentationData.strings.InviteLink_RevokedLinks.uppercased()))
        var index: Int32 = 0
        for _ in 0 ..< admin.revokedCount {
            entries.append(.revokedLink(index, presentationData.theme, nil))
            index += 1
        }
    }
   
    if !creators.isEmpty {
        entries.append(.adminsHeader(presentationData.theme, presentationData.strings.InviteLink_OtherAdminsLinks.uppercased()))
        var index: Int32 = 0
        for creator in creators {
            if let _ = creator.peer.peer {
                entries.append(.admin(index, presentationData.theme, creator))
                index += 1
            }
        }
    }
    
    return entries
}

private struct InviteLinkListControllerState: Equatable {
    var revokingPrivateLink: Bool
}

public func inviteLinkListController(context: AccountContext, updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil, peerId: EnginePeer.Id, admin: ExportedInvitationCreator?) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var presentInGlobalOverlayImpl: ((ViewController) -> Void)?
    var navigationController: (() -> NavigationController?)?
    // MARK: NAGRAM
    var bulkRevokeAdditionalLinksImpl: (() -> Void)?
    var presentBulkRevokeConfirmationImpl: ((InviteLinksBulkRevokeScope, [ExportedInvitation]) -> Void)?
        
    var dismissTooltipsImpl: (() -> Void)?
    
    let actionsDisposable = DisposableSet()
    
    let statePromise = ValuePromise(InviteLinkListControllerState(revokingPrivateLink: false), ignoreRepeated: true)
    let stateValue = Atomic(value: InviteLinkListControllerState(revokingPrivateLink: false))
    let updateState: ((InviteLinkListControllerState) -> InviteLinkListControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
        
    let revokeLinkDisposable = MetaDisposable()
    actionsDisposable.add(revokeLinkDisposable)
    
    let deleteAllRevokedLinksDisposable = MetaDisposable()
    actionsDisposable.add(deleteAllRevokedLinksDisposable)

    // MARK: NAGRAM
    let bulkRevokeDisposable = MetaDisposable()
    actionsDisposable.add(bulkRevokeDisposable)
    let isBulkRevokeFlowActive = Atomic(value: false)
    let protectedMainLink = Atomic<String?>(value: nil)

    var getControllerImpl: (() -> ViewController?)?
    
    let adminId = admin?.peer.peer?.id
    let invitesContext = context.engine.peers.peerExportedInvitations(peerId: peerId, adminId: adminId, revoked: false, forceUpdate: true)
    let revokedInvitesContext = context.engine.peers.peerExportedInvitations(peerId: peerId, adminId: adminId, revoked: true, forceUpdate: true)
    
    let creators: Signal<[ExportedInvitationCreator], NoError>
    if adminId == nil {
        creators = .single([]) |> then(context.engine.peers.peerExportedInvitationsCreators(peerId: peerId))
    } else {
        creators = .single([])
    }
    
    let arguments = InviteLinkListControllerArguments(context: context, shareMainLink: { invite in
        guard let inviteLink = invite.link else {
            return
        }
        let shareController = context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .url(inviteLink), updatedPresentationData: updatedPresentationData, actionCompleted: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.InviteLink_InviteLinkCopiedText), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
        }, completed: { peerIds in
            let _ = (context.engine.data.get(
                EngineDataList(
                    peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)
                )
            )
            |> deliverOnMainQueue).start(next: { peerList in
                let peers = peerList.compactMap { $0 }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }

                let text: String
                var savedMessages = false
                if peerIds.count == 1, let peerId = peerIds.first, peerId == context.account.peerId {
                    text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_SavedMessages_One
                    savedMessages = true
                } else {
                    if peers.count == 1, let peer = peers.first {
                        let peerName = peer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_Chat_One(peerName).string
                    } else if peers.count == 2, let firstPeer = peers.first, let secondPeer = peers.last {
                        let firstPeerName = firstPeer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : firstPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        let secondPeerName = secondPeer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : secondPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_TwoChats_One(firstPeerName, secondPeerName).string
                    } else if let peer = peers.first {
                        let peerName = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                        text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_ManyChats_One(peerName, "\(peers.count - 1)").string
                    } else {
                        text = ""
                    }
                }

                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: savedMessages, text: text), elevatedLayout: false, animateInAsReplacement: true, action: { action in
                    if savedMessages, action == .info {
                        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
                        |> deliverOnMainQueue).start(next: { peer in
                            guard let peer else {
                                return
                            }
                            guard let navigationController = navigationController?() else {
                                return
                            }
                            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), forceOpenChat: true))
                        })
                    }
                    return false
                }), nil)
            })
        }))
        presentControllerImpl?(shareController, nil)
    }, openMainLink: { invite in
        let controller = InviteLinkViewController(context: context, updatedPresentationData: updatedPresentationData, peerId: peerId, invite: invite, invitationsContext: nil, revokedInvitationsContext: revokedInvitesContext, importersContext: nil)
        pushControllerImpl?(controller)
    }, copyLink: { invite in
        UIPasteboard.general.string = invite.link
        
        dismissTooltipsImpl?()
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.InviteLink_InviteLinkCopiedText), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
    }, mainLinkContextAction: { invite, node, gesture in
        guard let node = node as? ContextReferenceContentNode, let controller = getControllerImpl?(), let invite = invite else {
            return
        }
        
        let creatorIsBot: Signal<Bool, NoError>
        if let adminPeer = admin?.peer.peer as? TelegramUser {
            creatorIsBot = .single(adminPeer.botInfo != nil)
        } else if case let .link(_, _, _, _, _, adminId, _, _, _, _, _, _, _) = invite, adminId.toInt64() != 0 {
            creatorIsBot = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: adminId))
            |> map { peer -> Bool in
                if let peer, case let .user(user) = peer, user.botInfo != nil {
                    return true
                } else {
                    return false
                }
            }
        } else {
            creatorIsBot = .single(false)
        }
        
        let _ = (creatorIsBot
        |> take(1)
        |> deliverOnMainQueue).start(next: { creatorIsBot in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            var items: [ContextMenuItem] = []

            items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextCopy, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                f(.dismissWithoutContent)

                dismissTooltipsImpl?()

                UIPasteboard.general.string = invite.link

                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.InviteLink_InviteLinkCopiedText), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
            })))

            items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextGetQRCode, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Settings/QrIcon"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                f(.dismissWithoutContent)
                
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> mapToSignal { peer -> Signal<EnginePeer, NoError> in
                    if let peer {
                        return .single(peer)
                    } else {
                        return .never()
                    }
                }
                |> deliverOnMainQueue).start(next: { peer in
                    let isGroup: Bool
                    if case let .channel(channel) = peer, case .broadcast = channel.info {
                        isGroup = false
                    } else {
                        isGroup = true
                    }
                    presentControllerImpl?(QrCodeScreen(context: context, updatedPresentationData: updatedPresentationData, subject: .invite(invite: invite, type: isGroup ? .group : .channel)), nil)
                })
            })))

            if case let .link(_, _, _, _, _, adminId, _, _, _, _, _, _, _) = invite, adminId.toInt64() != 0, !creatorIsBot {
                items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextRevoke, textColor: .destructive, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
                }, action: { _, f in
                    f(.dismissWithoutContent)

                    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                    |> mapToSignal { peer -> Signal<EnginePeer, NoError> in
                        if let peer {
                            return .single(peer)
                        } else {
                            return .never()
                        }
                    }
                    |> deliverOnMainQueue).start(next: { peer in
                        let isGroup: Bool
                        if case let .channel(channel) = peer, case .broadcast = channel.info {
                            isGroup = false
                        } else {
                            isGroup = true
                        }

                        let controller = ActionSheetController(presentationData: presentationData)
                        let dismissAction: () -> Void = { [weak controller] in
                            controller?.dismissAnimated()
                        }
                        controller.setItemGroups([
                            ActionSheetItemGroup(items: [
                                ActionSheetTextItem(title: isGroup ? presentationData.strings.GroupInfo_InviteLink_RevokeAlert_Text : presentationData.strings.ChannelInfo_InviteLink_RevokeAlert_Text),
                                ActionSheetButtonItem(title: presentationData.strings.GroupInfo_InviteLink_RevokeLink, color: .destructive, action: {
                                    dismissAction()

                                    var revoke = false
                                    updateState { state in
                                        if !state.revokingPrivateLink {
                                            revoke = true
                                            var updatedState = state
                                            updatedState.revokingPrivateLink = true
                                            return updatedState
                                        } else {
                                            return state
                                        }
                                    }
                                    if revoke, let inviteLink = invite.link {
                                        revokeLinkDisposable.set((context.engine.peers.revokePeerExportedInvitation(peerId: peerId, link: inviteLink) |> deliverOnMainQueue).start(next: { result in
                                            updateState { state in
                                                var updatedState = state
                                                updatedState.revokingPrivateLink = false
                                                return updatedState
                                            }
                                            if let result = result {
                                                switch result {
                                                    case let .update(newInvite):
                                                        invitesContext.remove(newInvite)
                                                        revokedInvitesContext.add(newInvite)
                                                    case let .replace(previousInvite, newInvite):
                                                        revokedInvitesContext.add(previousInvite)
                                                        invitesContext.remove(previousInvite)
                                                    invitesContext.add(newInvite)
                                                }
                                            }

                                            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkRevoked(text: presentationData.strings.InviteLink_InviteLinkRevoked), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
                                        }))
                                    }
                                })
                            ]),
                            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
                        ])
                        presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                    })
                })))
            }

            let contextController = makeContextController(presentationData: presentationData, source: .reference(InviteLinkContextReferenceContentSource(controller: controller, sourceNode: node)), items: .single(ContextController.Items(content: .list(items))), gesture: gesture)
            presentInGlobalOverlayImpl?(contextController)
        })
    }, createLink: {
        let controller = inviteLinkEditController(context: context, updatedPresentationData: updatedPresentationData, peerId: peerId, invite: nil, completion: { invite in
            if let invite = invite {
                invitesContext.add(invite)
            }
        })
        controller.navigationPresentation = .modal
        pushControllerImpl?(controller)
    }, bulkRevokeAdditionalLinks: {
        // MARK: NAGRAM
        bulkRevokeAdditionalLinksImpl?()
    }, openLink: { invite in
        if let invite = invite {
            let controller = InviteLinkViewController(context: context, updatedPresentationData: updatedPresentationData, peerId: peerId, invite: invite, invitationsContext: invitesContext, revokedInvitationsContext: revokedInvitesContext, importersContext: nil)
            pushControllerImpl?(controller)
        }
    }, linkContextAction: { invite, canEdit, node, gesture in
        guard let node = node as? ContextExtractedContentContainingNode, let controller = getControllerImpl?(), let invite = invite else {
            return
        }
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var items: [ContextMenuItem] = []

        items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextCopy, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.contextMenu.primaryColor)
        }, action: { _, f in
            f(.default)
            
            dismissTooltipsImpl?()
            
            UIPasteboard.general.string = invite.link

            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.InviteLink_InviteLinkCopiedText), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
        })))
        
        if !invite.isRevoked {
            if !invitationAvailability(invite).isZero {
                items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextShare, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.contextMenu.primaryColor)
                }, action: { _, f in
                    f(.default)
                    
                    guard let inviteLink = invite.link else {
                        return
                    }
                
                    let shareController = context.sharedContext.makeShareController(context: context, params: ShareControllerParams(subject: .url(inviteLink), updatedPresentationData: updatedPresentationData, actionCompleted: {
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkCopied(title: nil, text: presentationData.strings.InviteLink_InviteLinkCopiedText), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
                    }, completed: { peerIds in
                        let _ = (context.engine.data.get(
                            EngineDataList(
                                peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)
                            )
                        )
                        |> deliverOnMainQueue).start(next: { peerList in
                            let peers = peerList.compactMap { $0 }
                            let presentationData = context.sharedContext.currentPresentationData.with { $0 }

                            let text: String
                            var savedMessages = false
                            if peerIds.count == 1, let peerId = peerIds.first, peerId == context.account.peerId {
                                text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_SavedMessages_One
                                savedMessages = true
                            } else {
                                if peers.count == 1, let peer = peers.first {
                                    let peerName = peer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_Chat_One(peerName).string
                                } else if peers.count == 2, let firstPeer = peers.first, let secondPeer = peers.last {
                                    let firstPeerName = firstPeer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : firstPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    let secondPeerName = secondPeer.id == context.account.peerId ? presentationData.strings.DialogList_SavedMessages : secondPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_TwoChats_One(firstPeerName, secondPeerName).string
                                } else if let peer = peers.first {
                                    let peerName = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                    text = presentationData.strings.InviteLink_InviteLinkForwardTooltip_ManyChats_One(peerName, "\(peers.count - 1)").string
                                } else {
                                    text = ""
                                }
                            }

                            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: savedMessages, text: text), elevatedLayout: false, animateInAsReplacement: true, action: { action in
                                if savedMessages, action == .info {
                                    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
                                    |> deliverOnMainQueue).start(next: { peer in
                                        guard let peer else {
                                            return
                                        }
                                        guard let navigationController = navigationController?() else {
                                            return
                                        }
                                        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), forceOpenChat: true))
                                    })
                                }
                                return false
                            }), nil)
                        })
                    }))
                    presentControllerImpl?(shareController, nil)
                })))
                
                items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextGetQRCode, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Settings/QrIcon"), color: theme.contextMenu.primaryColor)
                }, action: { _, f in
                    f(.default)
                    
                    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                    |> mapToSignal { peer -> Signal<EnginePeer, NoError> in
                        if let peer {
                            return .single(peer)
                        } else {
                            return .never()
                        }
                    }
                    |> deliverOnMainQueue).start(next: { peer in
                        let isGroup: Bool
                        if case let .channel(channel) = peer, case .broadcast = channel.info {
                            isGroup = false
                        } else {
                            isGroup = true
                        }
                        Queue.mainQueue().after(0.2) {
                            presentControllerImpl?(QrCodeScreen(context: context, updatedPresentationData: updatedPresentationData, subject: .invite(invite: invite, type: isGroup ? .group : .channel)), nil)
                        }
                    })
                })))
            }
            
            if !invite.isPermanent && canEdit {
                items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextEdit, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.contextMenu.primaryColor)
                }, action: { _, f in
                    f(.default)
                
                    let controller = inviteLinkEditController(context: context, updatedPresentationData: updatedPresentationData, peerId: peerId, invite: invite, completion: { invite in
                        if let invite = invite {
                            if invite.isRevoked {
                                invitesContext.remove(invite)
                                revokedInvitesContext.add(invite.withUpdated(isRevoked: true))
                            } else {
                                invitesContext.update(invite)
                            }
                        }
                    })
                    controller.navigationPresentation = .modal
                    pushControllerImpl?(controller)
                })))
            }
        }
        
        if invite.isRevoked {
            items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextDelete, textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
            }, action: { _, f in
                f(.default)
            
                let controller = ActionSheetController(presentationData: presentationData)
                let dismissAction: () -> Void = { [weak controller] in
                    controller?.dismissAnimated()
                }
                controller.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: presentationData.strings.InviteLink_DeleteLinkAlert_Text),
                        ActionSheetButtonItem(title: presentationData.strings.InviteLink_DeleteLinkAlert_Action, color: .destructive, action: {
                            dismissAction()

                            if let inviteLink = invite.link {
                                revokeLinkDisposable.set((context.engine.peers.deletePeerExportedInvitation(peerId: peerId, link: inviteLink) |> deliverOnMainQueue).start())
                            }
                            
                            revokedInvitesContext.remove(invite)
                        })
                    ]),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
                ])
                presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            })))
        } else {
            items.append(.action(ContextMenuActionItem(text: presentationData.strings.InviteLink_ContextRevoke, textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
            }, action: { _, f in
                f(.default)
            
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> mapToSignal { peer -> Signal<EnginePeer, NoError> in
                    if let peer {
                        return .single(peer)
                    } else {
                        return .never()
                    }
                }
                |> deliverOnMainQueue).start(next: { peer in
                    let isGroup: Bool
                    if case let .channel(channel) = peer, case .broadcast = channel.info {
                        isGroup = false
                    } else {
                        isGroup = true
                    }
                    let controller = ActionSheetController(presentationData: presentationData)
                    let dismissAction: () -> Void = { [weak controller] in
                        controller?.dismissAnimated()
                    }
                    controller.setItemGroups([
                        ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: isGroup ? presentationData.strings.GroupInfo_InviteLink_RevokeAlert_Text : presentationData.strings.ChannelInfo_InviteLink_RevokeAlert_Text),
                            ActionSheetButtonItem(title: presentationData.strings.GroupInfo_InviteLink_RevokeLink, color: .destructive, action: {
                                dismissAction()
                                
                                if let inviteLink = invite.link {
                                    revokeLinkDisposable.set((context.engine.peers.revokePeerExportedInvitation(peerId: peerId, link: inviteLink) |> deliverOnMainQueue).start(next: { result in
                                        if case let .replace(_, newInvite) = result {
                                            invitesContext.add(newInvite)
                                        }
                                    }))
                                }
                                
                                invitesContext.remove(invite)
                                revokedInvitesContext.add(invite.withUpdated(isRevoked: true))
                                
                                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .linkRevoked(text: presentationData.strings.InviteLink_InviteLinkRevoked), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
                            })
                        ]),
                        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
                    ])
                    presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                })
            })))
        }

        let contextController = makeContextController(presentationData: presentationData, source: .extracted(InviteLinkContextExtractedContentSource(controller: controller, sourceNode: node, keepInPlace: false, blurBackground: true)), items: .single(ContextController.Items(content: .list(items))), gesture: gesture)
        presentInGlobalOverlayImpl?(contextController)
    }, openAdmin: { admin in
        let controller = inviteLinkListController(context: context, peerId: peerId, admin: admin)
        pushControllerImpl?(controller)
    }, deleteAllRevokedLinks: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak controller] in
            controller?.dismissAnimated()
        }
        controller.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: presentationData.strings.InviteLink_DeleteAllRevokedLinksAlert_Text),
                ActionSheetButtonItem(title: presentationData.strings.InviteLink_DeleteAllRevokedLinksAlert_Action, color: .destructive, action: {
                    dismissAction()
                    
                    deleteAllRevokedLinksDisposable.set((context.engine.peers.deleteAllRevokedPeerExportedInvitations(peerId: peerId, adminId: adminId ?? context.account.peerId) |> deliverOnMainQueue).start(completed: {
                    }))
                    
                    revokedInvitesContext.clear()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    })
    
    // MARK: NAGRAM
    presentBulkRevokeConfirmationImpl = { scope, invitations in
        let links = invitations.compactMap(\.link)
        guard !links.isEmpty else {
            _ = isBulkRevokeFlowActive.swap(false)
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let languageCode = presentationData.strings.baseLanguageCode
        let actionTitle: String
        let confirmationText: String
        switch scope {
        case .all:
            actionTitle = ngI18n("Nagram.InviteLinks.RevokeAll", languageCode)
            confirmationText = NagramLocalization.shared.localizedString(
                "Nagram.InviteLinks.ConfirmAll",
                languageCode,
                args: String(links.count)
            )
        case .unavailable:
            actionTitle = ngI18n("Nagram.InviteLinks.RevokeUnavailable", languageCode)
            confirmationText = NagramLocalization.shared.localizedString(
                "Nagram.InviteLinks.ConfirmUnavailable",
                languageCode,
                args: String(links.count)
            )
        }

        var confirmedAction: (() -> Void)?
        let controller = ActionSheetController(presentationData: presentationData)
        controller.dismissed = { _ in
            if let confirmedAction {
                Queue.mainQueue().justDispatch {
                    confirmedAction()
                }
            } else {
                _ = isBulkRevokeFlowActive.swap(false)
            }
        }
        let dismissAction: () -> Void = { [weak controller] in
            controller?.dismissAnimated()
        }
        controller.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: confirmationText),
                ActionSheetButtonItem(title: actionTitle, color: .destructive, action: {
                    confirmedAction = {
                        var didFinish = false
                        var finishImpl: ((InviteLinksBulkRevokeResult) -> Void)?
                        // Once confirmed, finish the serial batch so "revoke all" cannot silently become a
                        // partial operation by dismissing the progress overlay.
                        let progressController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                        finishImpl = { [weak progressController] result in
                            if didFinish {
                                return
                            }
                            didFinish = true
                            _ = isBulkRevokeFlowActive.swap(false)
                            invitesContext.reload()
                            revokedInvitesContext.reload()
                            progressController?.dismiss()
                            if result.successCount == 0 && result.failureCount == 0 {
                                return
                            }
                            // The overlay drops the completion handed to `dismiss`, so wait out its dismissal
                            // animation before presenting anything else.
                            Queue.mainQueue().after(inviteLinksOverlayDismissDelay) {
                                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                let languageCode = presentationData.strings.baseLanguageCode
                                if result.failureCount == 0 {
                                    let text = NagramLocalization.shared.localizedString(
                                        "Nagram.InviteLinks.Success",
                                        languageCode,
                                        args: String(result.successCount)
                                    )
                                    presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: text, cancel: nil, destructive: false), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), nil)
                                } else {
                                    let text = NagramLocalization.shared.localizedString(
                                        "Nagram.InviteLinks.PartialFailure",
                                        languageCode,
                                        args: String(result.successCount), String(result.failureCount)
                                    )
                                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                                }
                            }
                        }
                        presentControllerImpl?(progressController, nil)
                        bulkRevokeDisposable.set((revokeInviteLinksSerially(context: context, peerId: peerId, links: links)
                        |> deliverOnMainQueue).start(next: { result in
                            finishImpl?(result)
                        }))
                    }
                    dismissAction()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    bulkRevokeAdditionalLinksImpl = {
        guard admin == nil, !isBulkRevokeFlowActive.swap(true) else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var cancelImpl: (() -> Void)?
        let progressController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: {
            cancelImpl?()
        }))
        cancelImpl = { [weak progressController] in
            bulkRevokeDisposable.set(nil)
            _ = isBulkRevokeFlowActive.swap(false)
            progressController?.dismiss()
        }
        presentControllerImpl?(progressController, nil)
        bulkRevokeDisposable.set((fetchAllPeerExportedInvitations(context: context, peerId: peerId, adminId: context.account.peerId)
        |> deliverOnMainQueue).start(next: { invitations in
            cancelImpl = nil
            progressController.dismiss()
            // The overlay drops the completion handed to `dismiss`, so wait out its dismissal animation
            // before presenting anything else.
            Queue.mainQueue().after(inviteLinksOverlayDismissDelay) {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let languageCode = presentationData.strings.baseLanguageCode
                guard let invitations else {
                    _ = isBulkRevokeFlowActive.swap(false)
                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: ngI18n("Nagram.InviteLinks.FetchFailed", languageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                    return
                }
                let now = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                let currentMainLink = protectedMainLink.with { $0 }
                let allCandidates = inviteLinksBulkRevokeCandidates(invitations: invitations, accountPeerId: context.account.peerId, protectedMainLink: currentMainLink, scope: .all, now: now)
                let unavailableCandidates = inviteLinksBulkRevokeCandidates(invitations: invitations, accountPeerId: context.account.peerId, protectedMainLink: currentMainLink, scope: .unavailable, now: now)
                guard !allCandidates.isEmpty else {
                    _ = isBulkRevokeFlowActive.swap(false)
                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: ngI18n("Nagram.InviteLinks.NoAdditional", languageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                    return
                }

                var selectedScopeAction: (() -> Void)?
                let controller = ActionSheetController(presentationData: presentationData)
                controller.dismissed = { _ in
                    if let selectedScopeAction {
                        Queue.mainQueue().justDispatch {
                            selectedScopeAction()
                        }
                    } else {
                        _ = isBulkRevokeFlowActive.swap(false)
                    }
                }
                let dismissAction: () -> Void = { [weak controller] in
                    controller?.dismissAnimated()
                }
                controller.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: ngI18n("Nagram.InviteLinks.ScopeInfo", languageCode)),
                        ActionSheetButtonItem(title: ngI18n("Nagram.InviteLinks.RevokeAll", languageCode), color: .destructive, action: {
                            selectedScopeAction = {
                                presentBulkRevokeConfirmationImpl?(.all, allCandidates)
                            }
                            dismissAction()
                        }),
                        ActionSheetButtonItem(title: ngI18n("Nagram.InviteLinks.RevokeUnavailable", languageCode), color: .destructive, action: {
                            selectedScopeAction = {
                                if unavailableCandidates.isEmpty {
                                    _ = isBulkRevokeFlowActive.swap(false)
                                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                    presentControllerImpl?(textAlertController(context: context, updatedPresentationData: updatedPresentationData, title: nil, text: ngI18n("Nagram.InviteLinks.NoUnavailable", presentationData.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                                } else {
                                    presentBulkRevokeConfirmationImpl?(.unavailable, unavailableCandidates)
                                }
                            }
                            dismissAction()
                        })
                    ]),
                    ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
                ])
                presentControllerImpl?(controller, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }
        }))
    }

    let mainLink: Signal<ExportedInvitation?, NoError>
    if let _ = admin {
        mainLink = invitesContext.state
        |> mapToSignal { state -> Signal<ExportedInvitation?, NoError> in
            return .single(state.invitations.first(where: { $0.isPermanent && !$0.isRevoked }))
        }
    } else {
        mainLink = context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.ExportedInvitation(id: peerId)
        )
    }
    
    let importersState = Promise<PeerInvitationImportersState?>(nil)
    let importersContext: Signal<PeerInvitationImportersContext?, NoError> = mainLink
    |> distinctUntilChanged
    |> deliverOnMainQueue
    |> map { invite -> PeerInvitationImportersContext? in
        return invite.flatMap { context.engine.peers.peerInvitationImporters(peerId: peerId, subject: .invite(invite: $0, requested: false)) }
    } |> afterNext { context in
        if let context = context {
            importersState.set(context.state |> map(Optional.init))
        } else {
            importersState.set(.single(nil))
        }
    }
    
    let timerPromise = ValuePromise<Int32>(0)
    let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: {
        timerPromise.set(Int32(CFAbsoluteTimeGetCurrent()))
    }, queue: Queue.mainQueue())
    timer.start()
    
    let previousInvites = Atomic<PeerExportedInvitationsState?>(value: nil)
    let previousRevokedInvites = Atomic<PeerExportedInvitationsState?>(value: nil)
    let previousCreators = Atomic<[ExportedInvitationCreator]?>(value: nil)
    
    let presentationData = updatedPresentationData?.signal ?? context.sharedContext.presentationData
    let signal = combineLatest(queue: .mainQueue(),
        presentationData,
        context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.ExportedInvitation(id: peerId)
        ),
        context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)
        ),
        importersContext,
        importersState.get(),
        invitesContext.state,
        revokedInvitesContext.state,
        creators,
        timerPromise.get()
    )
    |> map { presentationData, exportedInvitation, peer, importersContext, importers, invites, revokedInvites, creators, tick -> (ItemListControllerState, (ItemListNodeState, Any)) in
        _ = protectedMainLink.swap(exportedInvitation?.link)
        let previousInvites = previousInvites.swap(invites)
        let previousRevokedInvites = previousRevokedInvites.swap(revokedInvites)
        let previousCreators = previousCreators.swap(creators)
        
        var crossfade = false
        if (previousInvites?.hasLoadedOnce ?? false) != (invites.hasLoadedOnce) {
            crossfade = true
        }
        if (previousRevokedInvites?.hasLoadedOnce ?? false) != (revokedInvites.hasLoadedOnce) {
            crossfade = true
        }
        if (previousCreators?.count ?? 0) != creators.count {
            crossfade = true
        }
        
        var animateChanges = false
        if !crossfade && previousInvites?.hasLoadedOnce == true && previousRevokedInvites?.hasLoadedOnce == true && previousCreators != nil {
            animateChanges = true
        }
        
        let title: ItemListControllerTitle
        if let admin = admin, let peer = admin.peer.peer {
            title = .textWithSubtitle(EnginePeer(peer).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), presentationData.strings.InviteLink_InviteLinks(admin.count))
        } else {
            title = .text(presentationData.strings.InviteLink_Title)
        }
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: title, leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: inviteLinkListControllerEntries(presentationData: presentationData, exportedInvitation: exportedInvitation, peer: peer, invites: invites.hasLoadedOnce ? invites.invitations : nil, revokedInvites: revokedInvites.hasLoadedOnce ? revokedInvites.invitations : nil, importers: importers, creators: creators, admin: admin, tick: tick), style: .blocks, emptyStateItem: nil, crossfadeState: crossfade, animateChanges: animateChanges)
        
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        timer.invalidate()
        actionsDisposable.dispose()
    }
    
    let controller = ItemListController(context: context, state: signal)
    controller.willDisappear = { _ in
        dismissTooltipsImpl?()
    }
    controller.didDisappear = { [weak controller] _ in
        controller?.clearItemNodesHighlight(animated: true)
    }
    controller.visibleBottomContentOffsetChanged = { offset in
        if case let .known(value) = offset, value < 40.0 {
            
        }
    }
    pushControllerImpl = { [weak controller] c in
        if let controller = controller {
            (controller.navigationController as? NavigationController)?.pushViewController(c, animated: true)
        }
    }
    navigationController = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    presentControllerImpl = { [weak controller] c, p in
        if let controller = controller {
            controller.present(c, in: .window(.root), with: p)
        }
    }
    presentInGlobalOverlayImpl = { [weak controller] c in
        if let controller = controller {
            controller.presentInGlobalOverlay(c)
        }
    }
    getControllerImpl = { [weak controller] in
        return controller
    }
    dismissTooltipsImpl = { [weak controller] in
        controller?.window?.forEachController({ controller in
            if let controller = controller as? UndoOverlayController {
                controller.dismissWithCommitAction()
            }
        })
        controller?.forEachController({ controller in
            if let controller = controller as? UndoOverlayController {
                controller.dismissWithCommitAction()
            }
            return true
        })
    }
    return controller
}


public final class InviteLinkContextExtractedContentSource: ContextExtractedContentSource {
    public var keepInPlace: Bool
    public let ignoreContentTouches: Bool = true
    public let blurBackground: Bool
    
    private let controller: ViewController
    private let sourceNode: ContextExtractedContentContainingNode
    
    public init(controller: ViewController, sourceNode: ContextExtractedContentContainingNode, keepInPlace: Bool, blurBackground: Bool) {
        self.controller = controller
        self.sourceNode = sourceNode
        self.keepInPlace = keepInPlace
        self.blurBackground = blurBackground
    }
    
    public func takeView() -> ContextControllerTakeViewInfo? {
        return ContextControllerTakeViewInfo(containingItem: .node(self.sourceNode), contentAreaInScreenSpace: UIScreen.main.bounds)
    }
    
    public func putBack() -> ContextControllerPutBackViewInfo? {
        return ContextControllerPutBackViewInfo(contentAreaInScreenSpace: UIScreen.main.bounds)
    }
}

final class InviteLinkContextReferenceContentSource: ContextReferenceContentSource {
    private let controller: ViewController
    private let sourceNode: ContextReferenceContentNode
    
    init(controller: ViewController, sourceNode: ContextReferenceContentNode) {
        self.controller = controller
        self.sourceNode = sourceNode
    }
    
    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceNode.view, contentAreaInScreenSpace: UIScreen.main.bounds)
    }
}
