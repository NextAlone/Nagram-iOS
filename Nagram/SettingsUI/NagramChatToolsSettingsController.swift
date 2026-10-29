import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NagramSettings
import NagramStrings

private final class NagramChatToolsSettingsArguments {
    let sizeSelected: (NagramChatToolsSize) -> Void
    let itemUpdated: (NagramChatToolId, Bool) -> Void
    let resetAction: () -> Void

    init(sizeSelected: @escaping (NagramChatToolsSize) -> Void, itemUpdated: @escaping (NagramChatToolId, Bool) -> Void, resetAction: @escaping () -> Void) {
        self.sizeSelected = sizeSelected
        self.itemUpdated = itemUpdated
        self.resetAction = resetAction
    }
}

private enum NagramChatToolsSettingsEntryStableId: Hashable {
    case sizeHeader
    case size(NagramChatToolsSize)
    case itemsHeader
    case item(NagramChatToolId)
    case itemsFooter
    case reset
}

private enum NagramChatToolsSettingsEntry: ItemListNodeEntry {
    case sizeHeader(text: String)
    case size(index: Int, size: NagramChatToolsSize, title: String, isSelected: Bool)
    case itemsHeader(text: String)
    case item(index: Int, id: NagramChatToolId, title: String, value: Bool, isEditing: Bool)
    case itemsFooter(text: String)
    case reset(title: String)

    var section: ItemListSectionId {
        switch self {
        case .sizeHeader, .size:
            return 0
        case .itemsHeader, .item, .itemsFooter:
            return 1
        case .reset:
            return 2
        }
    }

    var stableId: NagramChatToolsSettingsEntryStableId {
        switch self {
        case .sizeHeader:
            return .sizeHeader
        case let .size(_, size, _, _):
            return .size(size)
        case .itemsHeader:
            return .itemsHeader
        case let .item(_, id, _, _, _):
            return .item(id)
        case .itemsFooter:
            return .itemsFooter
        case .reset:
            return .reset
        }
    }

    private var sortIndex: Int {
        switch self {
        case .sizeHeader:
            return 0
        case let .size(index, _, _, _):
            return 1 + index
        case .itemsHeader:
            return 100
        case let .item(index, _, _, _, _):
            return 101 + index
        case .itemsFooter:
            return 999
        case .reset:
            return 1000
        }
    }

    static func ==(lhs: NagramChatToolsSettingsEntry, rhs: NagramChatToolsSettingsEntry) -> Bool {
        switch lhs {
        case let .sizeHeader(text):
            if case .sizeHeader(text) = rhs { return true }
            return false
        case let .size(index, size, title, isSelected):
            if case .size(index, size, title, isSelected) = rhs { return true }
            return false
        case let .itemsHeader(text):
            if case .itemsHeader(text) = rhs { return true }
            return false
        case let .item(index, id, title, value, isEditing):
            if case .item(index, id, title, value, isEditing) = rhs { return true }
            return false
        case let .itemsFooter(text):
            if case .itemsFooter(text) = rhs { return true }
            return false
        case let .reset(title):
            if case .reset(title) = rhs { return true }
            return false
        }
    }

    static func <(lhs: NagramChatToolsSettingsEntry, rhs: NagramChatToolsSettingsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramChatToolsSettingsArguments
        switch self {
        case let .sizeHeader(text), let .itemsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .size(_, size, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.sizeSelected(size)
            })
        case let .item(_, id, title, value, isEditing):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, editing: isEditing, reorderable: true, sectionId: self.section, style: .blocks, updated: { value in
                arguments.itemUpdated(id, value)
            })
        case let .itemsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .reset(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.resetAction()
            })
        }
    }
}

public func nagramChatToolsSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    let editingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let arguments = NagramChatToolsSettingsArguments(sizeSelected: { size in
        NagramSettings.shared.chatToolsSize = size
        bump()
    }, itemUpdated: { id, value in
        NagramSettings.shared.setChatToolEnabled(id, enabled: value)
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
                ActionSheetTextItem(title: ngI18n("Nagram.ChatTools.ResetConfirm", lang)),
                ActionSheetButtonItem(title: ngI18n("Nagram.ChatTools.Reset", lang), color: .destructive, action: {
                    dismissAction()
                    NagramSettings.shared.resetChatTools()
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
        let currentSize = NagramSettings.shared.chatToolsSize

        var entries: [NagramChatToolsSettingsEntry] = [
            .sizeHeader(text: ngI18n("Nagram.ChatTools.SizeHeader", lang))
        ]
        for (index, size) in NagramChatToolsSize.allCases.enumerated() {
            entries.append(.size(index: index, size: size, title: ngI18n("Nagram.ChatTools.Size.\(size.rawValue)", lang), isSelected: size == currentSize))
        }
        entries.append(.itemsHeader(text: ngI18n("Nagram.ChatTools.ItemsHeader", lang)))
        for (index, id) in NagramSettings.shared.chatToolsOrder.enumerated() {
            entries.append(.item(index: index, id: id, title: ngI18n("Nagram.ChatTools.\(id.rawValue)", lang), value: NagramSettings.shared.isChatToolEnabled(id), isEditing: isEditing))
        }
        entries.append(.itemsFooter(text: ngI18n("Nagram.ChatTools.ItemsFooter", lang)))
        entries.append(.reset(title: ngI18n("Nagram.ChatTools.Reset", lang)))

        let rightNavigationButton = ItemListNavigationButton(content: isEditing ? .icon(.done) : .text(presentationData.strings.Common_Edit), style: isEditing ? .bold : .regular, enabled: true, action: {
            editingPromise.set(!isEditing)
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.ChatTools.Settings", lang)), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [NagramChatToolsSettingsEntry]) -> Signal<Bool, NoError> in
        guard case let .item(_, fromId, _, _, _) = entries[fromIndex] else {
            return .single(false)
        }
        var order = NagramSettings.shared.chatToolsOrder
        let initialOrder = order
        order.removeAll(where: { $0 == fromId })
        if toIndex < entries.count, case let .item(_, referenceId, _, _, _) = entries[toIndex], let referenceIndex = order.firstIndex(of: referenceId) {
            order.insert(fromId, at: fromIndex < toIndex ? referenceIndex + 1 : referenceIndex)
        } else if toIndex < entries.count, entries[toIndex] < entries[fromIndex] {
            order.insert(fromId, at: 0)
        } else {
            order.append(fromId)
        }
        if order != initialOrder {
            NagramSettings.shared.chatToolsOrder = order
            bump()
            return .single(true)
        }
        return .single(false)
    })
    controller.setReorderCompleted({ (entries: [NagramChatToolsSettingsEntry]) -> Void in
        let order = entries.compactMap { entry -> NagramChatToolId? in
            if case let .item(_, id, _, _, _) = entry {
                return id
            }
            return nil
        }
        if !order.isEmpty {
            NagramSettings.shared.chatToolsOrder = order
            bump()
        }
    })
    return controller
}
