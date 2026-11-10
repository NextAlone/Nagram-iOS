import Foundation
import Speech
import SwiftSignalKit

// Apple Speech recognition that never leaves the device. A language without an
// on-device model is an explicit error: falling back to Apple's servers would send
// chat audio off the device without the user choosing that.
enum NagramSystemSpeechTranscriptionProvider {
    /// Longest voice or video message accepted, in seconds. On-device recognition of a
    /// URL request has no documented limit, but its run time grows with the audio.
    static let maximumDuration: Double = 5 * 60
    /// Whole-job timeout for this provider: recognition plus download and conversion.
    static let jobTimeout: Double = 10 * 60

    static let automaticLanguage = "auto"
    static let appLanguage = "app"

    static func authorize() -> Signal<Void, NagramTranscriptionError> {
        return Signal { subscriber in
            let isDisposed = Atomic(value: false)
            let handle: (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
                switch status {
                case .authorized:
                    subscriber.putNext(())
                    subscriber.putCompletion()
                case .restricted:
                    subscriber.putError(.speechPermissionRestricted)
                case .denied, .notDetermined:
                    subscriber.putError(.speechPermissionDenied)
                @unknown default:
                    subscriber.putError(.speechPermissionDenied)
                }
            }
            let status = SFSpeechRecognizer.authorizationStatus()
            if status == .notDetermined {
                SFSpeechRecognizer.requestAuthorization { status in
                    Queue.mainQueue().async {
                        guard !isDisposed.with({ $0 }) else { return }
                        handle(status)
                    }
                }
            } else {
                handle(status)
            }
            return ActionDisposable {
                let _ = isDisposed.swap(true)
            }
        }
        |> runOn(.mainQueue())
    }

    /// Resolves the language setting to one of the recognizer's supported locales.
    static func resolveLocale(setting: String, appLanguageCode: String) -> Result<Locale, NagramTranscriptionError> {
        let candidates: [String]
        switch setting {
        case "", self.automaticLanguage:
            candidates = Locale.preferredLanguages
        case self.appLanguage:
            candidates = [appLanguageCode]
        default:
            candidates = [setting]
        }
        let supported = SFSpeechRecognizer.supportedLocales().map { $0.identifier }
        for candidate in candidates {
            if let identifier = self.match(candidate, supported: supported) {
                return .success(Locale(identifier: identifier))
            }
        }
        return .failure(.speechLanguageUnsupported(candidates.first ?? setting))
    }

    static func transcribe(audioURL: URL, locale: Locale) -> Signal<String, NagramTranscriptionError> {
        return Signal { subscriber in
            let identifier = locale.identifier
            guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                subscriber.putError(.speechLanguageUnsupported(identifier))
                return EmptyDisposable
            }
            guard recognizer.supportsOnDeviceRecognition else {
                subscriber.putError(.speechOnDeviceUnavailable(identifier))
                return EmptyDisposable
            }
            guard recognizer.isAvailable else {
                subscriber.putError(.speechRecognizerUnavailable)
                return EmptyDisposable
            }
            recognizer.defaultTaskHint = .dictation

            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            if #available(iOS 16.0, *) {
                request.addsPunctuation = true
            }

            // The handler runs on the recognizer's queue (main by default); a cancelled task
            // still reports once, so only the first terminal event is forwarded.
            let isDone = Atomic(value: false)
            let task = recognizer.recognitionTask(with: request, resultHandler: { result, error in
                if let result, result.isFinal {
                    guard !isDone.swap(true) else { return }
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        subscriber.putError(.noSpeech)
                    } else {
                        subscriber.putNext(text)
                        subscriber.putCompletion()
                    }
                } else if let error {
                    guard !isDone.swap(true) else { return }
                    subscriber.putError(self.mapError(error as NSError))
                }
            })
            return ActionDisposable {
                let _ = isDone.swap(true)
                task.cancel()
                withExtendedLifetime(recognizer) {}
            }
        }
        |> runOn(.mainQueue())
    }

    private static func mapError(_ error: NSError) -> NagramTranscriptionError {
        // kAFAssistantErrorDomain 1110: no speech detected. Other codes are undocumented,
        // so they are shown with their domain and code instead of being guessed at.
        if error.domain == "kAFAssistantErrorDomain" && error.code == 1110 {
            return .noSpeech
        }
        if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
            return .cancelled
        }
        return .speechFailed("\(error.localizedDescription) (\(error.domain) \(error.code))")
    }

    // MARK: Locale matching

    private struct Tag {
        var language: String
        var script: String?
        var region: String?

        init(_ value: String) {
            let parts = value.replacingOccurrences(of: "_", with: "-").split(separator: "-").map { String($0) }
            self.language = (parts.first ?? "").lowercased()
            for part in parts.dropFirst() {
                if part.count == 4, part.allSatisfy({ $0.isLetter }), self.script == nil {
                    self.script = part.capitalized
                } else if (part.count == 2 && part.allSatisfy({ $0.isLetter })) || (part.count == 3 && part.allSatisfy({ $0.isNumber })), self.region == nil {
                    self.region = part.uppercased()
                }
            }
        }
    }

    private static let defaultRegions: [String: String] = [
        "en": "US", "es": "ES", "fr": "FR", "de": "DE", "pt": "BR", "it": "IT",
        "ar": "SA", "ru": "RU", "ja": "JP", "ko": "KR", "nl": "NL", "yue": "CN",
    ]

    private static func match(_ candidate: String, supported: [String]) -> String? {
        let tag = Tag(candidate)
        guard !tag.language.isEmpty else { return nil }
        var byKey: [String: String] = [:]
        for identifier in supported {
            let supportedTag = Tag(identifier)
            byKey["\(supportedTag.language)-\(supportedTag.region ?? "")"] = identifier
        }
        func lookup(_ language: String, _ region: String?) -> String? {
            return byKey["\(language)-\(region ?? "")"]
        }

        if tag.language == "zh" {
            // Script, not region, decides Mandarin's written form; zh-HK is Cantonese.
            if tag.region == "HK" || tag.region == "MO" {
                if let value = lookup("zh", "HK") { return value }
            }
            if tag.script == "Hant" || tag.region == "TW" || tag.region == "HK" || tag.region == "MO" {
                return lookup("zh", "TW")
            }
            return lookup("zh", "CN")
        }
        if let region = tag.region, let value = lookup(tag.language, region) {
            return value
        }
        if let region = self.defaultRegions[tag.language], let value = lookup(tag.language, region) {
            return value
        }
        return supported.filter { Tag($0).language == tag.language }.sorted().first
    }
}
