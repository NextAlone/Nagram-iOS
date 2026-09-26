import Foundation
import Security

public struct NagramSTTKeychainError: LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let detail = SecCopyErrorMessageString(self.status, nil) as String? ?? "Unknown Keychain error"
        return "Unable to access the speech-to-text API key: \(detail) (\(self.status))."
    }
}

enum NagramSTTKeychain {
    private static var query: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: NagramDemoMode.isEnabled ? "xyz.nextalone.nagram.stt.demo" : "xyz.nextalone.nagram.stt",
            kSecAttrAccount as String: "api-key"
        ]
    }

    static func read() throws -> String {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess else {
            throw NagramSTTKeychainError(status: status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw NagramSTTKeychainError(status: errSecDecode)
        }
        return value
    }

    static func write(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(self.query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NagramSTTKeychainError(status: status)
            }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(self.query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = self.query
            for (key, value) in attributes {
                query[key] = value
            }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NagramSTTKeychainError(status: status)
        }
    }
}
