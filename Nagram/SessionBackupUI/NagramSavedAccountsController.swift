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

// MARK: NAGRAM — 从钥匙串里挑一个尚未登录的账号。
//
// Accounts backed up from this app are kept in the keychain and follow the
// user's devices through iCloud Keychain. This lists the ones that are not
// signed in here so a fresh device can pick one instead of retyping a phone
// number.

private final class NagramSavedAccountsArguments {
    let select: (NagramSessionBackupRecord) -> Void

    init(select: @escaping (NagramSessionBackupRecord) -> Void) {
        self.select = select
    }
}

private enum NagramSavedAccountsEntryStableId: Hashable {
    case header
    case footer
    case progress
    case account(String)
}

private enum NagramSavedAccountsEntry: ItemListNodeEntry {
    case header(text: String)
    case footer(text: String)
    case progress(text: String, activity: Bool)
    case account(index: Int32, record: NagramSessionBackupRecord, detail: String, isEnabled: Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: NagramSavedAccountsEntryStableId {
        switch self {
        case .header:
            return .header
        case .footer:
            return .footer
        case .progress:
            return .progress
        case let .account(_, record, _, _):
            return .account("\(record.storage.rawValue):\(record.accountId)")
        }
    }

    var sortIndex: Int32 {
        switch self {
        case .header:
            return 0
        case let .account(index, _, _, _):
            return 10 + index
        case .progress:
            return 900
        case .footer:
            return 901
        }
    }

    static func ==(lhs: NagramSavedAccountsEntry, rhs: NagramSavedAccountsEntry) -> Bool {
        switch lhs {
        case let .header(lText):
            if case let .header(rText) = rhs { return lText == rText }
            return false
        case let .footer(lText):
            if case let .footer(rText) = rhs { return lText == rText }
            return false
        case let .progress(lText, lActivity):
            if case let .progress(rText, rActivity) = rhs { return lText == rText && lActivity == rActivity }
            return false
        case let .account(lIndex, lRecord, lDetail, lEnabled):
            if case let .account(rIndex, rRecord, rDetail, rEnabled) = rhs {
                return lIndex == rIndex && lRecord == rRecord && lDetail == rDetail && lEnabled == rEnabled
            }
            return false
        }
    }

    static func <(lhs: NagramSavedAccountsEntry, rhs: NagramSavedAccountsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! NagramSavedAccountsArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .progress(text, activity):
            return ItemListActivityTextItem(displayActivity: activity, presentationData: presentationData, text: text, color: .generic, sectionId: self.section)
        case let .account(_, record, detail, isEnabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: record.displayName, enabled: isEnabled, label: detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: {
                arguments.select(record)
            })
        }
    }
}

public func nagramSavedAccountsController(sharedContext: SharedAccountContext, presentationData: PresentationData) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var records: [NagramSessionBackupRecord] = []
    var hasLoadedRecords = false
    var isWorking = false
    var statusText: String?

    let disposable = MetaDisposable()
    let loadDisposable = MetaDisposable()
    var presentControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    let language = presentationData.strings.baseLanguageCode
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .short

    let arguments = NagramSavedAccountsArguments(select: { record in
        if isWorking {
            return
        }
        presentControllerImpl?(textAlertController(sharedContext: sharedContext, title: record.displayName, text: ngI18n("Nagram.SavedAccounts.Confirm", language), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: ngI18n("Nagram.SessionBackup.Restore", language), action: {
                isWorking = true
                statusText = ngI18n("Nagram.SessionBackup.Import.Progress.Adding", language)
                bump()
                disposable.set((nagramRestoreBackupRecord(sharedContext: sharedContext, record: record, makeCurrent: true, progress: { stage in
                    Queue.mainQueue().async {
                        switch stage {
                        case .addingAccount:
                            statusText = ngI18n("Nagram.SessionBackup.Import.Progress.Adding", language)
                        case .checkingDatacenter:
                            statusText = ngI18n("Nagram.SessionBackup.Import.Progress.Checking", language)
                        case let .movingToDatacenter(datacenterId):
                            statusText = String(format: ngI18n("Nagram.SessionBackup.Import.Progress.Moving", language), "\(datacenterId)")
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
                    presentControllerImpl?(textAlertController(sharedContext: sharedContext, title: ngI18n("Nagram.SavedAccounts.Title", language), text: "\(error)", actions: [
                        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                    ]))
                }))
            })
        ]))
    })

    loadDisposable.set((nagramRestorableBackups(sharedContext: sharedContext)
    |> deliverOnMainQueue).start(next: { loaded in
        records = loaded
        hasLoadedRecords = true
        bump()
    }))

    let signal = combineLatest(queue: .mainQueue(),
        sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, NagramSavedAccountsArguments)) in
        let language = presentationData.strings.baseLanguageCode
        var entries: [NagramSavedAccountsEntry] = []
        entries.append(.header(text: ngI18n("Nagram.SavedAccounts.Header", language)))
        for (index, record) in records.enumerated() {
            let storageKey = record.storage == .synced ? "Nagram.SessionBackup.Storage.Synced" : "Nagram.SessionBackup.Storage.Local"
            var detail = ngI18n(storageKey, language)
            if let phone = record.phone, !phone.isEmpty {
                detail = "\(phone) · \(detail)"
            }
            detail = "\(detail)\n\(dateFormatter.string(from: record.createdAt))"
            entries.append(.account(index: Int32(index), record: record, detail: detail, isEnabled: !isWorking))
        }
        if let statusText {
            entries.append(.progress(text: statusText, activity: true))
        } else if !hasLoadedRecords {
            entries.append(.progress(text: ngI18n("Nagram.SavedAccounts.Loading", language), activity: true))
        } else if records.isEmpty {
            entries.append(.progress(text: ngI18n("Nagram.SavedAccounts.Empty", language), activity: false))
        }
        entries.append(.footer(text: ngI18n("Nagram.SavedAccounts.Footer", language)))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ngI18n("Nagram.SavedAccounts.Title", language)),
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
        disposable.dispose()
        loadDisposable.dispose()
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
    return controller
}
