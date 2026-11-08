import Foundation
import CoreGraphics
import TelegramCore

// A message row the chat history has on screen: its frame in the list's coordinates and the messages it shows (an
// album shows several).
public struct ChatHistoryVisibleReadRow {
    public var frame: CGRect
    public var messages: [EngineMessage.Index]

    public init(frame: CGRect, messages: [EngineMessage.Index]) {
        self.frame = frame
        self.messages = messages
    }
}

// The newest message the chat reads from the rows on screen, or nil when no row counts. Frames and `topInset` are in list
// space: in the rotated chat history the list's top inset is the input panel at the bottom of the screen. A row hidden
// under the top inset does not count; one that starts up to 100 points above it does, as does a taller one holding
// `lastMessageId`, the newest message of a history that is loaded to its end. In a thread (`isThread`: a forum topic, a
// reply thread, a monoforum thread) the read goes up to a cloud message id, so a row holding a message of another
// namespace is left out.
public func chatHistoryMaxVisibleReadIndex(rows: [ChatHistoryVisibleReadRow], topInset: CGFloat, lastMessageId: EngineMessage.Id?, isThread: Bool) -> EngineMessage.Index? {
    var maxMessage: EngineMessage.Index?
    for row in rows {
        if row.frame.maxY < topInset {
            continue
        }
        var matches = false
        if row.frame.minY >= topInset - 100.0 {
            matches = true
        } else if let lastMessageId, row.messages.contains(where: { $0.id == lastMessageId }) {
            matches = true
        }
        if matches && isThread && row.messages.contains(where: { $0.id.namespace != Namespaces.Message.Cloud }) {
            matches = false
        }
        if matches, let maxItemIndex = row.messages.max() {
            if let maxMessageValue = maxMessage {
                if maxMessageValue < maxItemIndex {
                    maxMessage = maxItemIndex
                }
            } else {
                maxMessage = maxItemIndex
            }
        }
    }
    return maxMessage
}

// MARK: NAGRAM — a message newer than the read index that the chat does not show because a Nagram filter hides it.
public struct ChatHistoryReadCandidate {
    public var index: EngineMessage.Index
    public var isHiddenByFilter: Bool

    public init(index: EngineMessage.Index, isHiddenByFilter: Bool) {
        self.index = index
        self.isHiddenByFilter = isHiddenByFilter
    }
}

// MARK: NAGRAM — the read index the chat reports once filters are taken into account. Hidden messages have no row, so
// reading what is on screen stops at the newest shown message and a hidden newest message stays unread for good. When the
// history is loaded to its end and every message newer than `readIndex` (`newerMessages`, any order) is hidden, the
// read moves to the newest of them; otherwise, or when one of them is not a cloud message in a thread (`isThread`, see
// above), it stays at `readIndex`.
public func chatHistoryReadIndexPastHiddenMessages(readIndex: EngineMessage.Index, newerMessages: [ChatHistoryReadCandidate], isHistoryLoadedToEnd: Bool, isThread: Bool) -> EngineMessage.Index {
    guard isHistoryLoadedToEnd else {
        return readIndex
    }
    var result = readIndex
    for message in newerMessages where message.index > readIndex {
        if !message.isHiddenByFilter {
            return readIndex
        }
        if isThread && message.index.id.namespace != Namespaces.Message.Cloud {
            return readIndex
        }
        result = max(result, message.index)
    }
    return result
}
