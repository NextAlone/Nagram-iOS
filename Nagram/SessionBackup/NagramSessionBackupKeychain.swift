import Foundation
import Security

// MARK: NAGRAM — Keychain store for session backups.
//
// Layout mirrors iebb/mithka's iOS `AccountSessionBackupPlugin`:
//   class   kSecClassGenericPassword
//   service "<bundleId>.sessionsbackup"       synced: synchronizable, WhenUnlocked
//           "<bundleId>.sessionsbackup.local" local:  device-only, AfterFirstUnlock
//   account "<userId>"
//   data    the NagramSessionBackupRecord JSON envelope
//
// Keychain items are scoped to the app that wrote them, so this store backs up
// across a user's own devices via iCloud Keychain. Moving a session to or from
// another app goes through the exported session string or backup file.
public final class NagramSessionBackupKeychain {
    public static let shared = NagramSessionBackupKeychain()

    private let syncedService: String
    private let localService: String

    public init(bundleIdentifier: String? = nil) {
        let bundleId = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? "org.telegram.Telegram"
        self.syncedService = "\(bundleId).sessionsbackup"
        self.localService = "\(bundleId).sessionsbackup.local"
    }

    private func service(for storage: NagramSessionBackupStorage) -> String {
        switch storage {
        case .synced:
            return self.syncedService
        case .local:
            return self.localService
        }
    }

    private func accessibility(for storage: NagramSessionBackupStorage) -> CFString {
        switch storage {
        case .synced:
            return kSecAttrAccessibleWhenUnlocked
        case .local:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }

    private func isSynchronizable(_ storage: NagramSessionBackupStorage) -> Bool {
        return storage == .synced
    }

    public func save(_ record: NagramSessionBackupRecord) throws {
        let data = try record.encoded()
        let storage = record.storage
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service(for: storage),
            kSecAttrAccount as String: record.accountId,
            kSecAttrSynchronizable as String: self.isSynchronizable(storage)
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: self.accessibility(for: storage)
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw NagramSessionBackupKeychainError.status(updateStatus)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = self.accessibility(for: storage)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw NagramSessionBackupKeychainError.status(addStatus)
        }
    }

    // Returns the newest readable record per account for the given storage.
    public func records(storage: NagramSessionBackupStorage) -> [NagramSessionBackupRecord] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service(for: storage),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        // `Any` covers items written before the synchronizable attribute was set.
        query[kSecAttrSynchronizable as String] = storage == .synced ? kSecAttrSynchronizableAny : false

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecParam || status == errSecUnimplemented {
            query.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess, let items = result as? [Data] else {
            return []
        }

        var newestByAccount: [String: NagramSessionBackupRecord] = [:]
        for item in items {
            guard let record = try? NagramSessionBackupRecord(decoding: item, storage: storage) else {
                continue
            }
            if let existing = newestByAccount[record.accountId], existing.createdAt >= record.createdAt {
                continue
            }
            newestByAccount[record.accountId] = record
        }
        return newestByAccount.values.sorted(by: { $0.createdAt > $1.createdAt })
    }

    public func allRecords() -> [NagramSessionBackupRecord] {
        let combined = self.records(storage: .synced) + self.records(storage: .local)
        return combined.sorted(by: { $0.createdAt > $1.createdAt })
    }

    public func delete(accountId: String, storage: NagramSessionBackupStorage) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service(for: storage),
            kSecAttrAccount as String: accountId
        ]
        query[kSecAttrSynchronizable as String] = storage == .synced ? kSecAttrSynchronizableAny : false
        var status = SecItemDelete(query as CFDictionary)
        if status == errSecParam || status == errSecUnimplemented {
            query.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemDelete(query as CFDictionary)
        }
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NagramSessionBackupKeychainError.status(status)
        }
    }

    public func deleteAll() throws {
        for storage in NagramSessionBackupStorage.allCases {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.service(for: storage)
            ]
            query[kSecAttrSynchronizable as String] = storage == .synced ? kSecAttrSynchronizableAny : false
            var status = SecItemDelete(query as CFDictionary)
            if status == errSecParam || status == errSecUnimplemented {
                query.removeValue(forKey: kSecAttrSynchronizable as String)
                status = SecItemDelete(query as CFDictionary)
            }
            if status != errSecSuccess && status != errSecItemNotFound {
                throw NagramSessionBackupKeychainError.status(status)
            }
        }
    }
}

public enum NagramSessionBackupKeychainError: Error, CustomStringConvertible, Equatable {
    case status(OSStatus)

    public var description: String {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(message)"
        }
    }
}
