import AccountContext
import Foundation
import MtProtoKit
import NagramSessionBackup
import NagramSettings
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

// Importing used to be instant. Migration can keep it busy for a minute or
// more, so the caller needs something to show meanwhile.
public enum NagramSessionImportProgress {
    case addingAccount
    case checkingDatacenter
    case movingToDatacenter(Int32)
}

public enum NagramSessionBackupServiceError: Error, CustomStringConvertible {
    case noSessionData
    case invalidAuthKey(Int)
    case invalidSessionString(String)
    case alreadyLoggedIn(Int64)
    case authenticationFailed(errorCode: Int32, errorDescription: String?)
    case userIdMismatch(expected: Int64, authenticated: Int64)
    case datacenterProbeFailed(errorCode: Int32, errorDescription: String?)
    case datacenterUnreachable(sessionDatacenter: Int32, homeDatacenter: Int32)
    case importTimedOut

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
        case let .authenticationFailed(errorCode, errorDescription):
            return "Telegram could not verify this session (\(errorDescription ?? "RPC error \(errorCode)"))."
        case let .userIdMismatch(expected, authenticated):
            return "The session claims to belong to user \(expected), but its authorization key belongs to user \(authenticated)."
        case let .datacenterProbeFailed(errorCode, errorDescription):
            return "Telegram could not determine this session's home datacenter (\(errorDescription ?? "RPC error \(errorCode)"))."
        case let .datacenterUnreachable(sessionDatacenter, homeDatacenter):
            return "This session's key belongs to datacenter \(sessionDatacenter), but the account lives on datacenter \(homeDatacenter). Authorization transfer did not finish. Check the connection, or export a new session string from the account's own datacenter."
        case .importTimedOut:
            return "Telegram did not finish verifying this session in time. No account was added."
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

// Validate using an isolated in-memory network. Only the verified backup is
// persisted, in one transaction, after the verification connection has stopped.
public func nagramImportSessionString(sharedContext: SharedAccountContext, sessionString: String, makeCurrent: Bool = false, progress: @escaping (NagramSessionImportProgress) -> Void = { _ in }) -> Signal<AccountRecordId, NagramSessionBackupServiceError> {
    let session: PyrogramSessionString
    do {
        session = try PyrogramSessionString(decoding: sessionString)
    } catch {
        return .fail(.invalidSessionString("\(error)"))
    }
    guard !session.isBot else {
        return .fail(.invalidSessionString("Bot sessions cannot be used in this app."))
    }
    guard (1 ... (session.testMode ? 3 : 5)).contains(session.dcId) else {
        return .fail(.invalidSessionString("This session uses an unsupported datacenter."))
    }
    // PeerId packs a positive ID into 56 bits. Reject it before its initializer
    // asserts (debug) or its packed representation loses bits (release).
    guard session.userId <= 0x00ffffffffffffff else {
        return .fail(.invalidSessionString("This session uses an unsupported user id."))
    }

    let accountManager = sharedContext.accountManager
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
    return Signal { subscriber in
        let commitGate = NagramSessionImportCommitGate()
        let operation = sharedContext.activeAccountContexts
        |> take(1)
        |> castError(NagramSessionBackupServiceError.self)
        |> mapToSignal { _, accounts, _ -> Signal<AccountBackupData, NagramSessionBackupServiceError> in
            if accounts.contains(where: { $0.1.account.testingEnvironment == session.testMode && $0.1.account.peerId == peerId }) {
                return .fail(.alreadyLoggedIn(session.userId))
            }
            progress(.checkingDatacenter)
            return nagramWithSessionImportNetwork(accountManager: accountManager, networkArguments: sharedContext.networkArguments, backupData: backupData, testingEnvironment: session.testMode, verify: { network in
                return nagramValidateImportedSession(network: network, session: session, backupData: backupData, progress: progress)
            })
            |> timeout(120.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.importTimedOut))
        }
        |> mapToSignal { verifiedBackup -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
            progress(.addingAccount)
            return accountManager.transaction { transaction -> Result<AccountRecordId, NagramSessionBackupServiceError>? in
                return commitGate.commit {
                    var maxSortOrder: Int32 = 0
                    for record in transaction.getRecords() {
                        let isTesting = record.attributes.contains(where: {
                            if case let .environment(value) = $0 { return value.environment == .test }
                            return false
                        })
                        let isLoggedOut = record.attributes.contains(where: {
                            if case .loggedOut = $0 { return true }
                            return false
                        })
                        for attribute in record.attributes {
                            if case let .backupData(value) = attribute, !isLoggedOut, isTesting == session.testMode, value.data?.peerId == verifiedBackup.peerId {
                                return .failure(.alreadyLoggedIn(session.userId))
                            }
                            if case let .sortOrder(value) = attribute {
                                maxSortOrder = max(maxSortOrder, value.order)
                            }
                        }
                    }
                    var attributes: [TelegramAccountManagerTypes.Attribute] = [
                        .backupData(AccountBackupDataAttribute(data: verifiedBackup)),
                        .sortOrder(AccountSortOrderAttribute(order: maxSortOrder + 1))
                    ]
                    if session.testMode {
                        attributes.append(.environment(AccountEnvironmentAttribute(environment: .test)))
                    }
                    let recordId = transaction.createRecord(attributes)
                    if makeCurrent {
                        transaction.setCurrentId(recordId)
                        transaction.removeAuth()
                    }
                    return .success(recordId)
                }
            }
            |> castError(NagramSessionBackupServiceError.self)
            |> mapToSignal { result -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
                guard let result else { return .complete() }
                switch result {
                case let .success(recordId): return .single(recordId)
                case let .failure(error): return .fail(error)
                }
            }
        }
        let disposable = operation.start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion)
        return ActionDisposable {
            commitGate.cancel()
            disposable.dispose()
        }
    }
}

private func nagramValidateImportedSession(network: Network, session: PyrogramSessionString, backupData: AccountBackupData, progress: @escaping (NagramSessionImportProgress) -> Void) -> Signal<AccountBackupData, NagramSessionBackupServiceError> {
    return nagramAuthenticatedUserId(network: network)
    |> castError(NagramSessionBackupServiceError.self)
    |> mapToSignal { result -> Signal<AccountBackupData, NagramSessionBackupServiceError> in
        switch result {
        case let .failure(code, description):
            return .fail(.authenticationFailed(errorCode: code, errorDescription: description))
        case let .userId(userId):
            guard userId == session.userId else {
                return .fail(.userIdMismatch(expected: session.userId, authenticated: userId))
            }
        }
        return nagramHomeDatacenterId(network: network)
        |> castError(NagramSessionBackupServiceError.self)
        |> mapToSignal { result -> Signal<AccountBackupData, NagramSessionBackupServiceError> in
            switch result {
            case .current:
                return .single(backupData)
            case let .failure(code, description):
                return .fail(.datacenterProbeFailed(errorCode: code, errorDescription: description))
            case let .migrate(datacenterId):
                guard datacenterId != session.dcId, (1 ... (session.testMode ? 3 : 5)).contains(datacenterId) else {
                    return .fail(.datacenterProbeFailed(errorCode: 303, errorDescription: "INVALID_HOME_DATACENTER"))
                }
                progress(.movingToDatacenter(datacenterId))
                return nagramAuthorizedDatacenterKey(network: network, datacenterId: datacenterId, masterDatacenterId: session.dcId)
                |> castError(NagramSessionBackupServiceError.self)
                |> mapToSignal { migrated -> Signal<AccountBackupData, NagramSessionBackupServiceError> in
                    guard let migrated else {
                        return .fail(.datacenterUnreachable(sessionDatacenter: session.dcId, homeDatacenter: datacenterId))
                    }
                    return .single(AccountBackupData(
                        masterDatacenterId: datacenterId,
                        peerId: backupData.peerId,
                        masterDatacenterKey: migrated.key,
                        masterDatacenterKeyId: migrated.keyId,
                        notificationEncryptionKeyId: nil,
                        notificationEncryptionKey: nil,
                        additionalDatacenterKeys: [session.dcId: AccountBackupData.DatacenterKey(id: session.dcId, keyId: backupData.masterDatacenterKeyId, key: session.authKey)]
                    ))
                }
            }
        }
    }
}

// Accounts stored in the keychain — synced across the user's devices by iCloud
// Keychain — that are not signed in here. This is what the login screen badges
// and what the account picker lists.
public func nagramRestorableBackups(sharedContext: SharedAccountContext) -> Signal<[NagramSessionBackupRecord], NoError> {
    return sharedContext.activeAccountContexts
    |> take(1)
    |> map { _, accounts, _ -> Set<Int64> in
        return Set(accounts.map { $0.1.account.peerId.id._internalGetInt64Value() })
    }
    |> mapToSignal { signedInUserIds -> Signal<[NagramSessionBackupRecord], NoError> in
        // Off the main thread on purpose: a synchronizable keychain query can
        // block while iCloud Keychain answers, and this runs while the login
        // screens are being built.
        return Signal { subscriber in
            let includeSynced = NagramSettings.shared.sessionBackupICloudSync
            var newestByUserId: [Int64: NagramSessionBackupRecord] = [:]
            for record in NagramSessionBackupKeychain.shared.allRecords(includeSynced: includeSynced) where !signedInUserIds.contains(record.userId) {
                if let existing = newestByUserId[record.userId], existing.createdAt >= record.createdAt {
                    continue
                }
                newestByUserId[record.userId] = record
            }
            let records = newestByUserId.values.sorted(by: { $0.createdAt > $1.createdAt })
            subscriber.putNext(records)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
    }
}

public func nagramRestoreBackupRecord(sharedContext: SharedAccountContext, record: NagramSessionBackupRecord, makeCurrent: Bool = false, progress: @escaping (NagramSessionImportProgress) -> Void = { _ in }) -> Signal<AccountRecordId, NagramSessionBackupServiceError> {
    return nagramImportSessionString(sharedContext: sharedContext, sessionString: record.sessionString, makeCurrent: makeCurrent, progress: progress)
}
