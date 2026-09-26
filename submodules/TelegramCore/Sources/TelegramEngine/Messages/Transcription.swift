import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public enum EngineAudioTranscriptionResult {
    case success
    case error
}

private enum InternalAudioTranscriptionResult {
    case success(Api.messages.TranscribedAudio)
    case error(AudioTranscriptionMessageAttribute.TranscriptionError)
    case limitExceeded(Int32)
}

func _internal_transcribeAudio(postbox: Postbox, network: Network, messageId: MessageId) -> Signal<EngineAudioTranscriptionResult, NoError> {
    // MARK: NAGRAM — An explicit request establishes a generation before any asynchronous work.
    let requestId = Int64.random(in: Int64.min ... Int64.max)
    return postbox.transaction { transaction -> Api.InputPeer? in
        guard transaction.getMessage(messageId) != nil, let inputPeer = transaction.getPeer(messageId.peerId).flatMap(apiInputPeer) else {
            return nil
        }
        transaction.updateMessage(messageId, update: { currentMessage in
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            var attributes = currentMessage.attributes.filter { !($0 is AudioTranscriptionMessageAttribute) && !($0 is TranslationMessageAttribute) }
            attributes.append(AudioTranscriptionMessageAttribute(id: 0, text: "", isPending: true, didRate: false, error: nil, source: .telegram, requestId: requestId))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
        return inputPeer
    }
    |> mapToSignal { inputPeer -> Signal<EngineAudioTranscriptionResult, NoError> in
        guard let inputPeer = inputPeer else {
            return .single(.error)
        }
        return network.request(Api.functions.messages.transcribeAudio(peer: inputPeer, msgId: messageId.id))
        |> map { result -> InternalAudioTranscriptionResult in
            return .success(result)
        }
        |> `catch` { error -> Signal<InternalAudioTranscriptionResult, NoError> in
            let mappedError: AudioTranscriptionMessageAttribute.TranscriptionError
            if error.errorDescription.hasPrefix("FLOOD_WAIT_") {
                if let range = error.errorDescription.range(of: "_", options: .backwards) {
                    if let value = Int32(error.errorDescription[range.upperBound...]) {
                        return .single(.limitExceeded(value))
                    }
                }
                mappedError = .generic
            } else if error.errorDescription == "MSG_VOICE_TOO_LONG" {
                mappedError = .tooLong
            } else {
                mappedError = .generic
            }
            return .single(.error(mappedError))
        }
        |> mapToSignal { result -> Signal<EngineAudioTranscriptionResult, NoError> in
            return postbox.transaction { transaction -> EngineAudioTranscriptionResult in
                // MARK: NAGRAM — A newer local or external request owns this message now.
                guard let message = transaction.getMessage(messageId), let current = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, current.source == .telegram, current.requestId == requestId else {
                    return .error
                }
                let updatedAttribute: AudioTranscriptionMessageAttribute
                switch result {
                case let .success(transcribedAudio):
                    switch transcribedAudio {
                    case let .transcribedAudio(transcribedAudioData):
                        let (flags, transcriptionId, text, trialRemainingCount, trialUntilDate) = (transcribedAudioData.flags, transcribedAudioData.transcriptionId, transcribedAudioData.text, transcribedAudioData.trialRemainsNum, transcribedAudioData.trialRemainsUntilDate)
                        let isPending = (flags & (1 << 0)) != 0
                        // MARK: NAGRAM — A final push may arrive before the initial request response.
                        if current.id == transcriptionId && !current.isPending && isPending {
                            updatedAttribute = current
                        } else {
                            updatedAttribute = AudioTranscriptionMessageAttribute(id: transcriptionId, text: text, isPending: isPending, didRate: false, error: nil, source: .telegram, requestId: requestId)
                        }
                        
                        _internal_updateAudioTranscriptionTrialState(transaction: transaction) { current in
                            var updated = current
                            if let trialRemainingCount = trialRemainingCount, trialRemainingCount > 0 {
                                updated = updated.withUpdatedRemainingCount(trialRemainingCount)
                            } else if let trialUntilDate = trialUntilDate {
                                updated = updated.withUpdatedCooldownUntilTime(trialUntilDate)
                            } else {
                                updated = updated.withUpdatedCooldownUntilTime(nil)
                            }
                            return updated
                        }
                    }
                case let .error(error):
                    // MARK: NAGRAM
                    updatedAttribute = AudioTranscriptionMessageAttribute(id: 0, text: "", isPending: false, didRate: false, error: error, source: .telegram, requestId: requestId)
                case let .limitExceeded(timeout):
                    let cooldownTime = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970) + timeout
                    _internal_updateAudioTranscriptionTrialState(transaction: transaction) { current in
                        var updated = current
                        updated = updated.withUpdatedCooldownUntilTime(cooldownTime)
                        return updated
                    }
                    // MARK: NAGRAM — The merge hook removes this reset marker, preserving the trial lock UI.
                    updatedAttribute = AudioTranscriptionMessageAttribute(id: 0, text: "", isPending: false, didRate: false, error: nil, source: .telegram, requestId: requestId)
                }
                    
                transaction.updateMessage(messageId, update: { currentMessage in
                    let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                    // MARK: NAGRAM
                    var attributes = currentMessage.attributes.filter { !($0 is AudioTranscriptionMessageAttribute) && !($0 is TranslationMessageAttribute) }
                    
                    attributes.append(updatedAttribute)
                    
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                })
                
                // MARK: NAGRAM
                if case .limitExceeded = result {
                    return .error
                } else if updatedAttribute.error == nil {
                    return .success
                } else {
                    return .error
                }
            }
        }
    }
    // MARK: NAGRAM — A disposed request without a Telegram transcription id must not stay pending.
    |> afterDisposed {
        let _ = postbox.transaction { transaction -> Void in
            transaction.updateMessage(messageId, update: { currentMessage in
                guard let current = currentMessage.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, current.source == .telegram, current.requestId == requestId, current.id == 0, current.isPending else {
                    return .skip
                }
                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                var attributes = currentMessage.attributes.filter { !($0 is AudioTranscriptionMessageAttribute) }
                attributes.append(AudioTranscriptionMessageAttribute(id: 0, text: "", isPending: false, didRate: false, error: .generic, source: .telegram, requestId: requestId))
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
            })
        }.startStandalone()
    }
}

func _internal_rateAudioTranscription(postbox: Postbox, network: Network, messageId: MessageId, id: Int64, isGood: Bool) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Api.InputPeer? in
        // MARK: NAGRAM — Never submit third-party or superseded transcript ratings to Telegram.
        guard let message = transaction.getMessage(messageId), let current = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, current.canRate, current.id == id else {
            return nil
        }
        transaction.updateMessage(messageId, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var attributes = currentMessage.attributes
            for i in 0 ..< attributes.count {
                if let attribute = attributes[i] as? AudioTranscriptionMessageAttribute {
                    attributes[i] = attribute.withDidRate()
                }
            }
            return .update(StoreMessage(
                id: currentMessage.id,
                customStableId: nil,
                globallyUniqueId: currentMessage.globallyUniqueId,
                groupingKey: currentMessage.groupingKey,
                threadId: currentMessage.threadId,
                timestamp: currentMessage.timestamp,
                flags: StoreMessageFlags(currentMessage.flags),
                tags: currentMessage.tags,
                globalTags: currentMessage.globalTags,
                localTags: currentMessage.localTags,
                forwardInfo: storeForwardInfo,
                authorId: currentMessage.author?.id,
                text: currentMessage.text,
                attributes: attributes,
                media: currentMessage.media
            ))
        })
        
        return transaction.getPeer(messageId.peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer -> Signal<Never, NoError> in
        guard let inputPeer = inputPeer else {
            return .complete()
        }
        return network.request(Api.functions.messages.rateTranscribedAudio(peer: inputPeer, msgId: messageId.id, transcriptionId: id, good: isGood ? .boolTrue : .boolFalse))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> ignoreValues
    }
}

public enum AudioTranscription {
    public struct TrialState: Equatable, Codable {
        public let cooldownUntilTime: Int32?
        public let remainingCount: Int32
        
        func withUpdatedCooldownUntilTime(_ time: Int32?) -> AudioTranscription.TrialState {
            return AudioTranscription.TrialState(cooldownUntilTime: time, remainingCount: time != nil ? 0 : max(1, self.remainingCount))
        }
        
        func withUpdatedRemainingCount(_ remainingCount: Int32) -> AudioTranscription.TrialState {
            return AudioTranscription.TrialState(remainingCount: remainingCount)
        }
        
        public init(cooldownUntilTime: Int32? = nil, remainingCount: Int32) {
            self.cooldownUntilTime = cooldownUntilTime
            self.remainingCount = remainingCount
        }
        
        public static var defaultValue: AudioTranscription.TrialState {
            return AudioTranscription.TrialState(
                cooldownUntilTime: nil,
                remainingCount: 1
            )
        }
    }
}

func _internal_updateAudioTranscriptionTrialState(transaction: Transaction, _ f: (AudioTranscription.TrialState) -> AudioTranscription.TrialState) {
    let current = transaction.getPreferencesEntry(key: PreferencesKeys.audioTranscriptionTrialState)?.get(AudioTranscription.TrialState.self) ?? .defaultValue
    transaction.setPreferencesEntry(key: PreferencesKeys.audioTranscriptionTrialState, value: PreferencesEntry(f(current)))
}
