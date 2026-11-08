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

/// Whether `nagramRepeatedMessages` can send `message` again: the context menu and the double-tap action both ask
/// this. A protected message (the chat's or its own) qualifies only with force copy on, and is then sent as new content.
public func nagramCanRepeatMessage(_ message: EngineRawMessage, chatCopyProtectionEnabled: Bool, forceCopyEnabled: Bool) -> Bool {
    if Namespaces.Message.allScheduled.contains(message.id.namespace) {
        return false
    }
    if message.flags.isSending || message.flags.contains(.Failed) {
        return false
    }
    if message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.containsSecretMedia {
        return false
    }
    if message.id.peerId.isReplies {
        return false
    }
    if (chatCopyProtectionEnabled || message.isCopyProtected()) && !forceCopyEnabled {
        return false
    }

    for media in message.media {
        if media is TelegramMediaAction || media is TelegramMediaExpiredContent {
            return false
        }
        if let invoice = media as? TelegramMediaInvoice, let _ = invoice.extendedMedia {
            return false
        }
        if let story = media as? TelegramMediaStory {
            if let story = message.associatedStories[story.storyId], story.data.isEmpty {
                return false
            } else if story.isMention {
                return false
            }
        }
    }

    return true
}
