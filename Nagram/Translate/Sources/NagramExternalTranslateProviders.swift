import Foundation
import NagramSettings
import SwiftSignalKit
import TelegramCore

// MARK: NAGRAM — External translation providers imported from Android Nagram/Nnngram patterns.
func nagramExternalTranslate(provider: NagramTranslationProvider, text: String, fromLang: String?, toLang: String, context: [String] = [], isHTML: Bool = false) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    guard !text.isEmpty else {
        return .fail(.textIsEmpty)
    }

    switch provider {
    case .google, .googleCN:
        return nagramGoogleTranslate(provider: provider, text: text, toLang: toLang)
    case .microsoft:
        return nagramMicrosoftTranslate(text: text, toLang: toLang)
    case .yandex:
        return nagramYandexTranslate(text: text, fromLang: fromLang, toLang: toLang)
    case .transmart:
        return nagramTranSmartTranslate(text: text, fromLang: fromLang, toLang: toLang)
    case .llm:
        return nagramLLMTranslate(text: text, fromLang: fromLang, toLang: toLang, context: context, isHTML: isHTML)
    case .telegram:
        return .fail(.generic)
    }
}

private func nagramGoogleTranslate(provider: NagramTranslationProvider, text: String, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    var components = URLComponents()
    components.scheme = "https"
    components.host = provider == .googleCN ? "translate.google.cn" : "translate.google.com"
    components.path = "/translate_a/single"
    components.queryItems = [
        URLQueryItem(name: "dj", value: "1"),
        URLQueryItem(name: "q", value: text),
        URLQueryItem(name: "sl", value: "auto"),
        URLQueryItem(name: "tl", value: nagramTargetLanguage(toLang, provider: provider)),
        URLQueryItem(name: "ie", value: "UTF-8"),
        URLQueryItem(name: "oe", value: "UTF-8"),
        URLQueryItem(name: "client", value: "at"),
        URLQueryItem(name: "dt", value: "t"),
        URLQueryItem(name: "otf", value: "2")
    ]
    guard let url = components.url else {
        return .fail(.generic)
    }
    var request = URLRequest(url: url)
    request.setValue("GoogleTranslate/6.28.0.05.421483610 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")

    return nagramHTTPRequest(request, provider: provider)
    |> mapToSignal { data -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sentences = object["sentences"] as? [[String: Any]]
        else {
            return .fail(.generic)
        }
        let result = sentences.compactMap { $0["trans"] as? String }.joined()
        return .single((result, []))
    }
}

private func nagramMicrosoftTranslate(text: String, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    guard let url = URL(string: "https://www.bing.com/ttranslatev3") else {
        return .fail(.generic)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = nagramFormBody([
        URLQueryItem(name: "fromLang", value: "auto-detect"),
        URLQueryItem(name: "text", value: text),
        URLQueryItem(name: "to", value: nagramTargetLanguage(toLang, provider: .microsoft))
    ])
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

    return nagramHTTPRequest(request, provider: .microsoft)
    |> mapToSignal { data -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let translations = first["translations"] as? [[String: Any]],
              let result = translations.first?["text"] as? String
        else {
            return .fail(.generic)
        }
        return .single((result, []))
    }
}

private func nagramYandexTranslate(text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "translate.yandex.net"
    components.path = "/api/v1/tr.json/translate"
    let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    components.queryItems = [
        URLQueryItem(name: "srv", value: "android"),
        URLQueryItem(name: "uuid", value: uuid),
        URLQueryItem(name: "id", value: "\(requestId)-9-0")
    ]
    guard let url = components.url else {
        return .fail(.generic)
    }
    let target = nagramTargetLanguage(toLang, provider: .yandex)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let source = fromLang.flatMap { $0.isEmpty || $0 == "auto" ? nil : nagramTargetLanguage($0, provider: .yandex) }
    request.httpBody = nagramFormBody([
        URLQueryItem(name: "text", value: text),
        URLQueryItem(name: "lang", value: source.map { "\($0)-\(target)" } ?? target)
    ])
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("Mozilla/5.0 (Linux; Android 10; SM-G9600) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.0 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")

    return nagramHTTPRequest(request, provider: .yandex)
    |> mapToSignal { data -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? Int,
              code == 200,
              let texts = object["text"] as? [String],
              let result = texts.first
        else {
            return .fail(.generic)
        }
        return .single((result, []))
    }
}

private func nagramTranSmartTranslate(text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let target = nagramTargetLanguage(toLang, provider: .transmart)
    let supported: Set<String> = ["ar", "fr", "fil", "lo", "ja", "it", "hi", "id", "vi", "de", "km", "ms", "th", "tr", "zh", "ru", "ko", "pt", "es"]
    guard supported.contains(target) else {
        return .fail(.invalidLanguage)
    }
    guard let url = URL(string: "https://transmart.qq.com/api/imt") else {
        return .fail(.generic)
    }
    let sourceLang = fromLang.map { nagramTargetLanguage($0, provider: .transmart) }.flatMap { supported.contains($0) ? $0 : nil } ?? "en"
    let body: [String: Any] = [
        "header": [
            "client_key": "browser-chrome-120.0.0-Mac OS-\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970 * 1000.0))",
            "fn": "auto_translation",
            "session": "",
            "user": ""
        ],
        "source": [
            "lang": sourceLang,
            "text_list": text.components(separatedBy: "\n")
        ],
        "target": [
            "lang": target
        ],
        "model_category": "normal",
        "text_domain": "",
        "type": "plain"
    ]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
        return .fail(.generic)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

    return nagramHTTPRequest(request, provider: .transmart)
    |> mapToSignal { data -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = object["auto_translation"] as? [String]
        else {
            return .fail(.generic)
        }
        return .single((translations.joined(separator: "\n"), []))
    }
}

func nagramHTTPRequest(_ request: URLRequest, provider: NagramTranslationProvider) -> Signal<Data, TranslationError> {
    return Signal { subscriber in
        var request = request
        request.timeoutInterval = provider == .llm ? 45.0 : 15.0
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                subscriber.putError(.generic)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                subscriber.putError(.generic)
                return
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                subscriber.putError(httpResponse.statusCode == 429 ? .limitExceeded : .generic)
                return
            }
            guard let data else {
                subscriber.putError(.generic)
                return
            }
            subscriber.putNext(data)
            subscriber.putCompletion()
        }
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

private func nagramFormBody(_ queryItems: [URLQueryItem]) -> Data? {
    var components = URLComponents()
    components.queryItems = queryItems
    return components.percentEncodedQuery?.data(using: .utf8)
}

func nagramTargetLanguage(_ language: String, provider: NagramTranslationProvider) -> String {
    switch provider {
    case .google, .googleCN:
        switch language.lowercased() {
        case "zh-hans", "zh-cn":
            return "zh-CN"
        case "zh-hant", "zh-tw", "zh-hk":
            return "zh-TW"
        default:
            return language
        }
    case .microsoft:
        switch language.lowercased() {
        case "zh-hans", "zh-cn":
            return "zh-Hans"
        case "zh-hant", "zh-tw", "zh-hk":
            return "zh-Hant"
        default:
            return language
        }
    case .yandex, .transmart:
        if language.lowercased().hasPrefix("zh") {
            return "zh"
        }
        return language
    case .telegram:
        var language = language.lowercased()
        if language.contains("-") {
            language = language.components(separatedBy: "-").first ?? language
        }
        if language == "nb" {
            return "no"
        }
        return language
    case .llm:
        return language
    }
}
