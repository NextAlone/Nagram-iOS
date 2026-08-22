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

// MARK: NAGRAM — Session backup and restore screen.
//
// Sessions travel as Pyrogram session strings, the same representation
// iebb/mithka exports and imports, so a session moves between the two apps in
// either direction. Keychain backups additionally follow the user's own devices
// through iCloud Keychain.

private final class NagramSessionBackupArguments {
    let copySessionString: () -> Void
    let backUp: (NagramSessionBackupStorage) -> Void
    let importUpdated: (String) -> Void
    let pasteFromClipboard: () -> Void
    let importSession: () -> Void
    let openBackup: (NagramSessionBackupRecord) -> Void
    let deleteAll: () -> Void

    init(copySessionString: @escaping () -> Void, backUp: @escaping (NagramSessionBackupStorage) -> Void, importUpdated: @escaping (String) -> Void, pasteFromClipboard: @escaping () -> Void, importSession: @escaping () -> Void, openBackup: @escaping (NagramSessionBackupRecord) -> Void, deleteAll: @escaping () -> Void) {
        self.copySessionString = copySessionString
        self.backUp = backUp
        self.importUpdated = importUpdated
        self.pasteFromClipboard = pasteFromClipboard
        self.importSession = importSession
        self.openBackup = openBackup
        self.deleteAll = deleteAll
    }
}

private enum NagramSessionBackupSection: Int32 {
    case current
    case importSession
    case backups
}

private enum NagramSessionBackupEntryStableId: Hashable {
    case header(Int32)
    case footer(Int32)
    case copySessionString
    case backUp(String)
    case importInput
    case importPaste
    case importAction
    case backup(String)
    case deleteAll
}

private enum NagramSessionBackupEntry: ItemListNodeEntry {
    case header(section: Int32, text: String)
    case footer(section: Int32, text: String)
    case copySessionString(title: String, isEnabled: Bool)
    case backUp(storage: NagramSessionBackupStorage, title: String, isEnabled: Bool)
    case importInput(text: String, placeholder: String)
    case importPaste(title: String)
    case importAction(title: String, isEnabled: Bool)
    case backupItem(index: Int32, record: NagramSessionBackupRecord, detail: String)
    case deleteAll(title: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .footer(section, _):
            return ItemListSectionId(section)
        case .copySessionString, .backUp:
            return ItemListSectionId(NagramSessionBackupSection.current.rawValue)
        case .importInput, .importPaste, .importAction:
            return ItemListSectionId(NagramSessionBackupSection.importSession.rawValue)
        case .backupItem, .deleteAll:
            return ItemListSectionId(NagramSessionBackupSection.backups.rawValue)
        }
    }

    var stableId: NagramSessionBackupEntryStableId {
        switch self {
        case let .header(section, _):
            return .header(section)
        case let .footer(section, _):
            return .footer(section)
        case .copySessionString:
            return .copySessionString
        case let .backUp(storage, _, _):
            return .backUp(storage.rawValue)
        case .importInput:
            return .importInput
        case .importPaste:
            return .importPaste
        case .importAction:
            return .importAction
        case let .backupItem(_, record, _):
            return .backup("\(record.storage.rawValue):\(record.accountId)")
        case .deleteAll:
            return .deleteAll
        }
    }

    var sortIndex: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .footer(section, _):
            return section * 1000 + 900
        case .copySessionString:
            return NagramSessionBackupSection.current.rawValue * 1000 + 10
        case let .backUp(storage, _, _):
            return NagramSessionBackupSection.current.rawValue * 1000 + 20 + Int32(storage == .synced ? 0 : 1)
        case .importInput:
            return NagramSessionBackupSection.importSession.rawValue * 1000 + 10
        case .importPaste:
            return NagramSessionBackupSection.importSession.rawValue * 1000 + 20
        case .importAction:
            return NagramSessionBackupSection.importSession.rawValue * 1000 + 30
        case let .backupItem(index, _, _):
            return NagramSessionBackupSection.backups.rawValue * 1000 + 10 + index
        case .deleteAll:
            return NagramSessionBackupSection.backups.rawValue * 1000 + 800
        }
    }

    static func ==(lhs: NagramSessionBackupEntry, rhs: NagramSessionBackupEntry) -> Bool {
        switch lhs {
        case let .header(lSection, lText):
            if case let .header(rSection, rText) = rhs { return lSection == rSection && lText == rText }
            return false
        case let .footer(lSection, lText):
            if case let .footer(rSection, rText) = rhs { return lSection == rSection && lText == rText }
            return false
        case let .copySessionString(lTitle, lEnabled):
            if case let .copySessionString(rTitle, rEnabled) = rhs { return lTitle == rTitle && lEnabled == rEnabled }
            return false
        case let .backUp(lStorage, lTitle, lEnabled):
            if case let .backUp(rStorage, rTitle, rEnabled) = rhs { return lStorage == rStorage && lTitle == rTitle && lEnabled == rEnabled }
            return false
        case let .importInput(lText, lPlaceholder):
            if case let .importInput(rText, rPlaceholder) = rhs { return lText == rText && lPlaceholder == rPlaceholder }
            return false
        case let .importPaste(lTitle):
            if case let .importPaste(rTitle) = rhs { return lTitle == rTitle }
            return false
        case let .importAction(lTitle, lEnabled):
            if case let .importAction(rTitle, rEnabled) = rhs { return lTitle == rTitle && lEnabled == rEnabled }
            return false
        case let .backupItem(lIndex, lRecord, lDetail):
            if case let .backupItem(rIndex, rRecord, rDetail) = rhs { return lIndex == rIndex && lRecord == rRecord && lDetail == rDetail }
            return false
        case let .deleteAll(lTitle):
            if case let .deleteAll(rTitle) = rhs { return lTitle == rTitle }
            return false
        }
    }

    static func <(lhs: NagramSessionBackupEntry, rhs: NagramSessionBackupEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSessionBackupArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .copySessionString(title, isEnabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: isEnabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copySessionString()
            })
        case let .backUp(storage, title, isEnabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: isEnabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.backUp(storage)
            })
        case let .importInput(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .default, minimalHeight: 96.0, textUpdated: { value in
                arguments.importUpdated(value)
            }, action: {})
        case let .importPaste(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.pasteFromClipboard()
            })
        case let .importAction(title, isEnabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: isEnabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importSession()
            })
        case let .backupItem(_, record, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: record.displayName, label: detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: {
                arguments.openBackup(record)
            })
        case let .deleteAll(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.deleteAll()
            })
        }
    }
}

private func nagramSessionBackupEntries(presentationData: PresentationData, records: [NagramSessionBackupRecord], importText: String, isWorking: Bool) -> [NagramSessionBackupEntry] {
    let lang = presentationData.strings.baseLanguageCode
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short

    var entries: [NagramSessionBackupEntry] = []

    entries.append(.header(section: NagramSessionBackupSection.current.rawValue, text: ngI18n("Nagram.SessionBackup.Current", lang)))
    entries.append(.copySessionString(title: ngI18n("Nagram.SessionBackup.CopySessionString", lang), isEnabled: !isWorking))
    entries.append(.backUp(storage: .synced, title: ngI18n("Nagram.SessionBackup.BackUpSynced", lang), isEnabled: !isWorking))
    entries.append(.backUp(storage: .local, title: ngI18n("Nagram.SessionBackup.BackUpLocal", lang), isEnabled: !isWorking))
    entries.append(.footer(section: NagramSessionBackupSection.current.rawValue, text: ngI18n("Nagram.SessionBackup.Current.Footer", lang)))

    entries.append(.header(section: NagramSessionBackupSection.importSession.rawValue, text: ngI18n("Nagram.SessionBackup.Import", lang)))
    entries.append(.importInput(text: importText, placeholder: ngI18n("Nagram.SessionBackup.Import.Placeholder", lang)))
    entries.append(.importPaste(title: ngI18n("Nagram.SessionBackup.Import.Paste", lang)))
    entries.append(.importAction(title: ngI18n("Nagram.SessionBackup.Import.Action", lang), isEnabled: !isWorking && !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    entries.append(.footer(section: NagramSessionBackupSection.importSession.rawValue, text: ngI18n("Nagram.SessionBackup.Import.Footer", lang)))

    entries.append(.header(section: NagramSessionBackupSection.backups.rawValue, text: ngI18n("Nagram.SessionBackup.Saved", lang)))
    if records.isEmpty {
        entries.append(.footer(section: NagramSessionBackupSection.backups.rawValue, text: ngI18n("Nagram.SessionBackup.Saved.Empty", lang)))
    } else {
        for (index, record) in records.enumerated() {
            let storageKey = record.storage == .synced ? "Nagram.SessionBackup.Storage.Synced" : "Nagram.SessionBackup.Storage.Local"
            var detail = ngI18n(storageKey, lang)
            if let phone = record.phone, !phone.isEmpty {
                detail = "\(phone) · \(detail)"
            }
            detail = "\(detail)\n\(dateFormatter.string(from: record.createdAt))"
            entries.append(.backupItem(index: Int32(index), record: record, detail: detail))
        }
        entries.append(.deleteAll(title: ngI18n("Nagram.SessionBackup.DeleteAll", lang)))
        entries.append(.footer(section: NagramSessionBackupSection.backups.rawValue, text: ngI18n("Nagram.SessionBackup.Saved.Footer", lang)))
    }

    return entries
}

public func nagramSessionBackupController(context: AccountContext) -> ViewController {
    let keychain = NagramSessionBackupKeychain.shared
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var records: [NagramSessionBackupRecord] = keychain.allRecords()
    var importText = ""
    var isWorking = false

    let exportDisposable = MetaDisposable()
    let importDisposable = MetaDisposable()

    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var dismissInputImpl: (() -> Void)?

    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let reload: () -> Void = {
        records = keychain.allRecords()
        bump()
    }
    let presentAlert: (String, String) -> Void = { title, text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]), nil)
    }
    let presentError: (String, Error) -> Void = { title, error in
        presentAlert(title, "\(error)")
    }
    let confirm: (String, String, String, @escaping () -> Void) -> Void = { title, text, confirmTitle, action in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: confirmTitle, action: {
                action()
            })
        ]), nil)
    }

    let arguments = NagramSessionBackupArguments(copySessionString: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        confirm(ngI18n("Nagram.SessionBackup.CopySessionString", lang), ngI18n("Nagram.SessionBackup.CopySessionString.Warning", lang), ngI18n("Nagram.SessionBackup.CopySessionString.Confirm", lang), {
            if isWorking {
                return
            }
            isWorking = true
            bump()
            exportDisposable.set((nagramExportActiveSessionRecord(context: context)
            |> deliverOnMainQueue).start(next: { record in
                isWorking = false
                bump()
                UIPasteboard.general.string = record.sessionString
                presentAlert(ngI18n("Nagram.SessionBackup.CopySessionString", lang), ngI18n("Nagram.SessionBackup.Copied", lang))
            }, error: { error in
                isWorking = false
                bump()
                presentError(ngI18n("Nagram.SessionBackup.CopySessionString", lang), error)
            }))
        })
    }, backUp: { storage in
        if isWorking {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        isWorking = true
        bump()
        exportDisposable.set((nagramExportActiveSessionRecord(context: context, storage: storage)
        |> deliverOnMainQueue).start(next: { record in
            isWorking = false
            do {
                try keychain.save(record)
                reload()
                presentAlert(ngI18n("Nagram.SessionBackup.Title", lang), ngI18n("Nagram.SessionBackup.SaveSucceeded", lang))
            } catch {
                bump()
                presentError(ngI18n("Nagram.SessionBackup.Title", lang), error)
            }
        }, error: { error in
            isWorking = false
            bump()
            presentError(ngI18n("Nagram.SessionBackup.Title", lang), error)
        }))
    }, importUpdated: { value in
        importText = value
        bump()
    }, pasteFromClipboard: {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return
        }
        importText = text
        bump()
    }, importSession: {
        if isWorking {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let sessionString = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        if sessionString.isEmpty {
            return
        }
        dismissInputImpl?()
        confirm(ngI18n("Nagram.SessionBackup.Import.Action", lang), ngI18n("Nagram.SessionBackup.Import.Warning", lang), ngI18n("Nagram.SessionBackup.Import.Confirm", lang), {
            isWorking = true
            bump()
            importDisposable.set((nagramImportSessionString(sharedContext: context.sharedContext, sessionString: sessionString)
            |> deliverOnMainQueue).start(next: { recordId in
                isWorking = false
                importText = ""
                bump()
                context.sharedContext.switchToAccount(id: recordId, fromSettingsController: nil, withChatListController: nil)
            }, error: { error in
                isWorking = false
                bump()
                presentError(ngI18n("Nagram.SessionBackup.Import.Action", lang), error)
            }))
        })
    }, openBackup: { record in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let dismissAction: () -> Void = { [weak actionSheet] in
            actionSheet?.dismissAnimated()
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: record.displayName),
                ActionSheetButtonItem(title: ngI18n("Nagram.SessionBackup.Restore", lang), color: .accent, action: {
                    dismissAction()
                    if isWorking {
                        return
                    }
                    isWorking = true
                    bump()
                    importDisposable.set((nagramRestoreBackupRecord(sharedContext: context.sharedContext, record: record)
                    |> deliverOnMainQueue).start(next: { recordId in
                        isWorking = false
                        bump()
                        context.sharedContext.switchToAccount(id: recordId, fromSettingsController: nil, withChatListController: nil)
                    }, error: { error in
                        isWorking = false
                        bump()
                        presentError(ngI18n("Nagram.SessionBackup.Restore", lang), error)
                    }))
                }),
                ActionSheetButtonItem(title: ngI18n("Nagram.SessionBackup.CopySessionString", lang), color: .accent, action: {
                    dismissAction()
                    UIPasteboard.general.string = record.sessionString
                    presentAlert(ngI18n("Nagram.SessionBackup.CopySessionString", lang), ngI18n("Nagram.SessionBackup.Copied", lang))
                }),
                ActionSheetButtonItem(title: ngI18n("Nagram.SessionBackup.Delete", lang), color: .destructive, action: {
                    dismissAction()
                    do {
                        try keychain.delete(accountId: record.accountId, storage: record.storage)
                        reload()
                    } catch {
                        presentError(ngI18n("Nagram.SessionBackup.Delete", lang), error)
                    }
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { dismissAction() })
            ])
        ])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, deleteAll: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        confirm(ngI18n("Nagram.SessionBackup.DeleteAll", lang), ngI18n("Nagram.SessionBackup.DeleteAll.Warning", lang), ngI18n("Nagram.SessionBackup.Delete", lang), {
            do {
                try keychain.deleteAll()
                reload()
            } catch {
                presentError(ngI18n("Nagram.SessionBackup.DeleteAll", lang), error)
            }
        })
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries = nagramSessionBackupEntries(presentationData: presentationData, records: records, importText: importText, isWorking: isWorking)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.SessionBackup.Title", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        exportDisposable.dispose()
        importDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentControllerImpl = { [weak controller] c, presentationArguments in
        controller?.present(c, in: .window(.root), with: presentationArguments)
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    return controller
}
