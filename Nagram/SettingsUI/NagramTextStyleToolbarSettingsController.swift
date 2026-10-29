import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import NagramSettings
import NagramStrings

private final class NagramTextStyleToolbarArguments {
    let modeSelected: (NagramTextStyleToolbarMode) -> Void
    let itemUpdated: (NagramTextStyleMenuItemId, Bool) -> Void
    let resetAction: () -> Void

    init(modeSelected: @escaping (NagramTextStyleToolbarMode) -> Void, itemUpdated: @escaping (NagramTextStyleMenuItemId, Bool) -> Void, resetAction: @escaping () -> Void) {
        self.modeSelected = modeSelected
        self.itemUpdated = itemUpdated
        self.resetAction = resetAction
    }
}

private enum NagramTextStyleToolbarEntryStableId: Hashable {
    case previewHeader
    case preview
    case modeHeader
    case mode(NagramTextStyleToolbarMode)
    case itemsHeader
    case item(NagramTextStyleMenuItemId)
    case itemsFooter
    case reset
}

private enum NagramTextStyleToolbarEntry: ItemListNodeEntry {
    case previewHeader(text: String)
    case preview(theme: PresentationTheme, barTitle: String, panelTitle: String, emptyText: String, styles: [NagramTextStylePreviewItem.Style], showsBar: Bool, showsPanel: Bool)
    case modeHeader(text: String)
    case mode(index: Int, mode: NagramTextStyleToolbarMode, title: String, isSelected: Bool)
    case itemsHeader(text: String)
    case item(index: Int, id: NagramTextStyleMenuItemId, title: String, value: Bool, isEditing: Bool)
    case itemsFooter(text: String)
    case reset(title: String)

    var section: ItemListSectionId {
        switch self {
        case .previewHeader, .preview:
            return 0
        case .modeHeader, .mode:
            return 1
        case .itemsHeader, .item, .itemsFooter:
            return 2
        case .reset:
            return 3
        }
    }

    var stableId: NagramTextStyleToolbarEntryStableId {
        switch self {
        case .previewHeader:
            return .previewHeader
        case .preview:
            return .preview
        case .modeHeader:
            return .modeHeader
        case let .mode(_, mode, _, _):
            return .mode(mode)
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
        case .previewHeader:
            return 0
        case .preview:
            return 1
        case .modeHeader:
            return 10
        case let .mode(index, _, _, _):
            return 11 + index
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

    static func ==(lhs: NagramTextStyleToolbarEntry, rhs: NagramTextStyleToolbarEntry) -> Bool {
        switch lhs {
        case let .previewHeader(text):
            if case .previewHeader(text) = rhs { return true }
            return false
        case let .preview(lhsTheme, lhsBarTitle, lhsPanelTitle, lhsEmptyText, lhsStyles, lhsShowsBar, lhsShowsPanel):
            if case let .preview(rhsTheme, rhsBarTitle, rhsPanelTitle, rhsEmptyText, rhsStyles, rhsShowsBar, rhsShowsPanel) = rhs, lhsTheme === rhsTheme, lhsBarTitle == rhsBarTitle, lhsPanelTitle == rhsPanelTitle, lhsEmptyText == rhsEmptyText, lhsStyles == rhsStyles, lhsShowsBar == rhsShowsBar, lhsShowsPanel == rhsShowsPanel { return true }
            return false
        case let .modeHeader(text):
            if case .modeHeader(text) = rhs { return true }
            return false
        case let .mode(index, mode, title, isSelected):
            if case .mode(index, mode, title, isSelected) = rhs { return true }
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

    static func <(lhs: NagramTextStyleToolbarEntry, rhs: NagramTextStyleToolbarEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramTextStyleToolbarArguments
        switch self {
        case let .previewHeader(text), let .modeHeader(text), let .itemsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .preview(theme, barTitle, panelTitle, emptyText, styles, showsBar, showsPanel):
            return NagramTextStylePreviewItem(theme: theme, barTitle: barTitle, panelTitle: panelTitle, emptyText: emptyText, styles: styles, showsBar: showsBar, showsPanel: showsPanel, sectionId: self.section)
        case let .mode(_, mode, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.modeSelected(mode)
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

public func nagramTextStyleToolbarSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    let editingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let arguments = NagramTextStyleToolbarArguments(modeSelected: { mode in
        NagramSettings.shared.textStyleToolbarMode = mode
        bump()
    }, itemUpdated: { id, value in
        NagramSettings.shared.setTextStyleToolbarItemEnabled(id, enabled: value)
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
                ActionSheetTextItem(title: ngI18n("Nagram.TextStyleToolbar.ResetConfirm", lang)),
                ActionSheetButtonItem(title: ngI18n("Nagram.TextStyleToolbar.Reset", lang), color: .destructive, action: {
                    dismissAction()
                    NagramSettings.shared.resetTextStyleToolbarItems()
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
        let mode = NagramSettings.shared.textStyleToolbarMode
        let styles = NagramSettings.shared.enabledTextStyleToolbarItems.map { id in
            return NagramTextStylePreviewItem.Style(id: id, title: nagramTextStyleMenuItemTitle(id, strings: presentationData.strings))
        }

        var entries: [NagramTextStyleToolbarEntry] = [
            .previewHeader(text: ngI18n("Nagram.TextStyleToolbar.PreviewHeader", lang)),
            .preview(theme: presentationData.theme, barTitle: ngI18n("Nagram.TextStyleToolbar.PreviewBar", lang), panelTitle: ngI18n("Nagram.TextStyleToolbar.PreviewPanel", lang), emptyText: ngI18n("Nagram.TextStyleToolbar.PreviewEmpty", lang), styles: styles, showsBar: mode.showsBar, showsPanel: mode.showsPanel),
            .modeHeader(text: ngI18n("Nagram.TextStyleToolbar.ModeHeader", lang))
        ]
        for (index, value) in NagramTextStyleToolbarMode.allCases.enumerated() {
            entries.append(.mode(index: index, mode: value, title: ngI18n("Nagram.TextStyleToolbar.\(value.rawValue)", lang), isSelected: value == mode))
        }
        entries.append(.itemsHeader(text: ngI18n("Nagram.TextStyleToolbar.ItemsHeader", lang)))
        for (index, id) in NagramSettings.shared.textStyleToolbarItemOrder.enumerated() {
            entries.append(.item(index: index, id: id, title: nagramTextStyleMenuItemTitle(id, strings: presentationData.strings), value: NagramSettings.shared.isTextStyleToolbarItemEnabled(id), isEditing: isEditing))
        }
        entries.append(.itemsFooter(text: ngI18n("Nagram.TextStyleToolbar.ItemsFooter", lang)))
        entries.append(.reset(title: ngI18n("Nagram.TextStyleToolbar.Reset", lang)))

        let rightNavigationButton = ItemListNavigationButton(content: isEditing ? .icon(.done) : .text(presentationData.strings.Common_Edit), style: isEditing ? .bold : .regular, enabled: true, action: {
            editingPromise.set(!isEditing)
        })
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.TextStyleToolbar", lang)), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [NagramTextStyleToolbarEntry]) -> Signal<Bool, NoError> in
        guard case let .item(_, fromId, _, _, _) = entries[fromIndex] else {
            return .single(false)
        }
        var order = NagramSettings.shared.textStyleToolbarItemOrder
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
            NagramSettings.shared.textStyleToolbarItemOrder = order
            bump()
            return .single(true)
        }
        return .single(false)
    })
    controller.setReorderCompleted({ (entries: [NagramTextStyleToolbarEntry]) -> Void in
        let order = entries.compactMap { entry -> NagramTextStyleMenuItemId? in
            if case let .item(_, id, _, _, _) = entry {
                return id
            }
            return nil
        }
        if !order.isEmpty {
            NagramSettings.shared.textStyleToolbarItemOrder = order
            bump()
        }
    })
    return controller
}
