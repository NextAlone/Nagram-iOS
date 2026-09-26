import AVFoundation
import Foundation
import SwiftSignalKit
import UniversalMediaPlayer

// Owns only this request's temporary directory, never the MediaBox source file.
final class NagramTranscriptionAudio {
    let directory: URL
    let url: URL

    init() throws {
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent("nagram-stt-audio-\(UUID().uuidString)", isDirectory: true)
        self.url = self.directory.appendingPathComponent("audio.m4a")
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: self.directory) }
}

func nagramPrepareTranscriptionAudio(path: String) -> Signal<NagramTranscriptionAudio, NagramTranscriptionError> {
    return Signal { subscriber in
        let queue = Queue()
        let cancelled = Atomic(value: false)
        var writer: AVAssetWriter?
        var writerInput: AVAssetWriterInput?
        var didFinish = false
        queue.async {
            if cancelled.with({ $0 }) { return }
            do {
                // SoftwareAudioSource uses an Int32 byte offset internally.
                let size = try URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size < Int(Int32.max) else { throw NagramTranscriptionError.invalidAudio }
                let source = SoftwareAudioSource(path: path)
                guard source.hasStream else { throw NagramTranscriptionError.invalidAudio }
                let audio = try NagramTranscriptionAudio()
                let assetWriter = try AVAssetWriter(outputURL: audio.url, fileType: .m4a)
                writer = assetWriter
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 48000,
                    AVEncoderBitRateKey: 32000,
                    AVNumberOfChannelsKey: 1
                ])
                guard assetWriter.canAdd(input) else { throw NagramTranscriptionError.invalidAudio }
                assetWriter.add(input)
                writerInput = input
                guard assetWriter.startWriting() else { throw NagramTranscriptionError.invalidAudio }
                assetWriter.startSession(atSourceTime: .zero)
                var sampleCount = 0
                // AVAssetWriterInput owns this block. Weak references prevent a writer/input cycle.
                input.requestMediaDataWhenReady(on: queue.queue) { [weak assetWriter, weak input] in
                    guard !didFinish, let assetWriter, let input else { return }
                    while input.isReadyForMoreMediaData {
                        if cancelled.with({ $0 }) {
                            didFinish = true
                            input.markAsFinished()
                            assetWriter.cancelWriting()
                            return
                        }
                        guard let sample = source.readSampleBuffer(drainRemainingFrames: true) else {
                            didFinish = true
                            input.markAsFinished()
                            guard sampleCount > 0 else {
                                assetWriter.cancelWriting()
                                subscriber.putError(.invalidAudio)
                                return
                            }
                            assetWriter.finishWriting { [weak assetWriter] in
                                guard !cancelled.with({ $0 }) else { return }
                                guard let assetWriter, assetWriter.status == .completed else {
                                    subscriber.putError(.invalidAudio)
                                    return
                                }
                                let bytes = (try? audio.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                                guard bytes > 0 else { subscriber.putError(.invalidAudio); return }
                                guard Int64(bytes) <= NagramOpenAITranscriptionProvider.maximumFileSize else {
                                    subscriber.putError(.fileTooLarge)
                                    return
                                }
                                subscriber.putNext(audio)
                                subscriber.putCompletion()
                            }
                            return
                        }
                        guard input.append(sample) else {
                            didFinish = true
                            input.markAsFinished()
                            assetWriter.cancelWriting()
                            subscriber.putError(.invalidAudio)
                            return
                        }
                        sampleCount += 1
                    }
                }
            } catch {
                if writer?.status == .writing { writer?.cancelWriting() }
                subscriber.putError((error as? NagramTranscriptionError) ?? .invalidAudio)
            }
        }
        return ActionDisposable {
            _ = cancelled.swap(true)
            queue.async {
                if !didFinish, writer?.status == .writing {
                    didFinish = true
                    writerInput?.markAsFinished()
                }
                if writer?.status == .writing { writer?.cancelWriting() }
                writerInput = nil
                writer = nil
            }
        }
    }
}
