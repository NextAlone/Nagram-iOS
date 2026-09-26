import Foundation
import NagramSettings
import SwiftSignalKit

@main
struct ProviderTests {
    static func main() throws {
        let baseURL = CommandLine.arguments[1]
        let audioURL = URL(fileURLWithPath: CommandLine.arguments[2])
        func config(_ path: String, language: String = "zh", model: String = "gpt-transcribe") throws -> NagramSTTConfiguration {
            return try NagramSTTConfiguration(baseURL: baseURL, endpoint: path, model: model, language: language, prompt: "Nagram 测试", apiKey: "fictional-test-key")
        }
        func request(_ path: String, language: String = "zh", model: String = "gpt-transcribe") throws -> Result<String, NagramTranscriptionError> {
            let semaphore = DispatchSemaphore(value: 0)
            let result = Atomic<Result<String, NagramTranscriptionError>?>(value: nil)
            let disposable = NagramOpenAITranscriptionProvider.transcribe(configuration: try config(path, language: language, model: model), audioURL: audioURL).start(next: { text in
                _ = result.swap(.success(text)); semaphore.signal()
            }, error: { error in
                _ = result.swap(.failure(error)); semaphore.signal()
            })
            guard semaphore.wait(timeout: .now() + 10) == .success else { fatalError("Request timed out: \(path)") }
            disposable.dispose()
            return result.with { $0! }
        }
        guard case .success("识别成功") = try request("/ok") else { fatalError("Multipart transcription failed") }
        guard case .success("识别成功") = try request("/automatic", language: "", model: "whisper-1") else { fatalError("Automatic language compatibility failed") }
        guard case let .failure(.http(code, message)) = try request("/quota"), code == 429,
              message.contains("[REDACTED]"), !message.contains("fictional-test-key") else { fatalError("HTTP error/redaction failed") }
        guard case .failure(.noSpeech) = try request("/empty") else { fatalError("Empty transcription should be noSpeech") }
        guard case .failure(.invalidResponse) = try request("/invalid") else { fatalError("Malformed JSON accepted") }
        guard case .failure(.http(302, _)) = try request("/redirect") else { fatalError("Redirect followed") }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nagram-stt-provider-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.m4a")
        try Data().write(to: empty)
        do {
            try NagramOpenAITranscriptionProvider.multipart(configuration: config("/ok"), audioURL: empty, bodyURL: directory.appendingPathComponent("body"), boundary: "test")
            fatalError("Empty audio accepted")
        } catch NagramTranscriptionError.invalidAudio { }
        let oversizedURL = directory.appendingPathComponent("oversized.m4a")
        try Data().write(to: oversizedURL)
        let oversized = try FileHandle(forWritingTo: oversizedURL)
        try oversized.truncate(atOffset: UInt64(NagramOpenAITranscriptionProvider.maximumFileSize + 1))
        try oversized.close()
        do {
            try NagramOpenAITranscriptionProvider.multipart(configuration: config("/ok"), audioURL: oversizedURL, bodyURL: directory.appendingPathComponent("body"), boundary: "test")
            fatalError("Oversized audio accepted")
        } catch NagramTranscriptionError.fileTooLarge { }

        func uploads() -> Set<String> {
            return Set(((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []).filter { $0.hasPrefix("nagram-stt-upload-") })
        }
        Thread.sleep(forTimeInterval: 0.2)
        let before = uploads()
        let callback = Atomic(value: false)
        let task = NagramOpenAITranscriptionProvider.transcribe(configuration: try config("/slow"), audioURL: audioURL).start(next: { _ in _ = callback.swap(true) }, error: { _ in _ = callback.swap(true) })
        Thread.sleep(forTimeInterval: 0.2)
        task.dispose()
        for _ in 0 ..< 40 {
            if uploads().subtracting(before).isEmpty { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        precondition(!callback.with { $0 }, "Cancelled upload delivered a result")
        precondition(uploads().subtracting(before).isEmpty, "Cancelled upload leaked its multipart directory")
        print("PASS: multipart bytes, fields, model language compatibility, JSON, 429/redaction, empty result, malformed response, redirect rejection, size validation, cancellation and cleanup.")
    }
}
