import Foundation
import AppBundle

// MARK: NAGRAM — 本地化管理器（精简：去掉远程下载/日志）。
// 从主 app bundle 的 <locale>.lproj/NagramLocalizable.strings 读取，未命中按 fallback 链回退，最终回退 en。

public let nagramFallbackLocale = "en"

public final class NagramLocalization {
    public static let shared = NagramLocalization()

    private let appBundle: Bundle
    private var localizations: [String: [String: String]] = [:]
    private let fallbackMappings: [String: String] = [
        "zh-hant": "zh-hans"
    ]

    private init() {
        self.appBundle = getAppBundle()
        for locale in self.appBundle.localizations where locale != "Base" {
            self.localizations[locale] = self.loadDictionary(for: locale)
        }
    }

    public func localizedString(_ key: String, _ locale: String = nagramFallbackLocale, args: CVarArg...) -> String {
        let sanitized = self.sanitize(locale)
        if let value = self.find(key, inLocale: sanitized) {
            return args.isEmpty ? value : String(format: value, arguments: args)
        }
        return key
    }

    private func loadDictionary(for locale: String) -> [String: String] {
        guard let path = self.appBundle.path(forResource: "NagramLocalizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
              let dictionary = NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String]
        else {
            return [:]
        }
        return dictionary
    }

    private func sanitize(_ locale: String) -> String {
        var result = locale
        let rawSuffix = "-raw"
        if result.hasSuffix(rawSuffix) {
            result = String(result.dropLast(rawSuffix.count))
        }
        return result
    }

    private func find(_ key: String, inLocale locale: String) -> String? {
        if let value = self.localizations[locale]?[key], !value.isEmpty {
            return value
        }
        if let fallback = self.fallbackMappings[locale] {
            return self.find(key, inLocale: fallback)
        }
        return self.localizations[nagramFallbackLocale]?[key]
    }
}

/// 便捷函数：`ngI18n("Nagram.X", lang)`。lang 通常取 `presentationData.strings.baseLanguageCode`。
public func ngI18n(_ key: String, _ locale: String = nagramFallbackLocale) -> String {
    return NagramLocalization.shared.localizedString(key, locale)
}
