import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private final class NagramRegexFilterArguments {
    let openRule: (String?) -> Void

    init(openRule: @escaping (String?) -> Void) {
        self.openRule = openRule
    }
}

private func nagramRegexFilterActionTitle(_ action: NagramRegexFilterAction, lang: String) -> String {
    return ngI18n("Nagram.RegexFilters.Action.\(action.rawValue)", lang)
}

private func nagramRegexFilterAuthorPeerId(_ text: String) -> Int64? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value = Int64(trimmed), value > 0 else {
        return nil
    }
    return value
}

private func nagramRegexFilterHasInvalidAuthorPeerId(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && nagramRegexFilterAuthorPeerId(trimmed) == nil
}

private func nagramRegexFilterRuleTitle(_ rule: NagramRegexFilterRule, lang: String) -> String {
    let trimmedTitle = rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTitle.isEmpty {
        return trimmedTitle
    }
    if let authorPeerId = rule.authorPeerId {
        return "\(ngI18n("Nagram.RegexFilters.AuthorPeerId", lang)): \(authorPeerId)"
    }
    return rule.pattern
}

private func nagramRegexFilterRuleLabel(_ rule: NagramRegexFilterRule, lang: String) -> String {
    let status = ngI18n(rule.isEnabled ? "Nagram.RegexFilters.Status.Enabled" : "Nagram.RegexFilters.Status.Disabled", lang)
    if let authorPeerId = rule.authorPeerId {
        return "\(status) - \(ngI18n("Nagram.RegexFilters.AuthorPeerId", lang)): \(authorPeerId)"
    }
    let action = nagramRegexFilterActionTitle(rule.action, lang: lang)
    if !rule.peerIds.isEmpty {
        return "\(status) - \(action) - \(nagramRegexFilterScopeLabel(count: rule.peerIds.count, lang: lang)) - \(rule.pattern)"
    }
    return "\(status) - \(action) - \(rule.pattern)"
}

private func nagramRegexFilterScopeLabel(count: Int, lang: String) -> String {
    return ngI18n("Nagram.RegexFilters.Scope.Chats", lang).replacingOccurrences(of: "%d", with: "\(count)")
}

/// 从聊天里快捷添加规则时带入的内容：预填的模式，以及「只在当前聊天生效」用的聊天。
private struct NagramRegexFilterPrefill {
    let pattern: String
    let peerId: Int64
    let peerTitle: String
}

private func nagramRegexFilterScopeTitle(peerIds: [Int64], prefill: NagramRegexFilterPrefill?, lang: String) -> String {
    if let prefill, peerIds == [prefill.peerId] {
        return ngI18n("Nagram.RegexFilters.OnlyInChat", lang).replacingOccurrences(of: "%@", with: prefill.peerTitle)
    }
    return ngI18n("Nagram.RegexFilters.OnlyInChats", lang).replacingOccurrences(of: "%d", with: "\(peerIds.count)")
}

private func nagramRegexFilterValidationText(_ validation: NagramRegexFilterPatternValidation, lang: String) -> String {
    let baseText = ngI18n("Nagram.RegexFilters.InvalidPattern", lang)
    guard let errorDescription = validation.errorDescription, !errorDescription.isEmpty else {
        return baseText
    }
    return "\(baseText)\n\(errorDescription)"
}

private enum NagramRegexFilterEntryStableId: Hashable {
    case header
    case empty
    case rule(String)
    case footer
    case add
}

private enum NagramRegexFilterEntry: ItemListNodeEntry {
    case header(section: Int32, text: String)
    case rule(index: Int32, section: Int32, id: String, title: String, label: String)
    case add(section: Int32, title: String)
    case footer(section: Int32, text: String)
    case empty(section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _):
            return section
        case let .rule(_, section, _, _, _):
            return section
        case let .add(section, _):
            return section
        case let .footer(section, _):
            return section
        case let .empty(section, _):
            return section
        }
    }

    var stableId: NagramRegexFilterEntryStableId {
        switch self {
        case .header:
            return .header
        case let .rule(_, _, id, _, _):
            return .rule(id)
        case .add:
            return .add
        case .footer:
            return .footer
        case .empty:
            return .empty
        }
    }

    var sortIndex: Int32 {
        switch self {
        case .header:
            return 0
        case let .rule(index, _, _, _, _):
            return 10 + index
        case .empty:
            return 10
        case .footer:
            return 100000
        case .add:
            return 200000
        }
    }

    static func ==(lhs: NagramRegexFilterEntry, rhs: NagramRegexFilterEntry) -> Bool {
        switch lhs {
        case let .header(lSection, lText):
            if case let .header(rSection, rText) = rhs {
                return lSection == rSection && lText == rText
            }
            return false
        case let .rule(lIndex, lSection, lRuleId, lTitle, lLabel):
            if case let .rule(rIndex, rSection, rRuleId, rTitle, rLabel) = rhs {
                return lIndex == rIndex && lSection == rSection && lRuleId == rRuleId && lTitle == rTitle && lLabel == rLabel
            }
            return false
        case let .add(lSection, lTitle):
            if case let .add(rSection, rTitle) = rhs {
                return lSection == rSection && lTitle == rTitle
            }
            return false
        case let .footer(lSection, lText):
            if case let .footer(rSection, rText) = rhs {
                return lSection == rSection && lText == rText
            }
            return false
        case let .empty(lSection, lText):
            if case let .empty(rSection, rText) = rhs {
                return lSection == rSection && lText == rText
            }
            return false
        }
    }

    static func <(lhs: NagramRegexFilterEntry, rhs: NagramRegexFilterEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramRegexFilterArguments
        switch self {
        case let .header(section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .rule(_, section, id, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, labelStyle: .multilineDetailText, sectionId: section, style: .blocks, action: {
                arguments.openRule(id)
            })
        case let .add(section, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.openRule(nil)
            })
        case let .footer(section, text), let .empty(section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func nagramRegexFilterEntries(presentationData: PresentationData) -> [NagramRegexFilterEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let rules = NagramSettings.shared.regexFilterRules
    var entries: [NagramRegexFilterEntry] = []

    entries.append(.header(section: 0, text: ngI18n("Nagram.RegexFilters.Header", lang)))

    if rules.isEmpty {
        entries.append(.empty(section: 0, text: ngI18n("Nagram.RegexFilters.Empty", lang)))
    } else {
        for (index, rule) in rules.enumerated() {
            entries.append(.rule(index: Int32(index), section: 0, id: rule.id, title: nagramRegexFilterRuleTitle(rule, lang: lang), label: nagramRegexFilterRuleLabel(rule, lang: lang)))
        }
        entries.append(.footer(section: 0, text: ngI18n("Nagram.RegexFilters.Footer", lang)))
    }

    entries.append(.add(section: 1, title: ngI18n("Nagram.RegexFilters.Add", lang)))
    return entries
}

public func nagramRegexFilterSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = NagramRegexFilterArguments(openRule: { id in
        let rule = id.flatMap { id in NagramSettings.shared.regexFilterRules.first(where: { $0.id == id }) }
        pushControllerImpl?(nagramRegexFilterEditController(context: context, rule: rule, completion: {
            bump()
        }))
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.RegexFilters", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: nagramRegexFilterEntries(presentationData: presentationData), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c, animated: true)
    }
    return controller
}

private struct NagramRegexFilterEditState: Equatable {
    var title: String
    var pattern: String
    var authorPeerId: String
    var isEnabled: Bool
    var action: NagramRegexFilterAction
    var peerIds: [Int64]
    var validationError: String?
}

private final class NagramRegexFilterEditInputTag: ItemListItemTag {
    let id: Int

    init(_ id: Int) {
        self.id = id
    }

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? NagramRegexFilterEditInputTag {
            return self.id == other.id
        }
        return false
    }
}

private final class NagramRegexFilterEditArguments {
    let updateTitle: (String) -> Void
    let updatePattern: (String) -> Void
    let updateAuthorPeerId: (String) -> Void
    let updateEnabled: (Bool) -> Void
    let selectAction: (NagramRegexFilterAction) -> Void
    let updateScoped: (Bool) -> Void
    let delete: () -> Void

    init(updateTitle: @escaping (String) -> Void, updatePattern: @escaping (String) -> Void, updateAuthorPeerId: @escaping (String) -> Void, updateEnabled: @escaping (Bool) -> Void, selectAction: @escaping (NagramRegexFilterAction) -> Void, updateScoped: @escaping (Bool) -> Void, delete: @escaping () -> Void) {
        self.updateTitle = updateTitle
        self.updatePattern = updatePattern
        self.updateAuthorPeerId = updateAuthorPeerId
        self.updateEnabled = updateEnabled
        self.selectAction = selectAction
        self.updateScoped = updateScoped
        self.delete = delete
    }
}

private enum NagramRegexFilterEditEntry: ItemListNodeEntry {
    case header(stableId: Int32, section: Int32, text: String)
    case enabled(stableId: Int32, section: Int32, title: String, value: Bool)
    case action(stableId: Int32, section: Int32, title: String, value: NagramRegexFilterAction, label: String)
    case scope(stableId: Int32, section: Int32, title: String, value: Bool)
    case title(stableId: Int32, section: Int32, title: String, text: String, placeholder: String)
    case authorPeerId(stableId: Int32, section: Int32, title: String, text: String, placeholder: String)
    case pattern(stableId: Int32, section: Int32, text: String, placeholder: String)
    case error(stableId: Int32, section: Int32, text: String)
    case delete(stableId: Int32, section: Int32, title: String)
    case footer(stableId: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _):
            return section
        case let .enabled(_, section, _, _):
            return section
        case let .action(_, section, _, _, _):
            return section
        case let .scope(_, section, _, _):
            return section
        case let .title(_, section, _, _, _):
            return section
        case let .authorPeerId(_, section, _, _, _):
            return section
        case let .pattern(_, section, _, _):
            return section
        case let .error(_, section, _):
            return section
        case let .delete(_, section, _):
            return section
        case let .footer(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(stableId, _, _):
            return stableId
        case let .enabled(stableId, _, _, _):
            return stableId
        case let .action(stableId, _, _, _, _):
            return stableId
        case let .scope(stableId, _, _, _):
            return stableId
        case let .title(stableId, _, _, _, _):
            return stableId
        case let .authorPeerId(stableId, _, _, _, _):
            return stableId
        case let .pattern(stableId, _, _, _):
            return stableId
        case let .error(stableId, _, _):
            return stableId
        case let .delete(stableId, _, _):
            return stableId
        case let .footer(stableId, _, _):
            return stableId
        }
    }

    static func ==(lhs: NagramRegexFilterEditEntry, rhs: NagramRegexFilterEditEntry) -> Bool {
        switch lhs {
        case let .header(lId, lSection, lText):
            if case let .header(rId, rSection, rText) = rhs { return lId == rId && lSection == rSection && lText == rText }
            return false
        case let .enabled(lId, lSection, lTitle, lValue):
            if case let .enabled(rId, rSection, rTitle, rValue) = rhs { return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue }
            return false
        case let .action(lId, lSection, lTitle, lValue, lLabel):
            if case let .action(rId, rSection, rTitle, rValue, rLabel) = rhs { return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue && lLabel == rLabel }
            return false
        case let .scope(lId, lSection, lTitle, lValue):
            if case let .scope(rId, rSection, rTitle, rValue) = rhs { return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue }
            return false
        case let .title(lId, lSection, lTitle, lText, lPlaceholder):
            if case let .title(rId, rSection, rTitle, rText, rPlaceholder) = rhs { return lId == rId && lSection == rSection && lTitle == rTitle && lText == rText && lPlaceholder == rPlaceholder }
            return false
        case let .authorPeerId(lId, lSection, lTitle, lText, lPlaceholder):
            if case let .authorPeerId(rId, rSection, rTitle, rText, rPlaceholder) = rhs { return lId == rId && lSection == rSection && lTitle == rTitle && lText == rText && lPlaceholder == rPlaceholder }
            return false
        case let .pattern(lId, lSection, lText, lPlaceholder):
            if case let .pattern(rId, rSection, rText, rPlaceholder) = rhs { return lId == rId && lSection == rSection && lText == rText && lPlaceholder == rPlaceholder }
            return false
        case let .error(lId, lSection, lText):
            if case let .error(rId, rSection, rText) = rhs { return lId == rId && lSection == rSection && lText == rText }
            return false
        case let .delete(lId, lSection, lTitle):
            if case let .delete(rId, rSection, rTitle) = rhs { return lId == rId && lSection == rSection && lTitle == rTitle }
            return false
        case let .footer(lId, lSection, lText):
            if case let .footer(rId, rSection, rText) = rhs { return lId == rId && lSection == rSection && lText == rText }
            return false
        }
    }

    static func <(lhs: NagramRegexFilterEditEntry, rhs: NagramRegexFilterEditEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramRegexFilterEditArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .enabled(_, section, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                arguments.updateEnabled(value)
            })
        case let .action(_, section, title, value, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.selectAction(value)
            })
        case let .scope(_, section, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                arguments.updateScoped(value)
            })
        case let .title(_, section, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .next, clearType: .always, tag: NagramRegexFilterEditInputTag(0), sectionId: section, textUpdated: { value in
                arguments.updateTitle(value)
            }, action: {})
        case let .authorPeerId(_, section, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: text, placeholder: placeholder, type: .number, returnKeyType: .next, clearType: .always, tag: NagramRegexFilterEditInputTag(2), sectionId: section, textUpdated: { value in
                arguments.updateAuthorPeerId(value)
            }, action: {})
        case let .pattern(_, section, text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .done, minimalHeight: 80.0, textUpdated: { value in
                arguments.updatePattern(value)
            }, tag: NagramRegexFilterEditInputTag(1))
        case let .error(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .delete(_, section, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: section, style: .blocks, action: {
                arguments.delete()
            })
        case let .footer(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func nagramRegexFilterEditEntries(presentationData: PresentationData, state: NagramRegexFilterEditState, isNew: Bool, scopeCandidatePeerIds: [Int64], prefill: NagramRegexFilterPrefill?) -> [NagramRegexFilterEditEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [NagramRegexFilterEditEntry] = []
    var stableId: Int32 = 0

    entries.append(.header(stableId: stableId, section: 0, text: ngI18n("Nagram.RegexFilters.Rule", lang)))
    stableId += 1
    entries.append(.enabled(stableId: stableId, section: 0, title: ngI18n("Nagram.RegexFilters.Enabled", lang), value: state.isEnabled))
    stableId += 1
    entries.append(.action(stableId: stableId, section: 0, title: ngI18n("Nagram.RegexFilters.Action", lang), value: state.action, label: nagramRegexFilterActionTitle(state.action, lang: lang)))
    stableId += 1
    if !scopeCandidatePeerIds.isEmpty {
        let scopePeerIds = state.peerIds.isEmpty ? scopeCandidatePeerIds : state.peerIds
        entries.append(.scope(stableId: stableId, section: 0, title: nagramRegexFilterScopeTitle(peerIds: scopePeerIds, prefill: prefill, lang: lang), value: !state.peerIds.isEmpty))
    }
    stableId += 1
    entries.append(.authorPeerId(stableId: stableId, section: 0, title: ngI18n("Nagram.RegexFilters.AuthorPeerId", lang), text: state.authorPeerId, placeholder: ngI18n("Nagram.RegexFilters.AuthorPeerId.Placeholder", lang)))
    stableId += 1
    entries.append(.title(stableId: stableId, section: 0, title: ngI18n("Nagram.RegexFilters.RuleName", lang), text: state.title, placeholder: ngI18n("Nagram.RegexFilters.RuleName.Placeholder", lang)))
    stableId += 1
    entries.append(.pattern(stableId: stableId, section: 0, text: state.pattern, placeholder: ngI18n("Nagram.RegexFilters.Pattern.Placeholder", lang)))
    stableId += 1
    let authorPeerIdText = state.authorPeerId.trimmingCharacters(in: .whitespacesAndNewlines)
    if nagramRegexFilterHasInvalidAuthorPeerId(authorPeerIdText) {
        entries.append(.error(stableId: stableId, section: 0, text: ngI18n("Nagram.RegexFilters.InvalidAuthorPeerId", lang)))
        stableId += 1
    } else if let validationError = state.validationError {
        entries.append(.error(stableId: stableId, section: 0, text: validationError))
        stableId += 1
    } else {
        entries.append(.footer(stableId: stableId, section: 0, text: ngI18n(prefill != nil && isNew ? "Nagram.RegexFilters.QuickAdd.Footer" : "Nagram.RegexFilters.Edit.Footer", lang)))
        stableId += 1
    }

    if !isNew {
        entries.append(.delete(stableId: stableId, section: 1, title: ngI18n("Nagram.RegexFilters.Delete", lang)))
    }

    return entries
}

private func nagramRegexFilterEditController(context: AccountContext, rule: NagramRegexFilterRule?, prefill: NagramRegexFilterPrefill? = nil, completion: @escaping () -> Void) -> ViewController {
    // 已限定聊天的规则可以改回所有聊天；从聊天里快捷添加的新规则默认只在该聊天生效。
    let scopeCandidatePeerIds: [Int64]
    if let rule, !rule.peerIds.isEmpty {
        scopeCandidatePeerIds = rule.peerIds
    } else if let prefill {
        scopeCandidatePeerIds = [prefill.peerId]
    } else {
        scopeCandidatePeerIds = []
    }
    let initialPeerIds: [Int64] = rule?.peerIds ?? (prefill.map { [$0.peerId] } ?? [])
    let initialState = NagramRegexFilterEditState(title: rule?.title ?? "", pattern: rule?.pattern ?? prefill?.pattern ?? "", authorPeerId: rule?.authorPeerId.flatMap { String($0) } ?? "", isEnabled: rule?.isEnabled ?? true, action: rule?.action ?? .hide, peerIds: initialPeerIds, validationError: nil)
    let statePromise = ValuePromise<NagramRegexFilterEditState>(initialState, ignoreRepeated: false)
    let stateValue = Atomic<NagramRegexFilterEditState>(value: initialState)

    var saveImpl: (() -> Void)?
    var deleteImpl: (() -> Void)?
    var selectActionImpl: ((NagramRegexFilterAction) -> Void)?

    let arguments = NagramRegexFilterEditArguments(updateTitle: { value in
        let updated = stateValue.modify { state -> NagramRegexFilterEditState in
            var state = state
            state.title = value
            return state
        }
        statePromise.set(updated)
    }, updatePattern: { value in
        let updated = stateValue.modify { state -> NagramRegexFilterEditState in
            var state = state
            state.pattern = value
            state.validationError = nil
            return state
        }
        statePromise.set(updated)
    }, updateAuthorPeerId: { value in
        let updated = stateValue.modify { state -> NagramRegexFilterEditState in
            var state = state
            state.authorPeerId = value
            state.validationError = nil
            return state
        }
        statePromise.set(updated)
    }, updateEnabled: { value in
        let updated = stateValue.modify { state -> NagramRegexFilterEditState in
            var state = state
            state.isEnabled = value
            return state
        }
        statePromise.set(updated)
    }, selectAction: { value in
        selectActionImpl?(value)
    }, updateScoped: { value in
        let updated = stateValue.modify { state -> NagramRegexFilterEditState in
            var state = state
            state.peerIds = value ? scopeCandidatePeerIds : []
            return state
        }
        statePromise.set(updated)
    }, delete: {
        deleteImpl?()
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let pattern = state.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorPeerIdText = state.authorPeerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = !nagramRegexFilterHasInvalidAuthorPeerId(authorPeerIdText) && (nagramRegexFilterAuthorPeerId(authorPeerIdText) != nil || !pattern.isEmpty)
        let rightNavigationButton = ItemListNavigationButton(content: .text(ngI18n("Nagram.Common.Save", lang)), style: .bold, enabled: canSave, action: {
            saveImpl?()
        })
        let title = rule == nil ? ngI18n("Nagram.RegexFilters.Add", lang) : ngI18n("Nagram.RegexFilters.Edit", lang)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: nagramRegexFilterEditEntries(presentationData: presentationData, state: state, isNew: rule == nil, scopeCandidatePeerIds: scopeCandidatePeerIds, prefill: prefill), style: .blocks, focusItemTag: rule == nil ? NagramRegexFilterEditInputTag(1) : nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default

    selectActionImpl = { [weak controller] _ in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: ngI18n("Nagram.RegexFilters.Action", lang))]
        for action in NagramRegexFilterAction.allCases {
            items.append(ActionSheetButtonItem(title: nagramRegexFilterActionTitle(action, lang: lang), color: .accent, action: {
                dismissAction()
                let updated = stateValue.modify { state -> NagramRegexFilterEditState in
                    var state = state
                    state.action = action
                    return state
                }
                statePromise.set(updated)
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: {
                    dismissAction()
                })
            ])
        ])
        controller?.present(actionSheet, in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    saveImpl = { [weak controller] in
        let state = stateValue.with { $0 }
        let pattern = state.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorPeerIdText = state.authorPeerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorPeerId = nagramRegexFilterAuthorPeerId(authorPeerIdText)
        guard !nagramRegexFilterHasInvalidAuthorPeerId(authorPeerIdText) else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let validationText = ngI18n("Nagram.RegexFilters.InvalidAuthorPeerId", lang)
            let updated = stateValue.modify { state -> NagramRegexFilterEditState in
                var state = state
                state.validationError = validationText
                return state
            }
            statePromise.set(updated)
            controller?.present(textAlertController(context: context, title: nil, text: validationText, actions: [
                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
            ]), in: .window(.root))
            return
        }
        let validation: NagramRegexFilterPatternValidation = authorPeerId == nil ? NagramRegexFilterRule.validatePattern(pattern) : .valid
        guard validation.isValid else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            let validationText = nagramRegexFilterValidationText(validation, lang: lang)
            let updated = stateValue.modify { state -> NagramRegexFilterEditState in
                var state = state
                state.validationError = validationText
                return state
            }
            statePromise.set(updated)
            controller?.present(textAlertController(context: context, title: nil, text: validationText, actions: [
                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
            ]), in: .window(.root))
            return
        }

        let updatedRule = NagramRegexFilterRule(id: rule?.id ?? UUID().uuidString, title: state.title.trimmingCharacters(in: .whitespacesAndNewlines), pattern: authorPeerId == nil ? pattern : "", isEnabled: state.isEnabled, action: authorPeerId == nil ? state.action : .hide, replacement: "", authorPeerId: authorPeerId, peerIds: state.peerIds)
        NagramSettings.shared.upsertRegexFilterRule(updatedRule)
        completion()
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }

    deleteImpl = { [weak controller] in
        guard let rule else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        controller?.present(textAlertController(context: context, title: nil, text: ngI18n("Nagram.RegexFilters.DeleteConfirm", lang), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: ngI18n("Nagram.RegexFilters.Delete", lang), action: { [weak controller] in
                NagramSettings.shared.removeRegexFilterRule(id: rule.id)
                completion()
                let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
            })
        ]), in: .window(.root))
    }

    return controller
}

/// 从聊天里长按消息快捷添加过滤规则：预填转义后的消息文字，默认只在该聊天生效，可在编辑页删减为关键字或改为所有聊天。
public func nagramRegexFilterQuickAddController(context: AccountContext, text: String, peerId: Int64, peerTitle: String) -> ViewController {
    let prefill = NagramRegexFilterPrefill(pattern: NSRegularExpression.escapedPattern(for: text.trimmingCharacters(in: .whitespacesAndNewlines)), peerId: peerId, peerTitle: peerTitle)
    return nagramRegexFilterEditController(context: context, rule: nil, prefill: prefill, completion: {})
}
