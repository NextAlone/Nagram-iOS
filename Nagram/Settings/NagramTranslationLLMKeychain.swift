import Foundation
import Security

// MARK: NAGRAM — Local-only storage for LLM translation credentials.
enum NagramTranslationLLMKeychain {
    private static let service = NagramDemoMode.isEnabled
        ? "xyz.nextalone.nagram.translation.llm.demo"
        : "xyz.nextalone.nagram.translation.llm"
    private static let account = "api-key"
    private static let legacyDefaultsKey = "nagram.translationLLMAPIKey"

    static var apiKey: String {
        get {
            if let value = self.read(), !value.isEmpty {
                return value
            }
            let legacyValue = NagramDemoMode.userDefaults.string(forKey: self.legacyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacyValue.isEmpty {
                self.write(legacyValue)
                NagramDemoMode.userDefaults.removeObject(forKey: self.legacyDefaultsKey)
            }
            return legacyValue
        }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            NagramDemoMode.userDefaults.removeObject(forKey: self.legacyDefaultsKey)
            if value.isEmpty {
                self.delete()
            } else {
                self.write(value)
            }
        }
    }

    private static func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account
        ]
    }

    private static func read() -> String? {
        var query = self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        let data = Data(value.utf8)
        let query = self.baseQuery()
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func delete() {
        SecItemDelete(self.baseQuery() as CFDictionary)
    }
}
