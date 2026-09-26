import Foundation

// MARK: NAGRAM — Session backup record envelope.
//
// The envelope is byte-for-byte the JSON that iebb/mithka writes and reads
// (`AccountBackupService._encode` / `._decode`), including its `format` marker.
// Mithka's decoder rejects any other marker, so keeping the identifier is what
// makes an exported file restorable in either app.
public enum NagramSessionBackupStorage: String, CaseIterable, Equatable {
    case synced
    case local
}

public struct NagramSessionBackupRecord: Equatable {
    // Written by both apps.
    public static let formatIdentifier = "mithka.tdlib.session_string.v2.explicit_consent"
    // Accepted on import for older Mithka backups; never written.
    public static let legacyFormatIdentifier = "mithka.tdlib.session_string.v1"

    public var accountId: String
    public var userId: Int64
    public var name: String
    public var phone: String?
    public var createdAt: Date
    public var storage: NagramSessionBackupStorage
    public var sessionString: String
    // Mithka's installation-local account slot. It is informational there and
    // unused by its decoder; Nagram has no slots, so it is always 0.
    public var slot: Int

    public init(accountId: String, userId: Int64, name: String, phone: String?, createdAt: Date, storage: NagramSessionBackupStorage, sessionString: String, slot: Int = 0) {
        self.accountId = accountId
        self.userId = userId
        self.name = name
        self.phone = phone
        self.createdAt = createdAt
        self.storage = storage
        self.sessionString = sessionString
        self.slot = slot
    }

    public var displayName: String {
        let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? self.accountId : trimmed
    }

    public var sizeBytes: Int {
        return Data(self.sessionString.utf8).count
    }

    public func session() throws -> PyrogramSessionString {
        return try PyrogramSessionString(decoding: self.sessionString)
    }
}

public enum NagramSessionBackupRecordError: Error, CustomStringConvertible, Equatable {
    case notJSON
    case unsupportedFormat(String?)
    case missingSessionString
    case missingAccountId

    public var description: String {
        switch self {
        case .notJSON:
            return "The backup is not a JSON object."
        case let .unsupportedFormat(value):
            return "Unsupported backup format \(value ?? "<missing>")."
        case .missingSessionString:
            return "The backup does not contain a session string."
        case .missingAccountId:
            return "The backup does not contain an account id."
        }
    }
}

public extension NagramSessionBackupRecord {
    // Matches Dart's `DateTime.toIso8601String()` on a UTC value, which is what
    // Mithka writes and what its `DateTime.tryParse` reads back.
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func encoded() throws -> Data {
        var object: [String: Any] = [
            "format": NagramSessionBackupRecord.formatIdentifier,
            "id": self.accountId,
            "accountId": self.accountId,
            "slot": self.slot,
            "userId": self.userId,
            "name": self.name,
            "storage": self.storage.rawValue,
            "createdAt": NagramSessionBackupRecord.dateFormatter.string(from: self.createdAt),
            "sessionString": self.sessionString
        ]
        object["phone"] = self.phone ?? NSNull()
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    init(decoding data: Data, storage: NagramSessionBackupStorage = .synced) throws {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NagramSessionBackupRecordError.notJSON
        }
        let format = object["format"] as? String
        if format != NagramSessionBackupRecord.formatIdentifier && format != NagramSessionBackupRecord.legacyFormatIdentifier {
            throw NagramSessionBackupRecordError.unsupportedFormat(format)
        }
        guard let sessionString = object["sessionString"] as? String, !sessionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NagramSessionBackupRecordError.missingSessionString
        }

        let accountId = NagramSessionBackupRecord.stringValue(object["accountId"]) ?? NagramSessionBackupRecord.stringValue(object["id"])
        guard let accountId, !accountId.isEmpty else {
            throw NagramSessionBackupRecordError.missingAccountId
        }

        var userId = NagramSessionBackupRecord.int64Value(object["userId"]) ?? 0
        if userId == 0 {
            userId = Int64(accountId) ?? 0
        }

        var createdAt = Date(timeIntervalSince1970: 0)
        if let text = object["createdAt"] as? String {
            createdAt = NagramSessionBackupRecord.dateFormatter.date(from: text)
                ?? NagramSessionBackupRecord.fallbackDateFormatter.date(from: text)
                ?? createdAt
        }

        let storedStorage = (object["storage"] as? String).flatMap(NagramSessionBackupStorage.init(rawValue:))
        self.init(
            accountId: accountId,
            userId: userId,
            name: (object["name"] as? String) ?? accountId,
            phone: object["phone"] as? String,
            createdAt: createdAt,
            storage: storedStorage ?? storage,
            sessionString: sessionString,
            slot: (object["slot"] as? Int) ?? 0
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let text = value as? String {
            return Int64(text)
        }
        return nil
    }
}
