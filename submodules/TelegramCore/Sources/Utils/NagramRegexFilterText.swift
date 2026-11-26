import Foundation
import Postbox

// MARK: NAGRAM — the text the regex filters match a message against.

public extension Message {
    /// The message's text, or for a rich message, whose text is empty and whose content is in its
    /// `RichTextMessageAttribute`, the text of its blocks in order, one block per line.
    var nagramRegexFilterText: String {
        if !self.text.isEmpty {
            return self.text
        }
        guard let richText = self.richText else {
            return self.text
        }
        var pieces: [String] = []
        nagramAppendPlainText(of: richText.instantPage.blocks, to: &pieces)
        return pieces.joined(separator: "\n")
    }
}

private func nagramAppend(_ text: RichText, to pieces: inout [String]) {
    let plainText = text.plainText
    if !plainText.isEmpty {
        pieces.append(plainText)
    }
}

private func nagramAppend(_ caption: InstantPageCaption, to pieces: inout [String]) {
    nagramAppend(caption.text, to: &pieces)
    nagramAppend(caption.credit, to: &pieces)
}

private func nagramAppendPlainText(of blocks: [InstantPageBlock], to pieces: inout [String]) {
    for block in blocks {
        switch block {
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text), let .paragraph(text), let .footer(text), let .kicker(text), let .thinking(text):
            nagramAppend(text, to: &pieces)
        case let .authorDate(author, _):
            nagramAppend(author, to: &pieces)
        case let .heading(text, _), let .preformatted(text, _):
            nagramAppend(text, to: &pieces)
        case let .list(items, _):
            for item in items {
                switch item {
                case let .text(text, _, _):
                    nagramAppend(text, to: &pieces)
                case let .blocks(blocks, _, _):
                    nagramAppendPlainText(of: blocks, to: &pieces)
                case .unknown:
                    break
                }
            }
        case let .blockQuote(blocks, caption, _):
            nagramAppendPlainText(of: blocks, to: &pieces)
            nagramAppend(caption, to: &pieces)
        case let .pullQuote(text, caption):
            nagramAppend(text, to: &pieces)
            nagramAppend(caption, to: &pieces)
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _), let .audio(_, caption), let .document(_, caption), let .map(_, _, _, _, caption):
            nagramAppend(caption, to: &pieces)
        case let .webEmbed(_, _, _, caption, _, _, _):
            nagramAppend(caption, to: &pieces)
        case let .postEmbed(_, _, _, _, _, blocks, caption):
            nagramAppendPlainText(of: blocks, to: &pieces)
            nagramAppend(caption, to: &pieces)
        case let .collage(items, caption), let .slideshow(items, caption):
            nagramAppendPlainText(of: items, to: &pieces)
            nagramAppend(caption, to: &pieces)
        case let .cover(block):
            nagramAppendPlainText(of: [block], to: &pieces)
        case let .table(title, rows, _, _, _):
            nagramAppend(title, to: &pieces)
            for row in rows {
                for cell in row.cells {
                    if let text = cell.text {
                        nagramAppend(text, to: &pieces)
                    }
                }
            }
        case let .details(title, blocks, _):
            nagramAppend(title, to: &pieces)
            nagramAppendPlainText(of: blocks, to: &pieces)
        default:
            break
        }
    }
}
