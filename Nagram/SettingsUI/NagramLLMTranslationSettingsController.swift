import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import NagramTranslate
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData

private enum NagramLLMTranslationInputField: Int32, Hashable {
    case baseURL
    case endpoint
    case apiKey
    case model
    case prompt
}

private final class NagramLLMTranslationArguments {
    let inputUpdated: (NagramLLMTranslationInputField, String) -> Void
    let chooseFormat: () -> Void
    let fetchModels: () -> Void
    let selectFetchedModel: () -> Void
    let testModel: () -> Void
    let updateUseContext: (Bool) -> Void
    let updateTemperature: (Int32) -> Void

    init(inputUpdated: @escaping (NagramLLMTranslationInputField, String) -> Void, chooseFormat: @escaping () -> Void, fetchModels: @escaping () -> Void, selectFetchedModel: @escaping () -> Void, testModel: @escaping () -> Void, updateUseContext: @escaping (Bool) -> Void, updateTemperature: @escaping (Int32) -> Void) {
        self.inputUpdated = inputUpdated
        self.chooseFormat = chooseFormat
        self.fetchModels = fetchModels
        self.selectFetchedModel = selectFetchedModel
        self.testModel = testModel
        self.updateUseContext = updateUseContext
        self.updateTemperature = updateTemperature
    }
}

private enum NagramLLMTranslationEntryStableId: Hashable {
    case header(Int32)
    case format
    case input(NagramLLMTranslationInputField)
    case fetchModels
    case fetchedModels
    case testModel
    case useContext
    case temperature
    case footer(Int32)
}

private enum NagramLLMTranslationEntry: ItemListNodeEntry {
    case header(section: Int32, text: String)
    case format(section: Int32, title: String, label: String)
    case input(section: Int32, field: NagramLLMTranslationInputField, title: String, text: String, placeholder: String, isSecret: Bool)
    case prompt(section: Int32, text: String, placeholder: String)
    case useContext(section: Int32, title: String, value: Bool)
    case temperature(section: Int32, title: String, minValue: Int32, maxValue: Int32, value: Int32)
    case fetchModels(section: Int32, title: String)
    case fetchedModels(section: Int32, title: String, label: String)
    case testModel(section: Int32, title: String)
    case footer(section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .format(section, _, _), let .input(section, _, _, _, _, _), let .prompt(section, _, _), let .useContext(section, _, _), let .temperature(section, _, _, _, _), let .fetchModels(section, _), let .fetchedModels(section, _, _), let .testModel(section, _), let .footer(section, _):
            return section
        }
    }

    var stableId: NagramLLMTranslationEntryStableId {
        switch self {
        case let .header(section, _):
            return .header(section)
        case .format:
            return .format
        case let .input(_, field, _, _, _, _):
            return .input(field)
        case .prompt:
            return .input(.prompt)
        case .useContext:
            return .useContext
        case .temperature:
            return .temperature
        case .fetchModels:
            return .fetchModels
        case .fetchedModels:
            return .fetchedModels
        case .testModel:
            return .testModel
        case let .footer(section, _):
            return .footer(section)
        }
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case .format:
            return 10
        case let .input(_, field, _, _, _, _):
            return 20 + field.rawValue
        case let .prompt(section, _, _), let .useContext(section, _, _), let .temperature(section, _, _, _, _):
            return section * 1000 + 10
        case .fetchModels:
            return 1010
        case .fetchedModels:
            return 1020
        case .testModel:
            return 1030
        case let .footer(section, _):
            return section * 1000 + 900
        }
    }

    static func ==(lhs: NagramLLMTranslationEntry, rhs: NagramLLMTranslationEntry) -> Bool {
        switch lhs {
        case let .header(lSection, lText):
            if case let .header(rSection, rText) = rhs { return lSection == rSection && lText == rText }
            return false
        case let .format(lSection, lTitle, lLabel):
            if case let .format(rSection, rTitle, rLabel) = rhs { return lSection == rSection && lTitle == rTitle && lLabel == rLabel }
            return false
        case let .input(lSection, lField, lTitle, lText, lPlaceholder, lIsSecret):
            if case let .input(rSection, rField, rTitle, rText, rPlaceholder, rIsSecret) = rhs { return lSection == rSection && lField == rField && lTitle == rTitle && lText == rText && lPlaceholder == rPlaceholder && lIsSecret == rIsSecret }
            return false
        case let .prompt(lSection, lText, lPlaceholder):
            if case let .prompt(rSection, rText, rPlaceholder) = rhs { return lSection == rSection && lText == rText && lPlaceholder == rPlaceholder }
            return false
        case let .useContext(lSection, lTitle, lValue):
            if case let .useContext(rSection, rTitle, rValue) = rhs { return lSection == rSection && lTitle == rTitle && lValue == rValue }
            return false
        case let .temperature(lSection, lTitle, lMinValue, lMaxValue, lValue):
            if case let .temperature(rSection, rTitle, rMinValue, rMaxValue, rValue) = rhs { return lSection == rSection && lTitle == rTitle && lMinValue == rMinValue && lMaxValue == rMaxValue && lValue == rValue }
            return false
        case let .fetchModels(lSection, lTitle):
            if case let .fetchModels(rSection, rTitle) = rhs { return lSection == rSection && lTitle == rTitle }
            return false
        case let .fetchedModels(lSection, lTitle, lLabel):
            if case let .fetchedModels(rSection, rTitle, rLabel) = rhs { return lSection == rSection && lTitle == rTitle && lLabel == rLabel }
            return false
        case let .testModel(lSection, lTitle):
            if case let .testModel(rSection, rTitle) = rhs { return lSection == rSection && lTitle == rTitle }
            return false
        case let .footer(lSection, lText):
            if case let .footer(rSection, rText) = rhs { return lSection == rSection && lText == rText }
            return false
        }
    }

    static func <(lhs: NagramLLMTranslationEntry, rhs: NagramLLMTranslationEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramLLMTranslationArguments
        switch self {
        case let .header(section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .format(section, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.chooseFormat()
            })
        case let .input(section, field, title, text, placeholder, isSecret):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: isSecret ? .password : .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: { value in
                arguments.inputUpdated(field, value)
            }, action: {
            })
        case let .prompt(section, text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 240.0, maximalHeight: 240.0, textUpdated: { value in
                arguments.inputUpdated(.prompt, value)
            })
        case let .useContext(section, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                arguments.updateUseContext(value)
            })
        case let .temperature(section, title, minValue, maxValue, value):
            return NagramSliderItem(theme: presentationData.theme, minValue: minValue, maxValue: maxValue, value: value, title: title, valueText: { value in
                return String(format: "%.1f", Double(value) / 10.0)
            }, sectionId: section, updated: { value in
                arguments.updateTemperature(value)
            })
        case let .fetchModels(section, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.fetchModels()
            })
        case let .fetchedModels(section, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.selectFetchedModel()
            })
        case let .testModel(section, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.testModel()
            })
        case let .footer(section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private enum NagramLLMModelFetchError {
    case generic
}

private func nagramLLMFetchModels() -> Signal<[String], NagramLLMModelFetchError> {
    let settings = NagramSettings.shared
    guard let url = settings.translationLLMModelsURL() else {
        return .fail(.generic)
    }
    let format = settings.translationLLMAPIFormatValue
    let apiKey = settings.translationLLMAPIKeyValue

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    switch format {
    case .openai:
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    case .anthropic:
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
    }

    return Signal { subscriber in
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                subscriber.putError(.generic)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode), let data else {
                subscriber.putError(.generic)
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rawModels = object["data"] as? [[String: Any]] else {
                subscriber.putError(.generic)
                return
            }
            let models = Array(Set(rawModels.compactMap { item -> String? in
                guard let id = item["id"] as? String, !id.isEmpty else {
                    return nil
                }
                return id
            })).sorted { lhs, rhs in
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            guard !models.isEmpty else {
                subscriber.putError(.generic)
                return
            }
            subscriber.putNext(models)
            subscriber.putCompletion()
        }
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

private func nagramLLMTranslationEntries(presentationData: PresentationData, isFetchingModels: Bool, fetchedModels: [String], fetchErrorKey: String?, isTestingModel: Bool) -> [NagramLLMTranslationEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let settings = NagramSettings.shared
    let format = settings.translationLLMAPIFormatValue
    var entries: [NagramLLMTranslationEntry] = []
    entries.append(.header(section: 0, text: ngI18n("Nagram.TranslationLLMSettings", lang)))
    entries.append(.format(section: 0, title: ngI18n("Nagram.TranslationLLMAPIFormat", lang), label: ngI18n("Nagram.TranslationLLMAPIFormat.\(format.rawValue)", lang)))
    entries.append(.input(section: 0, field: .baseURL, title: ngI18n("Nagram.TranslationLLMBaseURL", lang), text: settings.translationLLMBaseURL, placeholder: format.defaultBaseURL, isSecret: false))
    entries.append(.input(section: 0, field: .endpoint, title: ngI18n("Nagram.TranslationLLMEndpoint", lang), text: settings.translationLLMEndpoint, placeholder: format.defaultTranslationEndpoint, isSecret: false))
    entries.append(.input(section: 0, field: .apiKey, title: ngI18n("Nagram.TranslationLLMAPIKey", lang), text: settings.translationLLMAPIKey, placeholder: ngI18n("Nagram.TranslationLLMAPIKey.Placeholder", lang), isSecret: true))
    entries.append(.input(section: 0, field: .model, title: ngI18n("Nagram.TranslationLLMModel", lang), text: settings.translationLLMModel, placeholder: ngI18n("Nagram.TranslationLLMModel.Placeholder", lang), isSecret: false))
    entries.append(.footer(section: 0, text: ngI18n("Nagram.TranslationLLMSettings.Footer", lang)))

    entries.append(.header(section: 1, text: ngI18n("Nagram.TranslationLLMModels", lang)))
    entries.append(.fetchModels(section: 1, title: ngI18n(isFetchingModels ? "Nagram.TranslationLLMFetchingModels" : "Nagram.TranslationLLMFetchModels", lang)))
    if !fetchedModels.isEmpty {
        entries.append(.fetchedModels(section: 1, title: ngI18n("Nagram.TranslationLLMFetchedModels", lang), label: "\(fetchedModels.count)"))
    }
    entries.append(.testModel(section: 1, title: ngI18n(isTestingModel ? "Nagram.TranslationLLMTestingModel" : "Nagram.TranslationLLMTestModel", lang)))
    if let fetchErrorKey {
        entries.append(.footer(section: 1, text: ngI18n(fetchErrorKey, lang)))
    }

    entries.append(.header(section: 2, text: ngI18n("Nagram.TranslationLLMPrompt", lang)))
    entries.append(.prompt(section: 2, text: settings.translationLLMPrompt, placeholder: NagramSettings.defaultTranslationLLMPrompt))
    entries.append(.footer(section: 2, text: ngI18n("Nagram.TranslationLLMPrompt.Footer", lang)))

    entries.append(.useContext(section: 3, title: ngI18n("Nagram.TranslationLLMUseContext", lang), value: settings.translationLLMUseContext))
    entries.append(.footer(section: 3, text: ngI18n("Nagram.TranslationLLMUseContext.Footer", lang)))

    if format == .openai {
        entries.append(.temperature(section: 4, title: ngI18n("Nagram.TranslationLLMTemperature", lang), minValue: 0, maxValue: 20, value: settings.translationLLMTemperatureTenthsValue))
    }
    return entries
}

public func nagramLLMTranslationSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    let fetchDisposable = MetaDisposable()
    let testDisposable = MetaDisposable()
    var isFetchingModels = false
    var isTestingModel = false
    var fetchedModels: [String] = []
    var fetchErrorKey: String?
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let presentTestResult: (String, String?) -> Void = { textKey, detail in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        var text = ngI18n(textKey, lang)
        if let detail, !detail.isEmpty {
            text += "\n\n\(detail)"
        }
        presentControllerImpl?(textAlertController(context: context, title: ngI18n("Nagram.TranslationLLMTestModel", lang), text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]), nil)
    }

    let presentModels: ([String]) -> Void = { models in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: ngI18n("Nagram.TranslationLLMModels", lang))]
        for model in models {
            items.append(ActionSheetButtonItem(title: model, color: .accent, action: {
                dismissAction()
                NagramSettings.shared.translationLLMModel = model
                bump()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    let arguments = NagramLLMTranslationArguments(inputUpdated: { field, value in
        switch field {
        case .baseURL:
            NagramSettings.shared.translationLLMBaseURL = value
        case .endpoint:
            NagramSettings.shared.translationLLMEndpoint = value
        case .apiKey:
            NagramSettings.shared.translationLLMAPIKey = value
        case .model:
            NagramSettings.shared.translationLLMModel = value
        case .prompt:
            NagramSettings.shared.translationLLMPrompt = value
            bump()
        }
    }, chooseFormat: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: ngI18n("Nagram.TranslationLLMAPIFormat", lang))]
        for format in NagramTranslationLLMAPIFormat.allCases {
            items.append(ActionSheetButtonItem(title: ngI18n("Nagram.TranslationLLMAPIFormat.\(format.rawValue)", lang), color: .accent, action: {
                dismissAction()
                NagramSettings.shared.translationLLMAPIFormat = format.rawValue
                fetchedModels = []
                fetchErrorKey = nil
                bump()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })])
        ])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, fetchModels: {
        guard !isFetchingModels && !isTestingModel else {
            return
        }
        isFetchingModels = true
        fetchErrorKey = nil
        bump()
        fetchDisposable.set((nagramLLMFetchModels()
        |> deliverOnMainQueue).start(next: { models in
            isFetchingModels = false
            fetchedModels = models
            fetchErrorKey = nil
            bump()
            presentModels(models)
        }, error: { _ in
            isFetchingModels = false
            fetchedModels = []
            fetchErrorKey = "Nagram.TranslationLLMFetchModelsFailed"
            bump()
        }))
    }, selectFetchedModel: {
        if !fetchedModels.isEmpty {
            presentModels(fetchedModels)
        }
    }, testModel: {
        guard !isTestingModel && !isFetchingModels else {
            return
        }
        isTestingModel = true
        fetchErrorKey = nil
        bump()
        testDisposable.set((nagramLLMTestModel()
        |> deliverOnMainQueue).start(next: { _ in
            isTestingModel = false
            bump()
            presentTestResult("Nagram.TranslationLLMTestModelSucceeded", nil)
        }, error: { error in
            isTestingModel = false
            bump()
            presentTestResult("Nagram.TranslationLLMTestModelFailed", error.message)
        }))
    }, updateUseContext: { value in
        NagramSettings.shared.translationLLMUseContext = value
        bump()
    }, updateTemperature: { value in
        NagramSettings.shared.translationLLMTemperatureTenths = value
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries = nagramLLMTranslationEntries(presentationData: presentationData, isFetchingModels: isFetchingModels, fetchedModels: fetchedModels, fetchErrorKey: fetchErrorKey, isTestingModel: isTestingModel)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.TranslationLLMSettings", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        fetchDisposable.dispose()
        testDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    return controller
}
