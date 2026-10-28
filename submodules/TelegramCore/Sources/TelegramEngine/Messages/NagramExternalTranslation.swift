import Foundation
import Postbox
import SwiftSignalKit

// MARK: NAGRAM — 外部翻译服务（Nagram/Translate）读取上下文与写回译文。
public extension TelegramEngine.Messages {
    /// The messages stored before `messageId` in its chat (or thread), oldest first, taken from a
    /// `count`-message window around it. Empty when the message is not stored.
    func nagramMessagesPreceding(messageId: EngineMessage.Id, count: Int) -> Signal<[EngineMessage], NoError> {
        let postbox = self.account.postbox
        return postbox.transaction { transaction -> Message? in
            return transaction.getMessage(messageId)
        }
        |> mapToSignal { target -> Signal<[EngineMessage], NoError> in
            guard let target else {
                return .single([])
            }
            return postbox.aroundMessageHistoryViewForLocation(
                .peer(peerId: messageId.peerId, threadId: target.threadId),
                anchor: .message(messageId),
                ignoreMessagesInTimestampRange: nil,
                ignoreMessageIds: Set(),
                count: count,
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
            |> map { view, _, _ -> [EngineMessage] in
                return view.entries.map(\.message)
                    .filter { $0.index < target.index }
                    .sorted(by: { $0.index < $1.index })
                    .map(EngineMessage.init)
            }
        }
    }

    /// Stores an externally produced translation, unless the message's source text (or, for a
    /// transcription, the transcription itself) changed since it was read.
    func nagramStoreExternalTranslation(messageId: EngineMessage.Id, text: String, entities: [MessageTextEntity], toLang: String, sourceText: String, sourceTranscription: AudioTranscriptionMessageAttribute?) -> Signal<Never, NoError> {
        return self.account.postbox.transaction { transaction in
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
                attributes.append(TranslationMessageAttribute(text: text, entities: entities, toLang: toLang))
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
            })
        }
        |> ignoreValues
    }
}
