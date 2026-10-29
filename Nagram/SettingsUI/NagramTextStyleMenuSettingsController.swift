import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NagramSettings
import NagramStrings

private final class NagramTextStyleMenuArguments {
    let positionSelected: (NagramTextStyleMenuPosition) -> Void
    let itemUpdated: (NagramTextStyleMenuItemId, Bool) -> Void
    let resetAction: () -> Void

    init(positionSelected: @escaping (NagramTextStyleMenuPosition) -> Void, itemUpdated: @escaping (NagramTextStyleMenuItemId, Bool) -> Void, resetAction: @escaping () -> Void) {
        self.positionSelected = positionSelected
        self.itemUpdated = itemUpdated
        self.resetAction = resetAction
    }
}

private enum NagramTextStyleMenuEntryStableId: Hashable {
    case positionHeader
    case position(NagramTextStyleMenuPosition)
    case positionFooter
    case itemsHeader
    case item(NagramTextStyleMenuItemId)
    case itemsFooter
    case reset
}

private enum NagramTextStyleMenuEntry: ItemListNodeEntry {
    case positionHeader(text: String)
    case position(index: Int, position: NagramTextStyleMenuPosition, title: String, isSelected: Bool)
    case positionFooter(text: String)
    case itemsHeader(text: String)
    case item(index: Int, id: NagramTextStyleMenuItemId, title: String, value: Bool, isEditing: Bool)
    case itemsFooter(text: String)
    case reset(title: String)

    var section: ItemListSectionId {
        switch self {
        case .positionHeader, .position, .positionFooter:
            return 0
        case .itemsHeader, .item, .itemsFooter:
            return 1
        case .reset:
            return 2
        }
    }

    var stableId: NagramTextStyleMenuEntryStableId {
        switch self {
        case .positionHeader:
            return .positionHeader
        case let .position(_, position, _, _):
            return .position(position)
        case .positionFooter:
            return .positionFooter
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
        case .positionHeader:
            return 0
        case let .position(index, _, _, _):
            return 1 + index
        case .positionFooter:
            return 99
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

    static func ==(lhs: NagramTextStyleMenuEntry, rhs: NagramTextStyleMenuEntry) -> Bool {
        switch lhs {
        case let .positionHeader(text):
            if case .positionHeader(text) = rhs { return true }
            return false
        case let .position(index, position, title, isSelected):
            if case .position(index, position, title, isSelected) = rhs { return true }
            return false
        case let .positionFooter(text):
            if case .positionFooter(text) = rhs { return true }
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

    static func <(lhs: NagramTextStyleMenuEntry, rhs: NagramTextStyleMenuEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramTextStyleMenuArguments
        switch self {
        case let .positionHeader(text), let .itemsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .position(_, position, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.positionSelected(position)
            })
        case let .positionFooter(text), let .itemsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .item(_, id, title, value, isEditing):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, editing: isEditing, reorderable: true, sectionId: self.section, style: .blocks, updated: { value in
                arguments.itemUpdated(id, value)
            })
        case let .reset(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.resetAction()
            })
        }
    }
}

func nagramTextStyleMenuItemTitle(_ id: NagramTextStyleMenuItemId, strings: PresentationStrings) -> String {
    switch id {
    case .quote:
        return strings.TextFormat_Quote
    case .spoiler:
        return strings.TextFormat_Spoiler
    case .bold:
        return strings.TextFormat_Bold
    case .italic:
        return strings.TextFormat_Italic
    case .monospace:
        return strings.TextFormat_Monospace
    case .link:
        return strings.TextFormat_Link
    case .date:
        return strings.TextFormat_Date
    case .strikethrough:
        return strings.TextFormat_Strikethrough
    case .underline:
        return strings.TextFormat_Underline
    case .code:
        return strings.TextFormat_Code
    }
}

public func nagramTextStyleMenuSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    let editingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let arguments = NagramTextStyleMenuArguments(positionSelected: { position in
        NagramSettings.shared.textStyleMenuPosition = position
        bump()
    }, itemUpdated: { id, value in
        NagramSettings.shared.setTextStyleMenuItemEnabled(id, enabled: value)
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
                ActionSheetTextItem(title: ngI18n("Nagram.TextStyleMenu.ResetConfirm", lang)),
                ActionSheetButtonItem(title: ngI18n("Nagram.TextStyleMenu.Reset", lang), color: .destructive, action: {
                    dismissAction()
                    NagramSettings.shared.resetTextStyleMenu()
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
        let currentPosition = NagramSettings.shared.textStyleMenuPosition
        var entries: [NagramTextStyleMenuEntry] = [
            .positionHeader(text: ngI18n("Nagram.TextStyleMenu.PositionHeader", lang))
        ]
        for (index, position) in NagramTextStyleMenuPosition.allCases.enumerated() {
            entries.append(.position(index: index, position: position, title: ngI18n("Nagram.TextStyleMenu.Position.\(position.rawValue)", lang), isSelected: position == currentPosition))
        }
        entries.append(.positionFooter(text: ngI18n("Nagram.TextStyleMenu.PositionFooter", lang)))
        entries.append(.itemsHeader(text: ngI18n("Nagram.TextStyleMenu.ItemsHeader", lang)))
        for (index, id) in NagramSettings.shared.textStyleMenuItemOrder.enumerated() {
            entries.append(.item(index: index, id: id, title: nagramTextStyleMenuItemTitle(id, strings: presentationData.strings), value: NagramSettings.shared.isTextStyleMenuItemEnabled(id), isEditing: isEditing))
        }
        entries.append(.itemsFooter(text: ngI18n("Nagram.TextStyleMenu.ItemsFooter", lang)))
        entries.append(.reset(title: ngI18n("Nagram.TextStyleMenu.Reset", lang)))

        let rightNavigationButton = ItemListNavigationButton(content: isEditing ? .icon(.done) : .text(presentationData.strings.Common_Edit), style: isEditing ? .bold : .regular, enabled: true, action: {
            editingPromise.set(!isEditing)
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.TextStyleMenu", lang)), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [NagramTextStyleMenuEntry]) -> Signal<Bool, NoError> in
        guard case let .item(_, fromId, _, _, _) = entries[fromIndex] else {
            return .single(false)
        }
        var order = NagramSettings.shared.textStyleMenuItemOrder
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
            NagramSettings.shared.textStyleMenuItemOrder = order
            bump()
            return .single(true)
        }
        return .single(false)
    })
    controller.setReorderCompleted({ (entries: [NagramTextStyleMenuEntry]) -> Void in
        let order = entries.compactMap { entry -> NagramTextStyleMenuItemId? in
            if case let .item(_, id, _, _, _) = entry {
                return id
            }
            return nil
        }
        if !order.isEmpty {
            NagramSettings.shared.textStyleMenuItemOrder = order
            bump()
        }
    })
    return controller
}
