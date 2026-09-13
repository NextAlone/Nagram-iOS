import TelegramCore

public func nagramRepeatedMessages(_ messages: [EngineRawMessage], threadId: Int64?, hideNames: Bool, copyProtectionEnabled: Bool) -> [EnqueueMessage] {
    var groupingKeys: [Int64: Int64] = [:]
    return messages.map { message in
        if copyProtectionEnabled || message.isCopyProtected() {
            // Protected messages must be sent as new content, not forwarded with a hidden author.
            let attributes = message.attributes.filter { attribute in
                return attribute is TextEntitiesMessageAttribute
                    || attribute is RichTextMessageAttribute
                    || attribute is MediaSpoilerMessageAttribute
                    || attribute is InvertMediaMessageAttribute
                    || attribute is WebpagePreviewMessageAttribute
            }
            let groupingKey = message.groupingKey.map { sourceKey in
                if let key = groupingKeys[sourceKey] {
                    return key
                }
                let key = Int64.random(in: Int64.min ... Int64.max)
                groupingKeys[sourceKey] = key
                return key
            }
            let mediaReference = message.media.first.map { media in
                AnyMediaReference.message(message: MessageReference(message), media: media)
            }
            return .message(text: message.text, attributes: attributes, inlineStickers: message.associatedMedia, mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        }
        let attributes: [EngineMessage.Attribute] = hideNames ? [ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)] : []
        return .forward(source: message.id, threadId: threadId, grouping: .auto, attributes: attributes, correlationId: nil)
    }
}
