import Foundation

public enum NagramMessageDoubleTapAction: String {
    case disabled
    case sendReaction
    case showReactions
    case reply
    case repeatMessage
    case repeatWithoutQuote
    case edit

    public static let allCases: [NagramMessageDoubleTapAction] = [
        .disabled,
        .sendReaction,
        .showReactions,
        .reply,
        .repeatMessage,
        .repeatWithoutQuote,
        .edit
    ]
}
