import Foundation
import NaturalLanguage

// MARK: NAGRAM — the language of a message's text, for the translate button beside messages.

public enum NagramMessageLanguage {
    private final class Box {
        let language: String?

        init(_ language: String?) {
            self.language = language
        }
    }

    // NSCache is thread-safe: bubbles lay out off the main thread.
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 1000
        return cache
    }()

    /// The dominant language of `text` as a translation code ("zh", "en", "no"), or nil when it cannot be told
    /// (emoji, numbers, a few letters). `key` identifies the text (a message's stable id and its text's hash).
    public static func dominantLanguage(key: String, text: String) -> String? {
        let cacheKey = key as NSString
        if let cached = self.cache.object(forKey: cacheKey) {
            return cached.language
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(256)))
        let language = recognizer.dominantLanguage.map { normalizedTranslationLanguage($0.rawValue) }
        self.cache.setObject(Box(language), forKey: cacheKey)
        return language
    }

    /// Same normalization as TranslateUI's `normalizeTranslationLanguage`: drop the region or script, and
    /// Norwegian Bokmål is "no".
    public static func normalizedTranslationLanguage(_ code: String) -> String {
        var code = code
        if let separator = code.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            code = String(code[..<separator])
        }
        if code == "nb" {
            code = "no"
        }
        return code.lowercased()
    }
}
