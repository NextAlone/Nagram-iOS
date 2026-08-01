import Foundation
import MtProtoKit
import Postbox
import SwiftSignalKit
import TelegramCore

public enum NagramReviewSessionError: Error {
    case invalidCode
    case invalidConfiguration
    case network
    case unauthorized
    case sessionUnavailable
    case invalidResponse
    case invalidSession
    case unsupportedSession
}

private struct NagramReviewSessionConfiguration {
    let endpoint: URL
    let bearerToken: String

    init?() {
        guard let url = Bundle.main.url(forResource: "NagramReviewSession", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }

        guard let endpointValue = dictionary["endpoint"] as? String,
              let endpoint = URL(string: endpointValue),
              endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil,
              endpoint.user == nil,
              endpoint.password == nil,
              let bearerToken = dictionary["bearer_token"] as? String,
              !bearerToken.isEmpty
        else {
            return nil
        }

        self.endpoint = endpoint
        self.bearerToken = bearerToken
    }
}

private struct NagramReviewSessionResponse: Decodable {
    let sessionString: String
    let phoneNumber: String

    private enum CodingKeys: String, CodingKey {
        case sessionString = "session_string"
        case phoneNumber = "phone_number"
    }
}

private struct NagramParsedReviewSession {
    let datacenterId: Int32
    let isTestingEnvironment: Bool
    let authKey: Data
    let authKeyId: Int64
    let peerId: PeerId
    let isBot: Bool
}

private final class NagramReviewSessionURLDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public enum NagramReviewSession {
    private static let configuration = NagramReviewSessionConfiguration()

    public static func hasReviewPhoneNumberPrefix(_ phoneNumber: String) -> Bool {
        return self.normalizedPhoneNumber(phoneNumber).hasPrefix("+99999")
    }

    public static func requestAndImport(
        accountManager: AccountManager<TelegramAccountManagerTypes>,
        phoneNumber: String,
        code: String
    ) -> Signal<Void, NagramReviewSessionError> {
        guard let configuration else {
            return .fail(.invalidConfiguration)
        }
        let normalizedPhoneNumber = self.normalizedPhoneNumber(phoneNumber)
        guard normalizedPhoneNumber.hasPrefix("+99999"),
              code.count == 5,
              code.unicodeScalars.allSatisfy({ (48 ... 57).contains($0.value) })
        else {
            return .fail(.invalidCode)
        }

        return self.requestSession(
            configuration: configuration,
            phoneNumber: normalizedPhoneNumber,
            code: code
        )
        |> mapToSignal { sessionString -> Signal<Void, NagramReviewSessionError> in
            guard let session = self.parseSessionString(sessionString) else {
                return .fail(.invalidSession)
            }
            guard !session.isBot else {
                return .fail(.unsupportedSession)
            }

            return accountManager.transaction { transaction -> Void in
                let nextSortOrder = (transaction.getRecords().map { record -> Int32 in
                    for attribute in record.attributes {
                        if case let .sortOrder(sortOrder) = attribute {
                            return sortOrder.order
                        }
                    }
                    return 0
                }.max() ?? 0) + 1

                let backupData = AccountBackupData(
                    masterDatacenterId: session.datacenterId,
                    peerId: session.peerId.toInt64(),
                    masterDatacenterKey: session.authKey,
                    masterDatacenterKeyId: session.authKeyId,
                    notificationEncryptionKeyId: nil,
                    notificationEncryptionKey: nil,
                    additionalDatacenterKeys: [:]
                )
                let environment: AccountEnvironment = session.isTestingEnvironment ? .test : .production
                let id = transaction.createRecord([
                    .environment(AccountEnvironmentAttribute(environment: environment)),
                    .sortOrder(AccountSortOrderAttribute(order: nextSortOrder)),
                    .backupData(AccountBackupDataAttribute(data: backupData)),
                ])
                transaction.setCurrentId(id)
                transaction.removeAuth()
            }
            |> castError(NagramReviewSessionError.self)
        }
    }

    fileprivate static func normalizedPhoneNumber(_ value: String) -> String {
        let digits = value.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            return (48 ... 57).contains(scalar.value) ? scalar : nil
        }
        return "+" + String(String.UnicodeScalarView(digits))
    }

    private static func requestSession(
        configuration: NagramReviewSessionConfiguration,
        phoneNumber: String,
        code: String
    ) -> Signal<String, NagramReviewSessionError> {
        let body: [String: String] = [
            "phone_number": phoneNumber,
            "otp": code,
            "request_id": UUID().uuidString,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .fail(.invalidConfiguration)
        }

        var request = URLRequest(url: configuration.endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        return Signal { subscriber in
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            sessionConfiguration.urlCache = nil
            sessionConfiguration.httpCookieStorage = nil
            sessionConfiguration.httpShouldSetCookies = false
            sessionConfiguration.waitsForConnectivity = false
            sessionConfiguration.timeoutIntervalForRequest = 10.0
            sessionConfiguration.timeoutIntervalForResource = 10.0

            let delegate = NagramReviewSessionURLDelegate()
            let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request) { data, response, error in
                defer {
                    session.finishTasksAndInvalidate()
                }

                if error != nil {
                    subscriber.putError(.network)
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    subscriber.putError(.invalidResponse)
                    return
                }
                guard response.statusCode == 200 else {
                    switch response.statusCode {
                    case 401:
                        subscriber.putError(.unauthorized)
                    case 403:
                        subscriber.putError(.invalidCode)
                    case 503:
                        subscriber.putError(.sessionUnavailable)
                    default:
                        subscriber.putError(.invalidResponse)
                    }
                    return
                }
                guard let data,
                      let response = try? JSONDecoder().decode(NagramReviewSessionResponse.self, from: data),
                      self.normalizedPhoneNumber(response.phoneNumber) == phoneNumber,
                      !response.sessionString.isEmpty
                else {
                    subscriber.putError(.invalidResponse)
                    return
                }

                subscriber.putNext(response.sessionString)
                subscriber.putCompletion()
            }
            task.resume()

            return ActionDisposable {
                task.cancel()
                session.invalidateAndCancel()
                _ = delegate
            }
        }
    }

    private static func parseSessionString(_ value: String) -> NagramParsedReviewSession? {
        guard !value.isEmpty,
              !value.contains("="),
              value.unicodeScalars.allSatisfy({ scalar in
                  return (48 ... 57).contains(scalar.value)
                      || (65 ... 90).contains(scalar.value)
                      || (97 ... 122).contains(scalar.value)
                      || scalar == "-"
                      || scalar == "_"
              })
        else {
            return nil
        }

        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard base64.count % 4 != 1 else {
            return nil
        }
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64), data.count == 271 else {
            return nil
        }

        let bytes = [UInt8](data)
        let datacenterId = bytes[0]
        let apiId = self.readUInt32BigEndian(bytes, offset: 1)
        let testMode = bytes[5]
        let authKey = Data(bytes[6 ..< 262])
        let userId = self.readUInt64BigEndian(bytes, offset: 262)
        let bot = bytes[270]

        guard datacenterId != 0,
              apiId != 0,
              testMode <= 1,
              !authKey.allSatisfy({ $0 == 0 }),
              userId != 0,
              userId <= 0x00ff_ffff_ffff_ffff,
              bot <= 1
        else {
            return nil
        }

        let digest = [UInt8](MTSha1(authKey))
        guard digest.count == 20 else {
            return nil
        }
        var authKeyIdBits: UInt64 = 0
        for index in 0 ..< 8 {
            authKeyIdBits |= UInt64(digest[12 + index]) << UInt64(index * 8)
        }

        let rawUserId = Int64(userId)
        let peerId = PeerId(
            namespace: Namespaces.Peer.CloudUser,
            id: PeerId.Id._internalFromInt64Value(rawUserId)
        )
        return NagramParsedReviewSession(
            datacenterId: Int32(datacenterId),
            isTestingEnvironment: testMode == 1,
            authKey: authKey,
            authKeyId: Int64(bitPattern: authKeyIdBits),
            peerId: peerId,
            isBot: bot == 1
        )
    }

    private static func readUInt32BigEndian(_ bytes: [UInt8], offset: Int) -> UInt32 {
        var result: UInt32 = 0
        for index in 0 ..< 4 {
            result = (result << 8) | UInt32(bytes[offset + index])
        }
        return result
    }

    private static func readUInt64BigEndian(_ bytes: [UInt8], offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0 ..< 8 {
            result = (result << 8) | UInt64(bytes[offset + index])
        }
        return result
    }
}
