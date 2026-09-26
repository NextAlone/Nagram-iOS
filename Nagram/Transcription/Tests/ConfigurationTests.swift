import Foundation

// Standalone checks of the real NagramSTTConfiguration.swift. Compile only these
// two files; these in-memory stubs intentionally replace Settings and Keychain.
// This does not access user preferences, credentials, or the network, and is not
// an app build or a substitute for iOS integration validation.
//
// xcrun swiftc -module-cache-path /tmp/nagram-stt-module-cache \
//   Nagram/Settings/NagramSTTConfiguration.swift \
//   Nagram/Transcription/Tests/ConfigurationTests.swift \
//   -o /tmp/nagram-stt-configuration-tests
// /tmp/nagram-stt-configuration-tests

final class NagramSettings {
    static let shared = NagramSettings()
    var sttBaseURL = ""
    var sttEndpoint = ""
    var sttModel = ""
    var sttLanguage = ""
    var sttPrompt = ""
}

enum StubCredentialError: Error {
    case unavailable
}

enum NagramSTTKeychain {
    static var value = ""
    static var failure: StubCredentialError?
    static var readCount = 0

    static func read() throws -> String {
        self.readCount += 1
        if let failure = self.failure {
            throw failure
        }
        return self.value
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private final class ConfigurationTestSuite {
    private(set) var assertionCount = 0

    func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw TestFailure(description: message)
        }
        self.assertionCount += 1
    }

    func expectError(_ expected: NagramSTTConfigurationError, _ label: String, operation: () throws -> NagramSTTConfiguration) throws {
        do {
            _ = try operation()
            throw TestFailure(description: "\(label): expected a configuration error")
        } catch let actual as NagramSTTConfigurationError {
            try self.expect(actual.localizationKey == expected.localizationKey, "\(label): wrong configuration error (\(actual.localizationKey))")
        }
    }

    func configuration(baseURL: String = "", endpoint: String = "", model: String = "test-transcription-model", language: String = "", prompt: String = "", apiKey: String = "fictional-test-key") throws -> NagramSTTConfiguration {
        return try NagramSTTConfiguration(baseURL: baseURL, endpoint: endpoint, model: model, language: language, prompt: prompt, apiKey: apiKey)
    }

    func run() throws {
        let urls: [(String, String, String)] = [
            ("", "", "https://api.openai.com/v1/audio/transcriptions"),
            ("https://example.test", "", "https://example.test/v1/audio/transcriptions"),
            ("https://example.test/v1", "", "https://example.test/v1/audio/transcriptions"),
            ("https://example.test/proxy/v1///", "", "https://example.test/proxy/v1/audio/transcriptions"),
            ("https://example.test/proxy", "custom/transcribe", "https://example.test/proxy/custom/transcribe"),
            ("https://example.test/v1/", "/v1/audio/transcriptions", "https://example.test/v1/audio/transcriptions"),
            ("invalid base URL", "https://gateway.test/transcribe?tenant=sample", "https://gateway.test/transcribe?tenant=sample"),
            ("", "http://localhost:8080/transcriptions", "http://localhost:8080/transcriptions"),
            ("http://localhost:8080/v1", "", "http://localhost:8080/v1/audio/transcriptions"),
            ("http://127.0.0.1:9000", "", "http://127.0.0.1:9000/v1/audio/transcriptions"),
            ("http://[::1]:9000", "", "http://[::1]:9000/v1/audio/transcriptions")
        ]
        for (baseURL, endpoint, expectedURL) in urls {
            let configuration = try self.configuration(baseURL: baseURL, endpoint: endpoint)
            try self.expect(configuration.url.absoluteString == expectedURL, "URL construction: \(baseURL) + \(endpoint)")
        }

        let trimmed = try self.configuration(baseURL: " https://example.test/v1/ \n", endpoint: " /audio/transcriptions \n", model: " model-name \n", language: " ZH \n", prompt: " proper names \n", apiKey: " fictional-key \n")
        try self.expect(trimmed.url.absoluteString == "https://example.test/v1/audio/transcriptions", "trimmed URL")
        try self.expect(trimmed.baseURL == "https://example.test/v1/", "trimmed base URL")
        try self.expect(trimmed.endpoint == "/audio/transcriptions", "trimmed endpoint")
        try self.expect(trimmed.model == "model-name", "trimmed model")
        try self.expect(trimmed.language == "zh", "normalized language")
        try self.expect(trimmed.prompt == "proper names", "trimmed prompt")
        try self.expect(trimmed.apiKey == "fictional-key", "trimmed key")

        for language in ["", "en", "ja", "zh", " EN "] {
            let configuration = try self.configuration(language: language)
            try self.expect(configuration.language == language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), "valid language: \(language)")
        }
        for language in ["en-US", "auto", "e", "123", "中文", "éa"] {
            try self.expectError(.invalidLanguage, "invalid language: \(language)") {
                try self.configuration(language: language)
            }
        }
        for model in ["", " \n\t"] {
            try self.expectError(.missingModel, "empty model") {
                try self.configuration(model: model)
            }
        }
        try self.expectError(.missingAPIKey, "official missing key") {
            try self.configuration(apiKey: " \n")
        }
        try self.expectError(.missingAPIKey, "official host is case insensitive") {
            try self.configuration(baseURL: "https://API.OPENAI.COM", apiKey: "")
        }
        try self.expectError(.invalidURL, "official requires HTTPS") {
            try self.configuration(baseURL: "http://api.openai.com")
        }
        let keylessLocal = try self.configuration(baseURL: "http://localhost:8080", apiKey: "")
        try self.expect(keylessLocal.apiKey.isEmpty, "keyless local service")
        let keylessGateway = try self.configuration(baseURL: "https://gateway.test", apiKey: "")
        try self.expect(keylessGateway.apiKey.isEmpty, "keyless custom service")
        let overriddenOfficial = try self.configuration(endpoint: "http://localhost:8080/transcriptions", apiKey: "")
        try self.expect(overriddenOfficial.apiKey.isEmpty, "full local endpoint overrides the default official base")

        for baseURL in ["ftp://example.test", "https://", "not-a-url", "https://user:password@example.test"] {
            try self.expectError(.invalidURL, "invalid base URL: \(baseURL)") {
                try self.configuration(baseURL: baseURL)
            }
        }
        for endpoint in ["ftp://example.test/transcribe", "https://", "https://user:password@example.test/transcribe", "https://example.test/transcribe#fragment"] {
            try self.expectError(.invalidURL, "invalid full endpoint: \(endpoint)") {
                try self.configuration(endpoint: endpoint)
            }
        }

        let original = try self.configuration()
        let equal = try self.configuration()
        let different = try self.configuration(model: "other-model")
        try self.expect(original == equal, "equal snapshots")
        try self.expect(original != different, "different snapshots")
        try self.expect(original.language.isEmpty && original.prompt.isEmpty, "empty optional wire fields")

        let settings = NagramSettings.shared
        settings.sttBaseURL = "http://localhost:8080"
        settings.sttModel = "stored-model"
        settings.sttLanguage = "ja"
        settings.sttPrompt = "stored hint"
        NagramSTTKeychain.value = "stored-fictional-key"
        let snapshot = try NagramSTTConfiguration.current()
        try self.expect(snapshot.model == "stored-model", "current reads model from in-memory settings")
        try self.expect(snapshot.language == "ja" && snapshot.prompt == "stored hint", "current reads optional settings")
        try self.expect(snapshot.apiKey == "stored-fictional-key" && NagramSTTKeychain.readCount == 1, "current reads only the stub credential")
        settings.sttModel = "changed-model"
        NagramSTTKeychain.value = "changed-fictional-key"
        try self.expect(snapshot.model == "stored-model" && snapshot.apiKey == "stored-fictional-key", "configuration is an immutable snapshot")
        let refreshed = try NagramSTTConfiguration.current()
        try self.expect(refreshed.model == "changed-model" && refreshed.apiKey == "changed-fictional-key", "next snapshot sees changes")

        NagramSTTKeychain.failure = .unavailable
        do {
            _ = try NagramSTTConfiguration.current()
            throw TestFailure(description: "current must propagate credential read failure")
        } catch StubCredentialError.unavailable {
            self.assertionCount += 1
        }
        NagramSTTKeychain.failure = nil
        NagramSTTKeychain.value = ""
        try self.expect(try NagramSTTConfiguration.current().apiKey.isEmpty, "empty local credential after recovery")
    }
}

#if !STT_LIBRARY
@main
private struct ConfigurationTests {
    static func main() throws {
        let suite = ConfigurationTestSuite()
        try suite.run()
        print("PASS: \(suite.assertionCount) STT configuration assertions (real configuration source; in-memory credential/settings stubs).")
    }
}
#endif
