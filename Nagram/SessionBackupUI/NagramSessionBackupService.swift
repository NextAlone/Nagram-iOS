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
            return "This session's key belongs to datacenter \(sessionDatacenter), but the account lives on datacenter \(homeDatacenter). Telegram answers every request for it — including the authorization transfer that would move it — with USER_MIGRATE, so the session cannot be used from here. Export a new session string from the account's own datacenter."
        case .importTimedOut:
            return "Telegram did not finish verifying this session in time. The incomplete account was discarded."
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
public func nagramImportSessionString(sharedContext: SharedAccountContext, sessionString: String, makeCurrent: Bool = false, progress: @escaping (NagramSessionImportProgress) -> Void = { _ in }) -> Signal<AccountRecordId, NagramSessionBackupServiceError> {
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
        progress(.addingAccount)
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
            // Deliberately not current yet. Switching now tears down the login
            // flow, which deallocates the screen that owns this signal and
            // cancels the migration below before it can finish.
            return transaction.createRecord(attributes)
        }
        |> castError(NagramSessionBackupServiceError.self)
        |> mapToSignal { recordId -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
            return nagramMigrateImportedAccount(sharedContext: sharedContext, recordId: recordId, session: session, progress: progress)
        }
        |> mapToSignal { finalRecordId -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
            guard makeCurrent else {
                return .single(finalRecordId)
            }
            return accountManager.transaction { transaction -> AccountRecordId in
                transaction.setCurrentId(finalRecordId)
                transaction.removeAuth()
                return finalRecordId
            }
            |> castError(NagramSessionBackupServiceError.self)
        }
    }
}

// A session string names the datacenter its key belongs to, which is not
// always the datacenter the account is homed on. When they differ every
// request comes back USER_MIGRATE_N and upstream has no handler, so the
// account would sit at "Updating..." forever. Here the freshly imported
// account is asked where it really lives; if that is elsewhere, MTProto is
// told to authorize that datacenter (it does so by exporting authorization
// from the imported one), and the account is rebuilt around the correct
// master datacenter. The original key is kept as an additional datacenter key.
private func nagramMigrateImportedAccount(
    sharedContext: SharedAccountContext,
    recordId: AccountRecordId,
    session: PyrogramSessionString,
    progress: @escaping (NagramSessionImportProgress) -> Void
) -> Signal<AccountRecordId, NagramSessionBackupServiceError> {
    let accountManager = sharedContext.accountManager
    let discardRecord: (NagramSessionBackupServiceError) -> Signal<AccountRecordId, NagramSessionBackupServiceError> = { error in
        return accountManager.transaction { transaction -> Void in
            transaction.updateRecord(recordId, { _ in return nil })
        }
        |> castError(NagramSessionBackupServiceError.self)
        |> mapToSignal { _ -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
            return .fail(error)
        }
    }
    Logger.shared.log("NagramMigration", "imported record \(recordId.int64), waiting for it to load")
    let loadedAccount = sharedContext.activeAccountContexts
    |> map { _, accounts, _ -> Account? in
        return accounts.first(where: { $0.0 == recordId })?.1.account
    }
    |> filter { $0 != nil }
    |> take(1)

    return loadedAccount
    |> castError(NagramSessionBackupServiceError.self)
    |> mapToSignal { account -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
        guard let account else {
            Logger.shared.log("NagramMigration", "account context never arrived")
            return discardRecord(.importTimedOut)
        }
        Logger.shared.log("NagramMigration", "account loaded, verifying identity")
        progress(.checkingDatacenter)
        return nagramAuthenticatedUserId(network: account.network)
        |> castError(NagramSessionBackupServiceError.self)
        |> mapToSignal { authenticatedUserResult -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
            let authenticatedUserId: Int64
            switch authenticatedUserResult {
            case let .userId(userId):
                authenticatedUserId = userId
            case let .failure(errorCode, errorDescription):
                Logger.shared.log("NagramMigration", "discarding record after self-user verification failure")
                return discardRecord(.authenticationFailed(errorCode: errorCode, errorDescription: errorDescription))
            }

            guard authenticatedUserId == session.userId else {
                Logger.shared.log("NagramMigration", "session user \(session.userId) does not match authenticated user \(authenticatedUserId); discarding imported record")
                return discardRecord(.userIdMismatch(expected: session.userId, authenticated: authenticatedUserId))
            }

            Logger.shared.log("NagramMigration", "identity verified, probing home datacenter (session dc \(session.dcId))")
            return nagramHomeDatacenterId(network: account.network)
            |> castError(NagramSessionBackupServiceError.self)
            |> mapToSignal { homeDatacenterResult -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
                let homeDatacenterId: Int32
                switch homeDatacenterResult {
                case .current:
                    Logger.shared.log("NagramMigration", "no migration needed (session dc \(session.dcId))")
                    return .single(recordId)
                case let .migrate(datacenterId):
                    homeDatacenterId = datacenterId
                case let .failure(errorCode, errorDescription):
                    Logger.shared.log("NagramMigration", "discarding record after datacenter probe failure")
                    return discardRecord(.datacenterProbeFailed(errorCode: errorCode, errorDescription: errorDescription))
                }

                guard homeDatacenterId != session.dcId else {
                    Logger.shared.log("NagramMigration", "probe redirected to the existing session dc \(session.dcId)")
                    return .single(recordId)
                }
                Logger.shared.log("NagramMigration", "migrating from dc \(session.dcId) to home dc \(homeDatacenterId)")
                progress(.movingToDatacenter(homeDatacenterId))
                return nagramAuthorizedDatacenterKey(network: account.network, datacenterId: homeDatacenterId, masterDatacenterId: session.dcId)
                |> castError(NagramSessionBackupServiceError.self)
                |> mapToSignal { migrated -> Signal<AccountRecordId, NagramSessionBackupServiceError> in
                    guard let migrated else {
                        // Telegram redirects even auth.exportAuthorization to the home
                        // datacenter, so there is no way to bootstrap authorization
                        // there from here. Drop the record rather than leaving a
                        // permanently reconnecting account behind.
                        Logger.shared.log("NagramMigration", "home dc unreachable from dc \(session.dcId); discarding imported record")
                        return discardRecord(.datacenterUnreachable(sessionDatacenter: session.dcId, homeDatacenter: homeDatacenterId))
                    }
                    Logger.shared.log("NagramMigration", "authorized home dc \(homeDatacenterId), rebuilding record")
                    let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(authenticatedUserId))
                    let backupData = AccountBackupData(
                        masterDatacenterId: homeDatacenterId,
                        peerId: peerId.toInt64(),
                        masterDatacenterKey: migrated.key,
                        masterDatacenterKeyId: migrated.keyId,
                        notificationEncryptionKeyId: nil,
                        notificationEncryptionKey: nil,
                        additionalDatacenterKeys: [
                            session.dcId: AccountBackupData.DatacenterKey(
                                id: session.dcId,
                                keyId: nagramAuthKeyId(authKey: session.authKey),
                                key: session.authKey
                            )
                        ]
                    )
                    return accountManager.transaction { transaction -> AccountRecordId in
                        var attributes: [TelegramAccountManagerTypes.Attribute] = [
                            .backupData(AccountBackupDataAttribute(data: backupData))
                        ]
                        if session.testMode {
                            attributes.append(.environment(AccountEnvironmentAttribute(environment: .test)))
                        }
                        var sortOrder: Int32 = 0
                        for record in transaction.getRecords() where record.id == recordId {
                            for attribute in record.attributes {
                                if case let .sortOrder(value) = attribute {
                                    sortOrder = value.order
                                }
                            }
                        }
                        attributes.append(.sortOrder(AccountSortOrderAttribute(order: sortOrder)))
                        let migratedRecordId = transaction.createRecord(attributes)
                        transaction.updateRecord(recordId, { _ in
                            return nil
                        })
                        Logger.shared.log("NagramMigration", "rebuilt as record \(migratedRecordId.int64) on dc \(homeDatacenterId)")
                        return migratedRecordId
                    }
                    |> castError(NagramSessionBackupServiceError.self)
                }
            }
        }
    }
    // Loading, verification, and migration must all finish before the staging
    // record is valid. A timeout discards it just like any explicit failure.
    |> timeout(120.0, queue: Queue.concurrentDefaultQueue(), alternate: discardRecord(.importTimedOut))
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
