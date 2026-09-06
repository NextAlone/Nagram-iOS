import Foundation
import XCTest

@testable import NagramSessionBackup

// MARK: NAGRAM — Interop tests for session backup.
//
// The golden values below were produced independently by Pyrogram's own storage
// format (`struct.pack(">BI?256sQ?", ...)`, base64url, padding stripped) and by
// `hashlib.sha1`, not by this Swift code. If a change here breaks two-way
// compatibility with Mithka or Pyrogram, these fail.
final class PyrogramSessionStringTests: XCTestCase {
    // authKey = bytes((i * 7 + 11) % 256 for i in range(256))
    private static let vectorOneKey = Data((0 ..< 256).map { UInt8(($0 * 7 + 11) % 256) })
    private static let vectorOneString = "AgAAB_gACxIZICcuNTxDSlFYX2ZtdHuCiZCXnqWss7rByM_W3eTr8vkABw4VHCMqMTg_Rk1UW2JpcHd-hYyTmqGor7a9xMvS2eDn7vX8AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dzj6vH4_wYNFBsiKTA3PkVMU1phaG92fYSLkpmgp661vMPK0djf5u30-wIJEBceJSwzOkFIT1ZdZGtyeYCHjpWco6qxuL_GzdTb4unw9_4FDBMaISgvNj1ES1JZYGdudXyDipGYn6attLvCydDX3uXs8_oBCA8WHSQrMjlAR05VXGNqcXh_ho2Um6KpsLe-xczT2uHo7_b9BAAAAAAAC9soAA"

    // authKey = bytes((255 - i) % 256 for i in range(256))
    private static let vectorTwoKey = Data((0 ..< 256).map { UInt8((255 - $0) % 256) })
    private static let vectorTwoString = "BQAJVAcB__79_Pv6-fj39vX08_Lx8O_u7ezr6uno5-bl5OPi4eDf3t3c29rZ2NfW1dTT0tHQz87NzMvKycjHxsXEw8LBwL--vby7urm4t7a1tLOysbCvrq2sq6qpqKempaSjoqGgn56dnJuamZiXlpWUk5KRkI-OjYyLiomIh4aFhIOCgYB_fn18e3p5eHd2dXRzcnFwb25tbGtqaWhnZmVkY2JhYF9eXVxbWllYV1ZVVFNSUVBPTk1MS0pJSEdGRURDQkFAPz49PDs6OTg3NjU0MzIxMC8uLSwrKikoJyYlJCMiISAfHh0cGxoZGBcWFRQTEhEQDw4NDAsKCQgHBgUEAwIBAAAAAAGhO4YAAQ"

    func testDecodesPyrogramProducedString() throws {
        let session = try PyrogramSessionString(decoding: PyrogramSessionStringTests.vectorOneString)
        XCTAssertEqual(session.dcId, 2)
        XCTAssertEqual(session.apiId, 2040)
        XCTAssertFalse(session.testMode)
        XCTAssertEqual(session.authKey, PyrogramSessionStringTests.vectorOneKey)
        XCTAssertEqual(session.userId, 777000)
        XCTAssertFalse(session.isBot)
    }

    func testEncodesByteIdenticalToPyrogram() throws {
        let session = PyrogramSessionString(dcId: 2, apiId: 2040, testMode: false, authKey: PyrogramSessionStringTests.vectorOneKey, userId: 777000, isBot: false)
        XCTAssertEqual(try session.encoded(), PyrogramSessionStringTests.vectorOneString)
    }

    func testHandlesTestModeBotAndLargeUserId() throws {
        let session = try PyrogramSessionString(decoding: PyrogramSessionStringTests.vectorTwoString)
        XCTAssertEqual(session.dcId, 5)
        XCTAssertEqual(session.apiId, 611335)
        XCTAssertTrue(session.testMode)
        XCTAssertEqual(session.authKey, PyrogramSessionStringTests.vectorTwoKey)
        XCTAssertEqual(session.userId, 7_000_000_000)
        XCTAssertTrue(session.isBot)
        XCTAssertEqual(try session.encoded(), PyrogramSessionStringTests.vectorTwoString)
    }

    func testRoundTripPreservesEveryField() throws {
        var authKey = Data(count: PyrogramSessionString.authKeySize)
        for index in 0 ..< authKey.count {
            authKey[index] = UInt8((index * 31 + 7) % 256)
        }
        let original = PyrogramSessionString(dcId: 4, apiId: 123456, testMode: true, authKey: authKey, userId: 6_543_210_987, isBot: true)
        let decoded = try PyrogramSessionString(decoding: try original.encoded())
        XCTAssertEqual(decoded, original)
    }

    func testCanonicalEncodingIsUnpaddedBase64URL() throws {
        let encoded = try PyrogramSessionString(dcId: 1, apiId: 1, testMode: false, authKey: PyrogramSessionStringTests.vectorOneKey, userId: 1, isBot: false).encoded()
        XCTAssertEqual(encoded.count, 362)
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
    }

    func testDecodeAcceptsPaddingWhitespaceAndStandardAlphabet() throws {
        let canonical = PyrogramSessionStringTests.vectorOneString
        let expected = try PyrogramSessionString(decoding: canonical)

        XCTAssertEqual(try PyrogramSessionString(decoding: canonical + "=="), expected)
        XCTAssertEqual(try PyrogramSessionString(decoding: "  \n\(canonical)\n  "), expected)
        let standardAlphabet = canonical.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        XCTAssertEqual(try PyrogramSessionString(decoding: standardAlphabet), expected)
    }

    func testRejectsEmptyString() {
        XCTAssertThrowsError(try PyrogramSessionString(decoding: "   ")) { error in
            XCTAssertEqual(error as? PyrogramSessionStringError, .empty)
        }
    }

    func testRejectsNonBase64() {
        XCTAssertThrowsError(try PyrogramSessionString(decoding: "not*valid*base64")) { error in
            XCTAssertEqual(error as? PyrogramSessionStringError, .notBase64)
        }
    }

    func testRejectsWrongDecodedSize() {
        let short = Data(count: 100).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try PyrogramSessionString(decoding: short)) { error in
            XCTAssertEqual(error as? PyrogramSessionStringError, .invalidSize(100))
        }
    }

    func testRejectsAllZeroAuthKey() {
        // A 271-byte payload with a valid dc/api/user id but a blank auth key.
        var bytes = Data()
        bytes.append(2)
        bytes.append(contentsOf: [0x00, 0x00, 0x07, 0xf8])
        bytes.append(0)
        bytes.append(Data(count: PyrogramSessionString.authKeySize))
        bytes.append(contentsOf: [0, 0, 0, 0, 0, 0x0b, 0xdb, 0x28])
        bytes.append(0)
        let encoded = bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try PyrogramSessionString(decoding: encoded)) { error in
            XCTAssertEqual(error as? PyrogramSessionStringError, .emptyAuthKey)
        }
    }

    func testEncodeRejectsShortAuthKey() {
        let session = PyrogramSessionString(dcId: 2, apiId: 2040, testMode: false, authKey: Data(count: 32), userId: 1, isBot: false)
        XCTAssertThrowsError(try session.encoded()) { error in
            XCTAssertEqual(error as? PyrogramSessionStringError, .invalidAuthKeySize(32))
        }
    }

    func testValidateDetectsUserMismatch() throws {
        let session = try PyrogramSessionString(decoding: PyrogramSessionStringTests.vectorOneString)
        XCTAssertNoThrow(try session.validate(expectedUserId: 777000))
        XCTAssertThrowsError(try session.validate(expectedUserId: 42)) { error in
            XCTAssertEqual(error as? PyrogramSessionStringError, .userIdMismatch(expected: 42, found: 777000))
        }
    }

    // Golden values from Python: struct.unpack("<q", hashlib.sha1(key).digest()[-8:])
    func testAuthKeyIdMatchesMTProtoDerivation() {
        let digestOne = Data([0xc7, 0xff, 0x3a, 0x4e, 0x52, 0x03, 0x17, 0x07, 0x62, 0xe3, 0xbe, 0x30, 0x70, 0x8e, 0x00, 0x99, 0x87, 0xe0, 0x0d, 0xda])
        XCTAssertEqual(PyrogramSessionString.authKeyId(sha1Digest: digestOne), -2_734_282_525_751_865_744)

        let digestTwo = Data([0x5b, 0xb4, 0x8c, 0x1e, 0x44, 0x2f, 0xd1, 0xb0, 0x6a, 0x76, 0xc7, 0xa8, 0x96, 0xd1, 0xb1, 0x0e, 0x8f, 0x72, 0x4a, 0x13])
        XCTAssertEqual(PyrogramSessionString.authKeyId(sha1Digest: digestTwo), 1_390_049_393_749_643_670)
    }
}

final class NagramSessionBackupRecordTests: XCTestCase {
    private static let sessionString = PyrogramSessionStringTests.mithkaSampleSessionString

    func testEncodesTheFormatMithkaRequires() throws {
        let record = NagramSessionBackupRecord(
            accountId: "777000",
            userId: 777000,
            name: "Nagram User",
            phone: "+1 234",
            createdAt: Date(timeIntervalSince1970: 1_787_000_000),
            storage: .synced,
            sessionString: NagramSessionBackupRecordTests.sessionString
        )
        let data = try record.encoded()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Mithka's decoder rejects any other marker, and reads these keys.
        XCTAssertEqual(object["format"] as? String, "mithka.tdlib.session_string.v2.explicit_consent")
        XCTAssertEqual(object["id"] as? String, "777000")
        XCTAssertEqual(object["accountId"] as? String, "777000")
        XCTAssertEqual(object["userId"] as? Int64, 777000)
        XCTAssertEqual(object["name"] as? String, "Nagram User")
        XCTAssertEqual(object["phone"] as? String, "+1 234")
        XCTAssertEqual(object["storage"] as? String, "synced")
        XCTAssertEqual(object["sessionString"] as? String, NagramSessionBackupRecordTests.sessionString)
        // Dart's DateTime.tryParse reads this shape back.
        XCTAssertEqual(object["createdAt"] as? String, "2026-08-17T20:53:20.000Z")
        XCTAssertNotNil(object["slot"])
    }

    func testDecodesRecordProducedByMithka() throws {
        // Literal output of Mithka's AccountBackupService._encode.
        let json = """
        {"format":"mithka.tdlib.session_string.v2.explicit_consent","id":"424242424242","accountId":"424242424242","slot":3,"userId":424242424242,"name":"Mithka User","phone":"+81 90","storage":"synced","createdAt":"2026-08-20T11:22:33.444Z","sessionString":"\(NagramSessionBackupRecordTests.sessionString)"}
        """
        let record = try NagramSessionBackupRecord(decoding: Data(json.utf8))
        XCTAssertEqual(record.accountId, "424242424242")
        XCTAssertEqual(record.userId, 424_242_424_242)
        XCTAssertEqual(record.name, "Mithka User")
        XCTAssertEqual(record.phone, "+81 90")
        XCTAssertEqual(record.storage, .synced)
        XCTAssertEqual(record.slot, 3)
        XCTAssertEqual(record.sessionString, NagramSessionBackupRecordTests.sessionString)
        XCTAssertEqual(NagramSessionBackupRecord.dateFormatter.string(from: record.createdAt), "2026-08-20T11:22:33.444Z")
        XCTAssertNoThrow(try record.session())
    }

    func testRoundTripsThroughOurOwnEncoder() throws {
        let original = NagramSessionBackupRecord(
            accountId: "777000",
            userId: 777000,
            name: "Round Trip",
            phone: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.25),
            storage: .local,
            sessionString: NagramSessionBackupRecordTests.sessionString,
            slot: 0
        )
        let decoded = try NagramSessionBackupRecord(decoding: try original.encoded())
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.phone)
        XCTAssertEqual(decoded.storage, .local)
    }

    func testAcceptsLegacyMithkaFormat() throws {
        let json = """
        {"format":"mithka.tdlib.session_string.v1","id":"777000","sessionString":"\(NagramSessionBackupRecordTests.sessionString)"}
        """
        let record = try NagramSessionBackupRecord(decoding: Data(json.utf8))
        XCTAssertEqual(record.accountId, "777000")
        // Falls back to the account id when the legacy record omits userId.
        XCTAssertEqual(record.userId, 777000)
    }

    func testRejectsUnknownFormat() {
        let json = #"{"format":"something.else","id":"1","sessionString":"abc"}"#
        XCTAssertThrowsError(try NagramSessionBackupRecord(decoding: Data(json.utf8))) { error in
            XCTAssertEqual(error as? NagramSessionBackupRecordError, .unsupportedFormat("something.else"))
        }
    }

    func testRejectsMissingSessionStringAndAccountId() {
        let noSession = #"{"format":"mithka.tdlib.session_string.v2.explicit_consent","id":"1","sessionString":"  "}"#
        XCTAssertThrowsError(try NagramSessionBackupRecord(decoding: Data(noSession.utf8))) { error in
            XCTAssertEqual(error as? NagramSessionBackupRecordError, .missingSessionString)
        }
        let noAccount = #"{"format":"mithka.tdlib.session_string.v2.explicit_consent","sessionString":"abc"}"#
        XCTAssertThrowsError(try NagramSessionBackupRecord(decoding: Data(noAccount.utf8))) { error in
            XCTAssertEqual(error as? NagramSessionBackupRecordError, .missingAccountId)
        }
        XCTAssertThrowsError(try NagramSessionBackupRecord(decoding: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? NagramSessionBackupRecordError, .notJSON)
        }
    }

    func testDisplayNameFallsBackToAccountId() {
        let record = NagramSessionBackupRecord(accountId: "777000", userId: 777000, name: "   ", phone: nil, createdAt: Date(), storage: .synced, sessionString: NagramSessionBackupRecordTests.sessionString)
        XCTAssertEqual(record.displayName, "777000")
        XCTAssertEqual(record.sizeBytes, 362)
    }
}

extension PyrogramSessionStringTests {
    // Shared valid session string for envelope tests.
    static let mithkaSampleSessionString = PyrogramSessionStringTests.vectorOneString
}
