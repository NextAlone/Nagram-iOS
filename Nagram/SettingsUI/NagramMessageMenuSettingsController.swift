import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NagramSettings
import NagramStrings

private final class NagramMessageMenuArguments {
    let itemUpdated: (NagramMessageMenuItemId, Bool) -> Void
    let resetAction: () -> Void

    init(itemUpdated: @escaping (NagramMessageMenuItemId, Bool) -> Void, resetAction: @escaping () -> Void) {
        self.itemUpdated = itemUpdated
        self.resetAction = resetAction
    }
}

private enum NagramMessageMenuEntryStableId: Hashable {
    case header
    case item(NagramMessageMenuItemId)
    case reset
    case footer
}

private enum NagramMessageMenuEntry: ItemListNodeEntry {
    case header(text: String)
    case item(index: Int, id: NagramMessageMenuItemId, title: String, value: Bool, isEditing: Bool, canReorder: Bool)
    case reset(title: String)
    case footer(text: String)

    var section: ItemListSectionId {
        switch self {
        case .header, .item:
            return 0
        case .reset, .footer:
            return 1
        }
    }

    var stableId: NagramMessageMenuEntryStableId {
        switch self {
        case .header:
            return .header
        case let .item(_, id, _, _, _, _):
            return .item(id)
        case .reset:
            return .reset
        case .footer:
            return .footer
        }
    }
    
    private var sortIndex: Int {
        switch self {
        case .header:
            return -1
        case let .item(index, _, _, _, _, _):
            return index
        case .reset:
            return 10000
        case .footer:
            return 10001
        }
    }

    static func ==(lhs: NagramMessageMenuEntry, rhs: NagramMessageMenuEntry) -> Bool {
        switch lhs {
        case let .header(text):
            if case .header(text) = rhs { return true }
            return false
        case let .item(index, id, title, value, isEditing, canReorder):
            if case .item(index, id, title, value, isEditing, canReorder) = rhs { return true }
            return false
        case let .reset(title):
            if case .reset(title) = rhs { return true }
            return false
        case let .footer(text):
            if case .footer(text) = rhs { return true }
            return false
        }
    }

    static func <(lhs: NagramMessageMenuEntry, rhs: NagramMessageMenuEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramMessageMenuArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .item(_, id, title, value, isEditing, canReorder):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, editing: isEditing, reorderable: canReorder, sectionId: self.section, style: .blocks, updated: { value in
                arguments.itemUpdated(id, value)
            })
        case let .reset(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.resetAction()
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func nagramMessageMenuSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    let editingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let arguments = NagramMessageMenuArguments(itemUpdated: { id, value in
        NagramSettings.shared.setMessageMenuItemEnabled(id, enabled: value)
        bump()
    }, resetAction: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: ngI18n("Nagram.MessageMenu.ResetConfirm", lang)),
                ActionSheetButtonItem(title: ngI18n("Nagram.MessageMenu.Reset", lang), color: .destructive, action: {
                    dismissAction()
                    NagramSettings.shared.resetMessageMenuItems()
                    bump()
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get(),
        editingPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _, isEditing -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let order = NagramSettings.shared.messageMenuItemOrder
        var entries: [NagramMessageMenuEntry] = [
            .header(text: ngI18n("Nagram.MessageMenu.Header", lang))
        ]
        for (index, id) in order.enumerated() {
            let enabled = NagramSettings.shared.isMessageMenuItemEnabled(id)
            entries.append(.item(index: index, id: id, title: ngI18n("Nagram.MessageMenu.Item.\(id.rawValue)", lang), value: enabled, isEditing: isEditing, canReorder: order.count > 1))
        }
        entries.append(.reset(title: ngI18n("Nagram.MessageMenu.Reset", lang)))
        entries.append(.footer(text: ngI18n("Nagram.MessageMenu.Footer", lang)))

        let rightNavigationButton = ItemListNavigationButton(content: isEditing ? .icon(.done) : .text(presentationData.strings.Common_Edit), style: isEditing ? .bold : .regular, enabled: true, action: {
            editingPromise.set(!isEditing)
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.MessageMenu", lang)), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [NagramMessageMenuEntry]) -> Signal<Bool, NoError> in
        let fromEntry = entries[fromIndex]
        guard case let .item(_, fromId, _, _, _, _) = fromEntry else {
            return .single(false)
        }
        
        var referenceId: NagramMessageMenuItemId?
        var beforeAll = false
        var afterAll = false
        if toIndex < entries.count {
            switch entries[toIndex] {
            case let .item(_, id, _, _, _, _):
                referenceId = id
            default:
                if entries[toIndex] < fromEntry {
                    beforeAll = true
                } else {
                    afterAll = true
                }
            }
        } else {
            afterAll = true
        }
        
        var order = NagramSettings.shared.messageMenuItemOrder
        let initialOrder = order
        if let index = order.firstIndex(of: fromId) {
            order.remove(at: index)
        }
        if let referenceId {
            var inserted = false
            for i in 0 ..< order.count {
                if order[i] == referenceId {
                    if fromIndex < toIndex {
                        order.insert(fromId, at: i + 1)
                    } else {
                        order.insert(fromId, at: i)
                    }
                    inserted = true
                    break
                }
            }
            if !inserted {
                order.append(fromId)
            }
        } else if beforeAll {
            order.insert(fromId, at: 0)
        } else if afterAll {
            order.append(fromId)
        }
        
        if initialOrder != order {
            NagramSettings.shared.messageMenuItemOrder = order
            bump()
            return .single(true)
        } else {
            return .single(false)
        }
    })
    controller.setReorderCompleted({ (entries: [NagramMessageMenuEntry]) -> Void in
        let order = entries.compactMap { entry -> NagramMessageMenuItemId? in
            if case let .item(_, id, _, _, _, _) = entry {
                return id
            }
            return nil
        }
        if !order.isEmpty {
            NagramSettings.shared.messageMenuItemOrder = order
            bump()
        }
    })
    return controller
}
