import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSessionBackup
import NagramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

// MARK: NAGRAM — Session import for first launch.
//
// The settings screen needs an authorized account, which does not exist yet on
// a fresh install. This screen is the login-time counterpart: it only imports,
// it takes a SharedAccountContext instead of an AccountContext, and it builds
// on `ItemListController`'s context-free initializer.
//
// A successful import marks the new record current and clears the pending
// unauthorized account, so the login flow finishes on its own.

private final class NagramSessionImportArguments {
    let textUpdated: (String) -> Void
    let pasteFromClipboard: () -> Void
    let importSession: () -> Void
    let restore: (NagramSessionBackupRecord) -> Void

    init(textUpdated: @escaping (String) -> Void, pasteFromClipboard: @escaping () -> Void, importSession: @escaping () -> Void, restore: @escaping (NagramSessionBackupRecord) -> Void) {
        self.textUpdated = textUpdated
        self.pasteFromClipboard = pasteFromClipboard
        self.importSession = importSession
        self.restore = restore
    }
}

private enum NagramSessionImportSection: Int32 {
    case importSession
    case backups
}

private enum NagramSessionImportEntryStableId: Hashable {
    case header(Int32)
    case footer(Int32)
    case input
    case paste
    case action
    case progress
    case backup(String)
}

private enum NagramSessionImportEntry: ItemListNodeEntry {
    case header(section: Int32, text: String)
    case footer(section: Int32, text: String)
    case input(text: String, placeholder: String)
    case paste(title: String)
    case action(title: String, isEnabled: Bool)
    case progress(text: String)
    case backup(index: Int32, record: NagramSessionBackupRecord, detail: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .footer(section, _):
            return ItemListSectionId(section)
        case .input, .paste, .action, .progress:
            return ItemListSectionId(NagramSessionImportSection.importSession.rawValue)
        case .backup:
            return ItemListSectionId(NagramSessionImportSection.backups.rawValue)
        }
    }

    var stableId: NagramSessionImportEntryStableId {
        switch self {
        case let .header(section, _):
            return .header(section)
        case let .footer(section, _):
            return .footer(section)
        case .input:
            return .input
        case .paste:
            return .paste
        case .action:
            return .action
        case .progress:
            return .progress
        case let .backup(_, record, _):
            return .backup("\(record.storage.rawValue):\(record.accountId)")
        }
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .footer(section, _):
            return section * 1000 + 900
        case .input:
            return NagramSessionImportSection.importSession.rawValue * 1000 + 10
        case .paste:
            return NagramSessionImportSection.importSession.rawValue * 1000 + 20
        case .action:
            return NagramSessionImportSection.importSession.rawValue * 1000 + 30
        case .progress:
            return NagramSessionImportSection.importSession.rawValue * 1000 + 40
        case let .backup(index, _, _):
            return NagramSessionImportSection.backups.rawValue * 1000 + 10 + index
        }
    }

    static func ==(lhs: NagramSessionImportEntry, rhs: NagramSessionImportEntry) -> Bool {
        switch lhs {
        case let .header(lSection, lText):
            if case let .header(rSection, rText) = rhs { return lSection == rSection && lText == rText }
            return false
        case let .footer(lSection, lText):
            if case let .footer(rSection, rText) = rhs { return lSection == rSection && lText == rText }
            return false
        case let .input(lText, lPlaceholder):
            if case let .input(rText, rPlaceholder) = rhs { return lText == rText && lPlaceholder == rPlaceholder }
            return false
        case let .paste(lTitle):
            if case let .paste(rTitle) = rhs { return lTitle == rTitle }
            return false
        case let .action(lTitle, lEnabled):
            if case let .action(rTitle, rEnabled) = rhs { return lTitle == rTitle && lEnabled == rEnabled }
            return false
        case let .progress(lText):
            if case let .progress(rText) = rhs { return lText == rText }
            return false
        case let .backup(lIndex, lRecord, lDetail):
            if case let .backup(rIndex, rRecord, rDetail) = rhs { return lIndex == rIndex && lRecord == rRecord && lDetail == rDetail }
            return false
        }
    }

    static func <(lhs: NagramSessionImportEntry, rhs: NagramSessionImportEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSessionImportArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .input(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 96.0, textUpdated: { value in
                arguments.textUpdated(value)
            })
        case let .paste(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.pasteFromClipboard()
            })
        case let .action(title, isEnabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: isEnabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importSession()
            })
        case let .progress(text):
            return ItemListActivityTextItem(displayActivity: true, presentationData: presentationData, text: text, color: .generic, sectionId: self.section)
        case let .backup(_, record, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: record.displayName, label: detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: {
                arguments.restore(record)
            })
        }
    }
}

private func nagramSessionImportEntries(lang: String, records: [NagramSessionBackupRecord], text: String, isWorking: Bool, statusText: String?) -> [NagramSessionImportEntry] {
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short

    var entries: [NagramSessionImportEntry] = []
    entries.append(.header(section: NagramSessionImportSection.importSession.rawValue, text: ngI18n("Nagram.SessionBackup.Import", lang)))
    entries.append(.input(text: text, placeholder: ngI18n("Nagram.SessionBackup.Import.Placeholder", lang)))
    entries.append(.paste(title: ngI18n("Nagram.SessionBackup.Import.Paste", lang)))
    entries.append(.action(title: ngI18n("Nagram.SessionBackup.Import.Action", lang), isEnabled: !isWorking && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    if let statusText {
        entries.append(.progress(text: statusText))
    }
    entries.append(.footer(section: NagramSessionImportSection.importSession.rawValue, text: ngI18n("Nagram.SessionBackup.Import.Footer", lang)))

    if !records.isEmpty {
        entries.append(.header(section: NagramSessionImportSection.backups.rawValue, text: ngI18n("Nagram.SessionBackup.Saved", lang)))
        for (index, record) in records.enumerated() {
            let storageKey = record.storage == .synced ? "Nagram.SessionBackup.Storage.Synced" : "Nagram.SessionBackup.Storage.Local"
            var detail = ngI18n(storageKey, lang)
            if let phone = record.phone, !phone.isEmpty {
                detail = "\(phone) · \(detail)"
            }
            detail = "\(detail)\n\(dateFormatter.string(from: record.createdAt))"
            entries.append(.backup(index: Int32(index), record: record, detail: detail))
        }
        entries.append(.footer(section: NagramSessionImportSection.backups.rawValue, text: ngI18n("Nagram.SessionBackup.Saved.RestoreFooter", lang)))
    }
    return entries
}

public func nagramSessionImportController(sharedContext: SharedAccountContext, presentationData: PresentationData) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    // Loaded asynchronously: a synchronizable keychain query can block, and
    // this screen is built on the main thread.
    var records: [NagramSessionBackupRecord] = []
    var text = ""
    var isWorking = false
    var statusText: String?

    let importDisposable = MetaDisposable()
    let recordsDisposable = MetaDisposable()
    var presentControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var dismissInputImpl: (() -> Void)?

    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let lang = presentationData.strings.baseLanguageCode
    recordsDisposable.set((nagramRestorableBackups(sharedContext: sharedContext)
    |> deliverOnMainQueue).start(next: { loaded in
        records = loaded
        bump()
    }))
    let presentError: (Error) -> Void = { error in
        presentControllerImpl?(textAlertController(sharedContext: sharedContext, title: ngI18n("Nagram.SessionBackup.Import.Action", lang), text: "\(error)", actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]))
    }
    // A successful import makes the record current, so the login flow unwinds by
    // itself; the screen only needs to close.
    let beginImport: (String) -> Void = { sessionString in
        if isWorking {
            return
        }
        isWorking = true
        statusText = ngI18n("Nagram.SessionBackup.Import.Progress.Adding", lang)
        bump()
        importDisposable.set((nagramImportSessionString(sharedContext: sharedContext, sessionString: sessionString, makeCurrent: true, progress: { stage in
            Queue.mainQueue().async {
                switch stage {
                case .addingAccount:
                    statusText = ngI18n("Nagram.SessionBackup.Import.Progress.Adding", lang)
                case .checkingDatacenter:
                    statusText = ngI18n("Nagram.SessionBackup.Import.Progress.Checking", lang)
                case let .movingToDatacenter(datacenterId):
                    statusText = String(format: ngI18n("Nagram.SessionBackup.Import.Progress.Moving", lang), "\(datacenterId)")
                }
                bump()
            }
        })
        |> deliverOnMainQueue).start(next: { _ in
            isWorking = false
            statusText = nil
            bump()
            dismissImpl?()
        }, error: { error in
            isWorking = false
            statusText = nil
            bump()
            presentError(error)
        }))
    }
    let confirmThenImport: (String) -> Void = { sessionString in
        presentControllerImpl?(textAlertController(sharedContext: sharedContext, title: ngI18n("Nagram.SessionBackup.Import.Action", lang), text: ngI18n("Nagram.SessionBackup.Import.Warning", lang), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: ngI18n("Nagram.SessionBackup.Import.Confirm", lang), action: {
                beginImport(sessionString)
            })
        ]))
    }

    let arguments = NagramSessionImportArguments(textUpdated: { value in
        text = value
        bump()
    }, pasteFromClipboard: {
        guard let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pasted.isEmpty else {
            return
        }
        text = pasted
        bump()
    }, importSession: {
        let sessionString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if sessionString.isEmpty {
            return
        }
        dismissInputImpl?()
        confirmThenImport(sessionString)
    }, restore: { record in
        dismissInputImpl?()
        confirmThenImport(record.sessionString)
    })

    let signal = combineLatest(queue: .mainQueue(),
        sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, NagramSessionImportArguments)) in
        let entries = nagramSessionImportEntries(lang: presentationData.strings.baseLanguageCode, records: records, text: text, isWorking: isWorking, statusText: statusText)
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.SessionBackup.Import", presentationData.strings.baseLanguageCode)),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            }),
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        importDisposable.dispose()
        recordsDisposable.dispose()
    }

    let controller = ItemListController(
        presentationData: ItemListPresentationData(presentationData),
        updatedPresentationData: sharedContext.presentationData |> map { ItemListPresentationData($0) },
        state: signal,
        tabBarItem: nil
    )
    controller.navigationPresentation = .modal
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    return controller
}
