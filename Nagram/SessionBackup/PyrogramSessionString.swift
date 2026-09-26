import Foundation

// MARK: NAGRAM — Pyrogram-compatible session string codec.
//
// Wire format: 271 raw bytes, base64url encoded.
//
//   offset  size  field
//   0       1     dcId      UInt8   (non-zero)
//   1       4     apiId     UInt32  big-endian (non-zero)
//   5       1     testMode  UInt8   (0 or 1)
//   6       256   authKey   raw MTProto auth key (not all-zero)
//   262     8     userId    UInt64  big-endian (non-zero)
//   270     1     isBot     UInt8   (0 or 1)
//
// This is Pyrogram's SESSION_STRING_FORMAT ">BI?256sQ?" and is the same string
// iebb/mithka exports and imports, so a session moves between Nagram-iOS,
// Mithka, and any Pyrogram-based tool in either direction.
public struct PyrogramSessionString: Equatable {
    public static let rawSize = 271
    public static let authKeySize = 256

    private static let dcIdOffset = 0
    private static let apiIdOffset = 1
    private static let testModeOffset = 5
    private static let authKeyOffset = 6
    private static let userIdOffset = 262
    private static let isBotOffset = 270

    public var dcId: Int32
    public var apiId: Int32
    public var testMode: Bool
    public var authKey: Data
    public var userId: Int64
    public var isBot: Bool

    public init(dcId: Int32, apiId: Int32, testMode: Bool, authKey: Data, userId: Int64, isBot: Bool) {
        self.dcId = dcId
        self.apiId = apiId
        self.testMode = testMode
        self.authKey = authKey
        self.userId = userId
        self.isBot = isBot
    }
}

public enum PyrogramSessionStringError: Error, CustomStringConvertible, Equatable {
    case empty
    case notBase64
    case invalidSize(Int)
    case invalidDcId
    case invalidApiId
    case invalidUserId
    case emptyAuthKey
    case invalidAuthKeySize(Int)
    case userIdMismatch(expected: Int64, found: Int64)

    public var description: String {
        switch self {
        case .empty:
            return "The session string is empty."
        case .notBase64:
            return "The session string is not valid base64url text."
        case let .invalidSize(size):
            return "The session string decodes to \(size) bytes, but \(PyrogramSessionString.rawSize) bytes are required."
        case .invalidDcId:
            return "The session string has an invalid datacenter id."
        case .invalidApiId:
            return "The session string has an invalid API id."
        case .invalidUserId:
            return "The session string has an invalid user id."
        case .emptyAuthKey:
            return "The session string has an empty authorization key."
        case let .invalidAuthKeySize(size):
            return "The authorization key is \(size) bytes, but \(PyrogramSessionString.authKeySize) bytes are required."
        case let .userIdMismatch(expected, found):
            return "The session string belongs to user \(found), but user \(expected) was expected."
        }
    }
}

public extension PyrogramSessionString {
    // Decodes and fully validates a Pyrogram/Mithka session string.
    init(decoding text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PyrogramSessionStringError.empty
        }
        guard let bytes = PyrogramSessionString.decodeBase64URL(trimmed) else {
            throw PyrogramSessionStringError.notBase64
        }
        if bytes.count != PyrogramSessionString.rawSize {
            throw PyrogramSessionStringError.invalidSize(bytes.count)
        }

        let dcId = Int32(bytes[PyrogramSessionString.dcIdOffset])
        let apiId = PyrogramSessionString.readBigEndianUInt32(bytes, at: PyrogramSessionString.apiIdOffset)
        let testMode = bytes[PyrogramSessionString.testModeOffset] != 0
        let authKey = bytes.subdata(in: PyrogramSessionString.authKeyOffset ..< (PyrogramSessionString.authKeyOffset + PyrogramSessionString.authKeySize))
        let userId = PyrogramSessionString.readBigEndianUInt64(bytes, at: PyrogramSessionString.userIdOffset)
        let isBot = bytes[PyrogramSessionString.isBotOffset] != 0

        if dcId == 0 {
            throw PyrogramSessionStringError.invalidDcId
        }
        if apiId == 0 || apiId > UInt32(Int32.max) {
            throw PyrogramSessionStringError.invalidApiId
        }
        if userId == 0 || userId > UInt64(Int64.max) {
            throw PyrogramSessionStringError.invalidUserId
        }
        if authKey.allSatisfy({ $0 == 0 }) {
            throw PyrogramSessionStringError.emptyAuthKey
        }

        self.init(dcId: dcId, apiId: Int32(apiId), testMode: testMode, authKey: authKey, userId: Int64(userId), isBot: isBot)
    }

    // Encodes to the canonical Pyrogram representation: base64url without padding.
    func encoded() throws -> String {
        if self.dcId <= 0 || self.dcId > 0xff {
            throw PyrogramSessionStringError.invalidDcId
        }
        if self.apiId <= 0 {
            throw PyrogramSessionStringError.invalidApiId
        }
        if self.userId <= 0 {
            throw PyrogramSessionStringError.invalidUserId
        }
        if self.authKey.count != PyrogramSessionString.authKeySize {
            throw PyrogramSessionStringError.invalidAuthKeySize(self.authKey.count)
        }
        if self.authKey.allSatisfy({ $0 == 0 }) {
            throw PyrogramSessionStringError.emptyAuthKey
        }

        var bytes = Data(capacity: PyrogramSessionString.rawSize)
        bytes.append(UInt8(self.dcId))
        PyrogramSessionString.appendBigEndian(UInt32(self.apiId), to: &bytes)
        bytes.append(self.testMode ? 1 : 0)
        bytes.append(self.authKey)
        PyrogramSessionString.appendBigEndian(UInt64(self.userId), to: &bytes)
        bytes.append(self.isBot ? 1 : 0)

        return PyrogramSessionString.encodeBase64URL(bytes)
    }

    // MTProto derives the auth key id from the trailing 8 bytes of SHA1(authKey),
    // read as a little-endian int64 (a raw memcpy on every Apple device). The
    // Pyrogram format does not carry the id, so importers recompute it.
    static func authKeyId(sha1Digest digest: Data) -> Int64 {
        var value: UInt64 = 0
        for (index, byte) in digest.suffix(8).enumerated() {
            value |= UInt64(byte) << UInt64(8 * index)
        }
        return Int64(bitPattern: value)
    }

    func validate(expectedUserId: Int64) throws {
        if self.userId != expectedUserId {
            throw PyrogramSessionStringError.userIdMismatch(expected: expectedUserId, found: self.userId)
        }
    }
}

private extension PyrogramSessionString {
    // Accepts padded and unpadded base64url, and tolerates standard base64
    // alphabets so strings pasted from other tools still import.
    static func decodeBase64URL(_ text: String) -> Data? {
        var normalized = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized.removeAll(where: { $0.isWhitespace })
        let remainder = normalized.count % 4
        if remainder == 1 {
            return nil
        }
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: normalized)
    }

    static func encodeBase64URL(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func readBigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0 ..< 4 {
            value = (value << 8) | UInt32(data[data.startIndex + offset + index])
        }
        return value
    }

    static func readBigEndianUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0 ..< 8 {
            value = (value << 8) | UInt64(data[data.startIndex + offset + index])
        }
        return value
    }

    static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xff))
        }
    }

    static func appendBigEndian(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }
}
