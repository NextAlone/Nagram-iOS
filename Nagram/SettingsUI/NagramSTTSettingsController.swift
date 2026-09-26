import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramStrings
import NagramTranscription
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData

private enum NagramSTTInputField: Int32 {
    case baseURL
    case endpoint
    case apiKey
    case model
    case language
    case prompt
}

private final class NagramSTTSettingsArguments {
    let inputUpdated: (NagramSTTInputField, String) -> Void
    let test: () -> Void

    init(inputUpdated: @escaping (NagramSTTInputField, String) -> Void, test: @escaping () -> Void) {
        self.inputUpdated = inputUpdated
        self.test = test
    }
}

private enum NagramSTTSettingsEntry: ItemListNodeEntry {
    case header(section: Int32, text: String)
    case input(field: NagramSTTInputField, title: String, text: String, placeholder: String)
    case prompt(text: String, placeholder: String)
    case test(title: String)
    case footer(section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .footer(section, _):
            return section
        case .input:
            return 0
        case .prompt:
            return 1
        case .test:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 100
        case let .input(field, _, _, _):
            return 10 + field.rawValue
        case .prompt:
            return 110
        case .test:
            return 210
        case let .footer(section, _):
            return section * 100 + 90
        }
    }

    static func <(lhs: NagramSTTSettingsEntry, rhs: NagramSTTSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSTTSettingsArguments
        switch self {
        case let .header(section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .input(field, title, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: placeholder, type: field == .apiKey ? .password : .regular(capitalization: false, autocorrection: false), spacing: 8.0, clearType: .onFocus, sectionId: 0, textUpdated: { value in
                arguments.inputUpdated(field, value)
            }, action: {})
        case let .prompt(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: 1, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 100.0, maximalHeight: 240.0, textUpdated: { value in
                arguments.inputUpdated(.prompt, value)
            })
        case let .test(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: 2, style: .blocks, action: arguments.test)
        case let .footer(section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func nagramSTTSettingsErrorText(_ error: Error, language: String) -> String {
    if let error = error as? NagramSTTConfigurationError {
        return ngI18n(error.localizationKey, language)
    }
    if let error = error as? NagramSTTKeychainError {
        return "\(ngI18n("Nagram.STT.Error.Keychain", language)) (\(error.status))"
    }
    if let error = error as? NagramTranscriptionError {
        let key: String
        switch error {
        case .download:
            key = "Nagram.STT.Error.Download"
        case .invalidAudio:
            key = "Nagram.STT.Error.InvalidAudio"
        case .fileTooLarge:
            key = "Nagram.STT.Error.FileTooLarge"
        case .cancelled:
            key = "Nagram.STT.Error.Cancelled"
        case .timeout:
            key = "Nagram.STT.Error.Timeout"
        case .invalidResponse:
            key = "Nagram.STT.Error.InvalidResponse"
        case .noSpeech:
            key = "Nagram.STT.Error.NoSpeech"
        case .configuration, .http, .network:
            return error.localizedDescription
        }
        return ngI18n(key, language)
    }
    return error.localizedDescription
}

private func nagramSTTSettingsEntries(presentationData: PresentationData, apiKey: String, isTesting: Bool) -> [NagramSTTSettingsEntry] {
    let settings = NagramSettings.shared
    let lang = presentationData.strings.baseLanguageCode
    return [
        .header(section: 0, text: ngI18n("Nagram.STTSettings", lang)),
        .input(field: .baseURL, title: ngI18n("Nagram.STTBaseURL", lang), text: settings.sttBaseURL, placeholder: NagramSTTConfiguration.defaultBaseURL),
        .input(field: .endpoint, title: ngI18n("Nagram.STTEndpoint", lang), text: settings.sttEndpoint, placeholder: NagramSTTConfiguration.defaultEndpoint),
        .input(field: .apiKey, title: ngI18n("Nagram.STTAPIKey", lang), text: apiKey, placeholder: ngI18n("Nagram.STTAPIKey.Placeholder", lang)),
        .input(field: .model, title: ngI18n("Nagram.STTModel", lang), text: settings.sttModel, placeholder: "gpt-4o-mini-transcribe"),
        .input(field: .language, title: ngI18n("Nagram.STTLanguage", lang), text: settings.sttLanguage, placeholder: ngI18n("Nagram.STTLanguage.Placeholder", lang)),
        .footer(section: 0, text: ngI18n("Nagram.STTSettings.Footer", lang)),
        .header(section: 1, text: ngI18n("Nagram.STTPrompt", lang)),
        .prompt(text: settings.sttPrompt, placeholder: ngI18n("Nagram.STTPrompt.Placeholder", lang)),
        .footer(section: 1, text: ngI18n("Nagram.STTPrompt.Footer", lang)),
        .test(title: ngI18n(isTesting ? "Nagram.STT.Cancel" : "Nagram.STTTest", lang)),
        .footer(section: 2, text: ngI18n("Nagram.STTTest.Footer", lang))
    ]
}

public func nagramSTTSettingsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let testDisposable = MetaDisposable()
    var isTesting = false
    var apiKey = NagramSettings.shared.sttAPIKey
    var credentialSaveError: Error?
    var presentControllerImpl: ((ViewController) -> Void)?
    let presentResult: (String, String) -> Void = { titleKey, text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: ngI18n(titleKey, presentationData.strings.baseLanguageCode), text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]))
    }
    let presentError: (String, Error) -> Void = { titleKey, error in
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        presentResult(titleKey, nagramSTTSettingsErrorText(error, language: lang))
    }

    let arguments = NagramSTTSettingsArguments(inputUpdated: { field, value in
        let settings = NagramSettings.shared
        switch field {
        case .baseURL:
            settings.sttBaseURL = value
        case .endpoint:
            settings.sttEndpoint = value
        case .apiKey:
            apiKey = value
            do {
                try settings.setSTTAPIKey(value)
                credentialSaveError = nil
            } catch {
                if credentialSaveError == nil {
                    presentError("Nagram.STTSaveFailed", error)
                }
                credentialSaveError = error
            }
        case .model:
            settings.sttModel = value
        case .language:
            settings.sttLanguage = value
        case .prompt:
            settings.sttPrompt = value
        }
    }, test: {
        if isTesting {
            testDisposable.set(nil)
            isTesting = false
            bump()
            return
        }
        if credentialSaveError != nil {
            do {
                try NagramSettings.shared.setSTTAPIKey(apiKey)
                credentialSaveError = nil
            } catch {
                credentialSaveError = error
                presentError("Nagram.STTSaveFailed", error)
                return
            }
        }
        let configuration: NagramSTTConfiguration
        do {
            configuration = try NagramSTTConfiguration.current()
        } catch {
            presentError("Nagram.STTTestFailed", error)
            return
        }
        isTesting = true
        bump()
        testDisposable.set((NagramTranscriptionService.shared.test(configuration: configuration)
        |> deliverOnMainQueue).start(next: { text in
            isTesting = false
            bump()
            presentResult("Nagram.STTTestSucceeded", text)
        }, error: { error in
            isTesting = false
            bump()
            presentError("Nagram.STTTestFailed", error)
        }))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.STTSettings", presentationData.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: nagramSTTSettingsEntries(presentationData: presentationData, apiKey: apiKey, isTesting: isTesting), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        testDisposable.dispose()
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root), with: nil)
    }
    return controller
}
