import AccountContext
import Foundation
import MtProtoKit
import NagramSessionBackup
import Postbox
import SwiftSignalKit
import TelegramCore

// MARK: NAGRAM — Bridges Pyrogram session strings to Telegram's account storage.
//
// Export reads the master datacenter auth key that upstream already keeps for
// its own account backups (`accountBackupData`). Import feeds the key back in
// through `AccountBackupData`, the same path upstream uses to rebuild an
// account record, so no MTProto internals are re-implemented here.
//
// The api_id carried by an imported session string is deliberately not adopted:
// an MTProto auth key is bound to its datacenter, not to an api_id, and this app
// always connects with its own `BuildConfig.apiId`. Exported strings therefore
// carry Nagram's api_id, and imported ones keep running under it.

public enum NagramSessionBackupServiceError: Error, CustomStringConvertible {
    case noSessionData
    case invalidAuthKey(Int)
    case invalidSessionString(String)
    case alreadyLoggedIn(Int64)

    public var description: String {
        switch self {
        case .noSessionData:
            return "This account has no exportable authorization key yet."
        case let .invalidAuthKey(size):
            return "The stored authorization key is \(size) bytes, but \(PyrogramSessionString.authKeySize) bytes are required."
        case let .invalidSessionString(message):
            return message
        case let .alreadyLoggedIn(userId):
            return "User \(userId) is already signed in on this device."
        }
    }
}

// The Pyrogram format does not carry the auth key id, so it is recomputed from
// the key on import using MTProto's own SHA1 helper.
public func nagramAuthKeyId(authKey: Data) -> Int64 {
    return PyrogramSessionString.authKeyId(sha1Digest: MTSha1(authKey))
}

public func nagramExportActiveSessionRecord(context: AccountContext, storage: NagramSessionBackupStorage = .synced) -> Signal<NagramSessionBackupRecord, NagramSessionBackupServiceError> {
    let account = context.account
    let identity = account.postbox.transaction { transaction -> (String, String?) in
        guard let user = transaction.getPeer(account.peerId) as? TelegramUser else {
            return ("", nil)
        }
        return (user.debugDisplayTitle, user.phone)
    }

    return combineLatest(accountBackupData(postbox: account.postbox), identity)
    |> castError(NagramSessionBackupServiceError.self)
    |> mapToSignal { backupData, identity -> Signal<NagramSessionBackupRecord, NagramSessionBackupServiceError> in
        guard let backupData else {
            return .fail(.noSessionData)
        }
        if backupData.masterDatacenterKey.count != PyrogramSessionString.authKeySize {
            return .fail(.invalidAuthKey(backupData.masterDatacenterKey.count))
        }
        let userId = account.peerId.id._internalGetInt64Value()
        let session = PyrogramSessionString(
            dcId: backupData.masterDatacenterId,
            apiId: account.networkArguments.apiId,
            testMode: account.testingEnvironment,
            authKey: backupData.masterDatacenterKey,
            userId: userId,
            isBot: false
        )
        do {
            let sessionString = try session.encoded()
            let name = identity.0.isEmpty ? "\(userId)" : identity.0
            return .single(NagramSessionBackupRecord(
                accountId: "\(userId)",
                userId: userId,
                name: name,
                phone: identity.1,
                createdAt: Date(),
                storage: storage,
                sessionString: sessionString
            ))
        } catch {
            return .fail(.invalidSessionString("\(error)"))
        }
    }
}

// Import only needs the shared context, so it also works before any account
// exists — that is what makes it reachable from the login screen on a fresh
// install.
// `makeCurrent` mirrors what upstream does when a phone login completes: it
// marks the new record current and clears the pending unauthorized account, so
// the login flow ends by itself. Adding an account from settings passes false
// and switches through `switchToAccount` instead.
public func nagramImportSessionString(sharedContext: SharedAccountContext, sessionString: String, makeCurrent: Bool = false) -> Signal<AccountRecordId, NagramSessionBackupServiceError> {
    let session: PyrogramSessionString
    do {
        session = try PyrogramSessionString(decoding: sessionString)
    } catch {
        return .fail(.invalidSessionString("\(error)"))
    }

    let accountManager = sharedContext.accountManager
    return sharedContext.activeAccountContexts
    |> take(1)
    |> castError(NagramSessionBackupServiceError.self)
    |> mapToSignal { _, accounts, _ -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
        let signedInUserIds = accounts.map { $0.1.account.peerId.id._internalGetInt64Value() }
        if signedInUserIds.contains(session.userId) {
            return .fail(.alreadyLoggedIn(session.userId))
        }

        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(session.userId))
        let backupData = AccountBackupData(
            masterDatacenterId: session.dcId,
            peerId: peerId.toInt64(),
            masterDatacenterKey: session.authKey,
            masterDatacenterKeyId: nagramAuthKeyId(authKey: session.authKey),
            notificationEncryptionKeyId: nil,
            notificationEncryptionKey: nil,
            additionalDatacenterKeys: [:]
        )

        return accountManager.transaction { transaction -> AccountRecordId in
            var attributes: [TelegramAccountManagerTypes.Attribute] = [
                .backupData(AccountBackupDataAttribute(data: backupData))
            ]
            if session.testMode {
                attributes.append(.environment(AccountEnvironmentAttribute(environment: .test)))
            }
            var maxSortOrder: Int32 = 0
            for record in transaction.getRecords() {
                for attribute in record.attributes {
                    if case let .sortOrder(sortOrder) = attribute {
                        maxSortOrder = max(maxSortOrder, sortOrder.order)
                    }
                }
            }
            attributes.append(.sortOrder(AccountSortOrderAttribute(order: maxSortOrder + 1)))
            let recordId = transaction.createRecord(attributes)
            if makeCurrent {
                transaction.setCurrentId(recordId)
                transaction.removeAuth()
            }
            return recordId
        }
        |> castError(NagramSessionBackupServiceError.self)
    }
}

public func nagramRestoreBackupRecord(sharedContext: SharedAccountContext, record: NagramSessionBackupRecord, makeCurrent: Bool = false) -> Signal<AccountRecordId, NagramSessionBackupServiceError> {
    return nagramImportSessionString(sharedContext: sharedContext, sessionString: record.sessionString, makeCurrent: makeCurrent)
}
