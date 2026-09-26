import Foundation

public enum NagramSTTConfigurationError: LocalizedError {
    case invalidURL
    case missingModel
    case missingAPIKey
    case invalidLanguage

    public var localizationKey: String {
        switch self {
        case .invalidURL:
            return "Nagram.STT.Error.InvalidURL"
        case .missingModel:
            return "Nagram.STT.Error.MissingModel"
        case .missingAPIKey:
            return "Nagram.STT.Error.MissingAPIKey"
        case .invalidLanguage:
            return "Nagram.STT.Error.InvalidLanguage"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid HTTP or HTTPS API URL without embedded credentials. OpenAI requires HTTPS."
        case .missingModel:
            return "Enter a speech-to-text model name."
        case .missingAPIKey:
            return "An API key is required for api.openai.com."
        case .invalidLanguage:
            return "Use a two-letter language code such as zh or en, or leave it empty for automatic detection."
        }
    }
}

public struct NagramSTTConfiguration: Equatable {
    public static let defaultBaseURL = "https://api.openai.com"
    public static let defaultEndpoint = "/v1/audio/transcriptions"

    public let baseURL: String
    public let endpoint: String
    public let model: String
    public let language: String
    public let prompt: String
    public let apiKey: String
    public let url: URL

    public init(baseURL: String, endpoint: String, model: String, language: String, prompt: String, apiKey: String) throws {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var components: URLComponents?
        if let endpointComponents = URLComponents(string: self.endpoint), endpointComponents.scheme != nil {
            components = endpointComponents
        } else {
            components = URLComponents(string: self.baseURL.isEmpty ? Self.defaultBaseURL : self.baseURL)
            if var value = components {
                var basePath = value.path
                while basePath.hasSuffix("/") {
                    basePath.removeLast()
                }
                var endpointPath = self.endpoint.isEmpty ? Self.defaultEndpoint : self.endpoint
                if !endpointPath.hasPrefix("/") {
                    endpointPath = "/\(endpointPath)"
                }
                if basePath.hasSuffix("/v1"), endpointPath.hasPrefix("/v1/") {
                    endpointPath = String(endpointPath.dropFirst(3))
                }
                value.path = basePath + endpointPath
                value.query = nil
                value.fragment = nil
                components = value
            }
        }
        guard let components, let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil, components.fragment == nil, let url = components.url else {
            throw NagramSTTConfigurationError.invalidURL
        }
        if host.lowercased() == "api.openai.com", scheme != "https" {
            throw NagramSTTConfigurationError.invalidURL
        }
        self.url = url
        guard !self.model.isEmpty else {
            throw NagramSTTConfigurationError.missingModel
        }
        if host.lowercased() == "api.openai.com", self.apiKey.isEmpty {
            throw NagramSTTConfigurationError.missingAPIKey
        }
        if !self.language.isEmpty, self.language.utf8.count != 2 || !self.language.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }) {
            throw NagramSTTConfigurationError.invalidLanguage
        }
    }

    public static func current() throws -> NagramSTTConfiguration {
        let settings = NagramSettings.shared
        return try NagramSTTConfiguration(baseURL: settings.sttBaseURL, endpoint: settings.sttEndpoint, model: settings.sttModel, language: settings.sttLanguage, prompt: settings.sttPrompt, apiKey: NagramSTTKeychain.read())
    }
}
