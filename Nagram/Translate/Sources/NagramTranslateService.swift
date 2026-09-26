import AccountContext
import Foundation
import NagramSettings
import Postbox
import SwiftSignalKit
import TelegramCore

// MARK: NAGRAM — Unified Nagram translation facade. Telegram provider reuses TelegramEngine MTProto translateText wrappers.
public final class NagramTranslateService {
    private let context: AccountContext

    public init(context: AccountContext) {
        self.context = context
    }

    public var provider: NagramTranslationProvider {
        return NagramSettings.shared.translationProviderValue
    }

    public func translate(text: String, toLang: String, entities: [MessageTextEntity] = [], tone: TranslationTone = .neutral, messageId: EngineMessage.Id? = nil, fromLang: String? = nil) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
        let provider = self.provider
        switch provider {
        case .telegram:
            return self.context.engine.messages.translate(text: text, toLang: nagramTargetLanguage(toLang, provider: provider), entities: entities, tone: tone, messageId: messageId)
        case .google, .googleCN, .microsoft, .yandex, .transmart, .llm:
            return self.translateExternally(provider: provider, text: text, fromLang: fromLang, toLang: toLang, messageId: messageId)
        }
    }

    public func translateMessages(messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, enableLocalIfPossible: Bool, tone: TranslationTone = .neutral) -> Signal<Never, TranslationError> {
        let provider = self.provider
        switch provider {
        case .telegram:
            return self.context.engine.messages.translateMessages(messageIds: messageIds, fromLang: fromLang, toLang: nagramTargetLanguage(toLang, provider: provider), enableLocalIfPossible: enableLocalIfPossible, tone: tone)
        case .google, .googleCN, .microsoft, .yandex, .transmart, .llm:
            return self.translateMessagesExternally(provider: provider, messageIds: messageIds, fromLang: fromLang, toLang: toLang)
        }
    }

    private func translateExternally(provider: NagramTranslationProvider, text: String, fromLang: String?, toLang: String, messageId: EngineMessage.Id?) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
        guard provider == .llm, NagramSettings.shared.translationLLMUseContext, let messageId else {
            return nagramExternalTranslate(provider: provider, text: text, fromLang: fromLang, toLang: toLang)
        }
        return self.translationContext(messageId: messageId)
        |> castError(TranslationError.self)
        |> mapToSignal { context in
            return nagramExternalTranslate(provider: provider, text: text, fromLang: fromLang, toLang: toLang, context: context)
        }
    }

    private func translationContext(messageId: EngineMessage.Id) -> Signal<[String], NoError> {
        return self.context.account.postbox.transaction { transaction -> Message? in
            return transaction.getMessage(messageId)
        }
        |> mapToSignal { target -> Signal<[String], NoError> in
            guard let target else {
                return .single([])
            }
            return self.context.account.postbox.aroundMessageHistoryViewForLocation(
                .peer(peerId: messageId.peerId, threadId: target.threadId),
                anchor: .message(messageId),
                ignoreMessagesInTimestampRange: nil,
                ignoreMessageIds: Set(),
                count: 32,
                trackHoles: false,
                clipHoles: true,
                ignoreRelatedChats: true,
                fixedCombinedReadStates: nil,
                topTaggedMessageIdNamespaces: [Namespaces.Message.Cloud],
                tag: nil,
                appendMessagesFromTheSameGroup: false,
                namespaces: .not(Namespaces.Message.allNonRegular),
                orderStatistics: []
            )
            |> take(1)
            |> map { view, _, _ -> [String] in
                return view.entries.map(\.message)
                    .filter { $0.index < target.index }
                    .sorted(by: { $0.index < $1.index })
                    .suffix(5)
                    .compactMap(nagramTranslationContextText)
            }
        }
    }

    private func translateMessagesExternally(provider: NagramTranslationProvider, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String) -> Signal<Never, TranslationError> {
        return self.context.account.postbox.transaction { transaction -> [(EngineMessage.Id, String, AudioTranscriptionMessageAttribute?)] in
            var items: [(EngineMessage.Id, String, AudioTranscriptionMessageAttribute?)] = []
            for messageId in messageIds {
                guard let message = transaction.getMessage(messageId) else {
                    continue
                }
                if !message.text.isEmpty {
                    items.append((messageId, message.text, nil))
                } else if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
                    items.append((messageId, audioTranscription.text, audioTranscription))
                }
            }
            return items
        }
        |> castError(TranslationError.self)
        |> mapToSignal { items -> Signal<Never, TranslationError> in
            guard !items.isEmpty else {
                return .complete()
            }
            let timeoutSeconds: Double = provider == .llm ? 45.0 : 15.0
            let signals: [Signal<(EngineMessage.Id, String, String, AudioTranscriptionMessageAttribute?)?, NoError>] = items.map { messageId, text, transcription in
                return self.translateExternally(provider: provider, text: text, fromLang: fromLang, toLang: toLang, messageId: messageId)
                |> timeout(timeoutSeconds, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.generic))
                |> map { result -> (EngineMessage.Id, String, String, AudioTranscriptionMessageAttribute?)? in
                    guard let translatedText = result?.0, !translatedText.isEmpty else {
                        return nil
                    }
                    return (messageId, translatedText, text, transcription)
                }
                |> `catch` { _ -> Signal<(EngineMessage.Id, String, String, AudioTranscriptionMessageAttribute?)?, NoError> in
                    return .single(nil)
                }
            }
            return combineLatest(signals)
            |> mapToSignal { translations -> Signal<Never, NoError> in
                let translations = translations.compactMap { $0 }
                guard !translations.isEmpty else {
                    return .complete()
                }
                return self.context.account.postbox.transaction { transaction in
                    for (messageId, text, sourceText, sourceTranscription) in translations {
                        transaction.updateMessage(messageId, update: { currentMessage in
                            if let sourceTranscription {
                                guard currentMessage.text.isEmpty, let current = currentMessage.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !current.isPending, current.text == sourceText, current.id == sourceTranscription.id, current.source == sourceTranscription.source, current.requestId == sourceTranscription.requestId else {
                                    return .skip
                                }
                            } else if currentMessage.text != sourceText {
                                return .skip
                            }
                            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                            var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                            attributes.append(TranslationMessageAttribute(text: text, entities: [], toLang: toLang))
                            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                        })
                    }
                }
                |> ignoreValues
            }
            |> castError(TranslationError.self)
        }
    }
}

private func nagramTranslationContextText(_ message: Message) -> String? {
    let text: String
    if !message.text.isEmpty {
        text = message.text
    } else if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
        text = audioTranscription.text
    } else {
        return nil
    }
    return String(text.prefix(1000))
}
