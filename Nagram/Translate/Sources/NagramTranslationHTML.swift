import Foundation
import TelegramCore

// MARK: NAGRAM — Rich text <-> HTML round trip that lets formatting survive an external translation provider. Ported from Android Nagram's HTMLKeeper (originally OctoGram).

private enum NagramTranslationTag: Equatable {
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case spoiler
    case blockQuote
    case pre
    case link
    case customEmoji

    init?(name: String) {
        switch name {
        case "b", "strong":
            self = .bold
        case "i", "em":
            self = .italic
        case "u", "ins":
            self = .underline
        case "s", "strike", "del":
            self = .strikethrough
        case "code", "tt":
            self = .code
        case "tg-spoiler", "spoiler":
            self = .spoiler
        case "blockquote":
            self = .blockQuote
        case "pre":
            self = .pre
        case "a":
            self = .link
        case "tg-emoji":
            self = .customEmoji
        default:
            return nil
        }
    }

    var name: String {
        switch self {
        case .bold:
            return "b"
        case .italic:
            return "i"
        case .underline:
            return "u"
        case .strikethrough:
            return "s"
        case .code:
            return "code"
        case .spoiler:
            return "tg-spoiler"
        case .blockQuote:
            return "blockquote"
        case .pre:
            return "pre"
        case .link:
            return "a"
        case .customEmoji:
            return "tg-emoji"
        }
    }

    /// Tags whose entity carries data that is restored from the source entities. They are never split in two, and a provider may add attributes to them.
    var isAtomic: Bool {
        switch self {
        case .blockQuote, .pre, .link, .customEmoji:
            return true
        case .bold, .italic, .underline, .strikethrough, .code, .spoiler:
            return false
        }
    }
}

private struct NagramTranslationSpan {
    var start: Int
    var end: Int
    let tag: NagramTranslationTag
    let openTag: String
}

private func nagramTranslationSpan(for entity: MessageTextEntity, length: Int) -> NagramTranslationSpan? {
    let tag: NagramTranslationTag
    var openTag: String?
    switch entity.type {
    case .Bold:
        tag = .bold
    case .Italic:
        tag = .italic
    case .Underline:
        tag = .underline
    case .Strikethrough:
        tag = .strikethrough
    case .Code:
        tag = .code
    case .Spoiler:
        tag = .spoiler
    case .BlockQuote:
        tag = .blockQuote
    case .Pre:
        tag = .pre
    case .Url, .TextUrl, .TextMention:
        tag = .link
    case let .CustomEmoji(_, fileId):
        tag = .customEmoji
        openTag = "<tg-emoji emoji-id=\"\(fileId)\">"
    default:
        return nil
    }
    let start = max(0, entity.range.lowerBound)
    let end = min(length, entity.range.upperBound)
    guard start < end else {
        return nil
    }
    return NagramTranslationSpan(start: start, end: end, tag: tag, openTag: openTag ?? "<\(tag.name)>")
}

/// Converts `text` into the HTML sent to a translation provider, or returns nil when no entity needs to be kept.
///
/// Links are emitted as a bare `<a>`: their target is restored from the source entities by `nagramTranslationRichText`.
func nagramTranslationHTML(text: String, entities: [MessageTextEntity]) -> String? {
    let string = text as NSString
    let spans = entities.compactMap { nagramTranslationSpan(for: $0, length: string.length) }
    guard !spans.isEmpty else {
        return nil
    }

    // A style that partially overlaps an atomic span is cut at its boundary, so the atomic tag stays in one piece.
    let atomicSpans = spans.filter { $0.tag.isAtomic }
    var pieces = atomicSpans
    for span in spans where !span.tag.isAtomic {
        var cuts = Set<Int>()
        for atomic in atomicSpans {
            if atomic.start < span.start && span.start < atomic.end && atomic.end < span.end {
                cuts.insert(atomic.end)
            }
            if span.start < atomic.start && atomic.start < span.end && span.end < atomic.end {
                cuts.insert(atomic.start)
            }
        }
        var piece = span
        for cut in cuts.sorted() {
            piece.end = cut
            pieces.append(piece)
            piece.start = cut
        }
        piece.end = span.end
        pieces.append(piece)
    }
    pieces.sort { lhs, rhs in
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end > rhs.end
        }
        return lhs.tag.isAtomic && !rhs.tag.isAtomic
    }

    var boundaries = Set<Int>([0, string.length])
    for piece in pieces {
        boundaries.insert(piece.start)
        boundaries.insert(piece.end)
    }
    let positions = boundaries.sorted()

    var result = ""
    var stack: [NagramTranslationSpan] = []
    var nextPiece = 0
    for (index, position) in positions.enumerated() {
        if let lowest = stack.firstIndex(where: { $0.end <= position }) {
            var reopened: [NagramTranslationSpan] = []
            while stack.count > lowest {
                let span = stack.removeLast()
                result += "</\(span.tag.name)>"
                if span.end > position {
                    reopened.append(span)
                }
            }
            for span in reopened.reversed() {
                result += span.openTag
                stack.append(span)
            }
        }
        while nextPiece < pieces.count && pieces[nextPiece].start == position {
            result += pieces[nextPiece].openTag
            stack.append(pieces[nextPiece])
            nextPiece += 1
        }
        if index + 1 < positions.count {
            let segment = string.substring(with: NSRange(location: position, length: positions[index + 1] - position))
            result += segment.replacingOccurrences(of: "<", with: "&lt;")
        }
    }
    return result
}

private enum NagramTranslationParsedTag {
    case open([NagramTranslationTag], attributes: String)
    case close([NagramTranslationTag])
    case lineBreak
}

/// Parses the text between `<` and `>`. Providers tend to pad tags with spaces and to glue two of them together (`<b-i>`); anything unknown is not a tag and stays in the text.
private func nagramTranslationParseTag(_ body: Substring) -> NagramTranslationParsedTag? {
    var content = body.trimmingCharacters(in: .whitespaces)
    if content.hasSuffix("/") {
        content = String(content.dropLast()).trimmingCharacters(in: .whitespaces)
    }
    let isClosing = content.hasPrefix("/")
    if isClosing {
        content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    let nameEnd = content.firstIndex(where: { !(($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-") }) ?? content.endIndex
    let name = content[..<nameEnd].lowercased()
    let attributes = content[nameEnd...].trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else {
        return nil
    }
    if name == "br" {
        return .lineBreak
    }
    if let tag = NagramTranslationTag(name: name) {
        if isClosing {
            return attributes.isEmpty ? .close([tag]) : nil
        }
        if !attributes.isEmpty && !tag.isAtomic {
            return nil
        }
        return .open([tag], attributes: attributes)
    }
    let parts = name.split(separator: "-").map { NagramTranslationTag(name: String($0)) }
    let tags = parts.compactMap { $0 }
    guard parts.count > 1, tags.count == parts.count, attributes.isEmpty else {
        return nil
    }
    return isClosing ? .close(tags.reversed()) : .open(tags, attributes: "")
}

private func nagramTranslationUnescape(_ text: String) -> String {
    guard text.contains("&") else {
        return text
    }
    var result = text
    for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
        result = result.replacingOccurrences(of: entity, with: character)
    }
    return result
}

/// Converts the HTML returned by a translation provider back into text and entities.
///
/// The data a tag cannot carry through a provider (link targets, code languages, quote collapsing, emoji packs) is taken from `sourceEntities`, in order.
func nagramTranslationRichText(html: String, sourceEntities: [MessageTextEntity]) -> (String, [MessageTextEntity]) {
    var linkTypes: [MessageTextEntityType] = []
    var preTypes: [MessageTextEntityType] = []
    var quoteTypes: [MessageTextEntityType] = []
    var emojiTypes: [Int64: MessageTextEntityType] = [:]
    for entity in sourceEntities {
        switch entity.type {
        case .Url, .TextUrl, .TextMention:
            linkTypes.append(entity.type)
        case .Pre:
            preTypes.append(entity.type)
        case .BlockQuote:
            quoteTypes.append(entity.type)
        case let .CustomEmoji(_, fileId):
            emojiTypes[fileId] = entity.type
        default:
            break
        }
    }

    let output = NSMutableString()
    var openTags: [(tag: NagramTranslationTag, start: Int, type: MessageTextEntityType?)] = []
    var entities: [MessageTextEntity] = []
    var dropLeadingSpace = false

    func endsWithSpace() -> Bool {
        return output.length > 0 && output.character(at: output.length - 1) == 0x20
    }
    func truncate(to length: Int) {
        guard length < output.length else {
            return
        }
        output.deleteCharacters(in: NSRange(location: length, length: output.length - length))
        entities = entities.compactMap { entity in
            let upperBound = min(entity.range.upperBound, length)
            return entity.range.lowerBound < upperBound ? MessageTextEntity(range: entity.range.lowerBound ..< upperBound, type: entity.type) : nil
        }
    }
    func appendText(_ text: Substring) {
        var text = nagramTranslationUnescape(String(text))
        guard !text.isEmpty else {
            return
        }
        if dropLeadingSpace && text.hasPrefix(" ") {
            text.removeFirst()
        }
        dropLeadingSpace = false
        output.append(text)
    }
    func open(_ tag: NagramTranslationTag, attributes: String) {
        let type: MessageTextEntityType?
        switch tag {
        case .bold:
            type = .Bold
        case .italic:
            type = .Italic
        case .underline:
            type = .Underline
        case .strikethrough:
            type = .Strikethrough
        case .code:
            type = .Code
        case .spoiler:
            type = .Spoiler
        case .blockQuote:
            type = quoteTypes.isEmpty ? .BlockQuote(isCollapsed: false) : quoteTypes.removeFirst()
        case .pre:
            type = preTypes.isEmpty ? .Pre(language: nil) : preTypes.removeFirst()
        case .link:
            type = linkTypes.isEmpty ? nil : linkTypes.removeFirst()
        case .customEmoji:
            type = attributes.range(of: "-?[0-9]+", options: .regularExpression).flatMap { Int64(attributes[$0]) }.flatMap { emojiTypes[$0] }
        }
        openTags.append((tag, output.length, type))
    }
    func close(at index: Int) {
        let entry = openTags.remove(at: index)
        let start = min(entry.start, output.length)
        if let type = entry.type, start < output.length {
            entities.append(MessageTextEntity(range: start ..< output.length, type: type))
        }
    }

    var index = html.startIndex
    while index < html.endIndex {
        guard let tagStart = html[index...].firstIndex(of: "<") else {
            appendText(html[index...])
            break
        }
        appendText(html[index ..< tagStart])
        let bodyStart = html.index(after: tagStart)
        guard let tagEnd = html[bodyStart...].firstIndex(where: { $0 == ">" || $0 == "<" }), html[tagEnd] == ">", let parsedTag = nagramTranslationParseTag(html[bodyStart ..< tagEnd]) else {
            output.append("<")
            dropLeadingSpace = false
            index = bodyStart
            continue
        }
        index = html.index(after: tagEnd)
        switch parsedTag {
        case .lineBreak:
            output.append("\n")
            dropLeadingSpace = false
        case let .open(tags, attributes):
            // Providers pad tags with spaces: " <b> text" keeps a single space, before the tag.
            dropLeadingSpace = output.length == 0 || endsWithSpace()
            for tag in tags {
                open(tag, attributes: attributes)
            }
        case let .close(tags):
            // "text </b> next" keeps a single space, after the tag.
            if endsWithSpace() && index < html.endIndex && html[index] == " " {
                truncate(to: output.length - 1)
            }
            for tag in tags {
                if let openIndex = openTags.lastIndex(where: { $0.tag == tag }) {
                    close(at: openIndex)
                } else if !openTags.isEmpty {
                    // A closing tag without an opening one is a mangled copy of the innermost open tag.
                    close(at: openTags.count - 1)
                }
            }
        }
    }
    while !openTags.isEmpty {
        close(at: openTags.count - 1)
    }

    let lastContent = output.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: .backwards)
    truncate(to: lastContent.location == NSNotFound ? 0 : NSMaxRange(lastContent))
    entities.sort { $0.range.lowerBound < $1.range.lowerBound }
    return (output as String, entities)
}
