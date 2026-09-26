import Foundation

// MARK: NAGRAM — Command line front end for the session backup codec.
//
// Used by scripts/test-session-backup-interop.sh so the same Swift code the app
// ships can be driven from a shell and compared against the Pyrogram reference
// implementation and against Mithka's own Dart decoder.
//
//   session-encode <dcId> <apiId> <testMode> <authKeyHex> <userId> <isBot>
//   session-decode <sessionString>
//   authkeyid-from-sha1 <sha1DigestHex>
//   record-encode <accountId> <userId> <name> <phone> <iso8601> <sessionString> <slot> <storage>
//   record-decode <json>

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func data(fromHex hex: String) -> Data {
    var result = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        guard let byte = UInt8(hex[index ..< next], radix: 16) else {
            fail("invalid hex near offset \(hex.distance(from: hex.startIndex, to: index))")
        }
        result.append(byte)
        index = next
    }
    return result
}

func hex(from data: Data) -> String {
    return data.map { String(format: "%02x", $0) }.joined()
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("no command given")
}

do {
    switch command {
    case "session-encode":
        guard arguments.count == 7 else { fail("session-encode needs 6 arguments") }
        guard let dcId = Int32(arguments[1]), let apiId = Int32(arguments[2]), let userId = Int64(arguments[5]) else {
            fail("session-encode got a non-numeric argument")
        }
        let session = PyrogramSessionString(
            dcId: dcId,
            apiId: apiId,
            testMode: arguments[3] == "1",
            authKey: data(fromHex: arguments[4]),
            userId: userId,
            isBot: arguments[6] == "1"
        )
        print(try session.encoded())

    case "session-decode":
        guard arguments.count == 2 else { fail("session-decode needs 1 argument") }
        let session = try PyrogramSessionString(decoding: arguments[1])
        print([
            String(session.dcId),
            String(session.apiId),
            session.testMode ? "1" : "0",
            hex(from: session.authKey),
            String(session.userId),
            session.isBot ? "1" : "0"
        ].joined(separator: "\t"))

    case "authkeyid-from-sha1":
        guard arguments.count == 2 else { fail("authkeyid-from-sha1 needs 1 argument") }
        print(PyrogramSessionString.authKeyId(sha1Digest: data(fromHex: arguments[1])))

    case "record-encode":
        guard arguments.count == 9 else { fail("record-encode needs 8 arguments") }
        guard let userId = Int64(arguments[2]), let slot = Int(arguments[7]) else {
            fail("record-encode got a non-numeric argument")
        }
        guard let createdAt = NagramSessionBackupRecord.dateFormatter.date(from: arguments[5]) else {
            fail("record-encode could not parse the date \(arguments[5])")
        }
        guard let storage = NagramSessionBackupStorage(rawValue: arguments[8]) else {
            fail("record-encode got an unknown storage \(arguments[8])")
        }
        let record = NagramSessionBackupRecord(
            accountId: arguments[1],
            userId: userId,
            name: arguments[3],
            phone: arguments[4].isEmpty ? nil : arguments[4],
            createdAt: createdAt,
            storage: storage,
            sessionString: arguments[6],
            slot: slot
        )
        guard let json = String(data: try record.encoded(), encoding: .utf8) else {
            fail("record-encode produced invalid UTF-8")
        }
        print(json)

    case "record-decode":
        guard arguments.count == 2 else { fail("record-decode needs 1 argument") }
        let record = try NagramSessionBackupRecord(decoding: Data(arguments[1].utf8))
        print([
            record.accountId,
            String(record.userId),
            record.name,
            record.phone ?? "",
            NagramSessionBackupRecord.dateFormatter.string(from: record.createdAt),
            String(record.sizeBytes),
            record.storage.rawValue,
            record.sessionString
        ].joined(separator: "\t"))

    default:
        fail("unknown command \(command)")
    }
} catch {
    fail("\(error)")
}
