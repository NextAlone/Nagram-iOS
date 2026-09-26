import Foundation

/// Some third-party keyboards insert visual line separators to keep a newline key beside `.send`.
/// Telegram expects LF in message text; the replacements are one UTF-16 unit so entity offsets stay stable.
public func nagramNormalizeTextInputLineBreaks(_ text: NSAttributedString) -> NSAttributedString {
    let string = text.string as NSString
    var locations: [Int] = []
    var index = 0
    while index < string.length {
        switch string.character(at: index) {
        case 0x000d:
            if index + 1 >= string.length || string.character(at: index + 1) != 0x000a {
                locations.append(index)
            }
        case 0x0085, 0x2028, 0x2029:
            locations.append(index)
        default:
            break
        }
        index += 1
    }
    guard !locations.isEmpty else {
        return text
    }

    let result = NSMutableAttributedString(attributedString: text)
    for location in locations.reversed() {
        result.replaceCharacters(in: NSRange(location: location, length: 1), with: "\n")
    }
    return result
}

public struct NagramPanguTransform: Equatable {
    public let text: String
    public let insertedUtf16Offsets: [Int]

    public init(text: String, insertedUtf16Offsets: [Int]) {
        self.text = text
        self.insertedUtf16Offsets = insertedUtf16Offsets
    }
}

public enum NagramPangu {
    private static let protectedAttributeKeyNames: Set<String> = [
        "Attribute__Monospace",
        "Attribute__TextMention",
        "Attribute__TextUrl",
        "Attribute__Date",
        "Attribute__CustomEmoji",
        "Attribute__OriginalText",
        "Attribute__Blockquote",
        "Attribute__CollapsedBlockquote",
    ]

    public static func transform(_ text: String) -> NagramPanguTransform {
        return self.transform(text, protectedUtf16Ranges: [])
    }

    public static func transform(_ text: String, protectedUtf16Ranges: [Range<Int>]) -> NagramPanguTransform {
        guard text.count > 1 else {
            return NagramPanguTransform(text: text, insertedUtf16Offsets: [])
        }

        let protectedUtf16Ranges = normalizedProtectedUtf16Ranges(protectedUtf16Ranges, textLength: text.utf16.count)
        var result = String()
        result.reserveCapacity(text.count)

        var insertedUtf16Offsets: [Int] = []
        var index = text.startIndex
        while index < text.endIndex {
            let current = text[index]
            result.append(current)

            let nextIndex = text.index(after: index)
            if nextIndex < text.endIndex {
                let next = text[nextIndex]
                let nextUtf16Offset = nextIndex.utf16Offset(in: text)
                if shouldInsertSpace(between: current, and: next) && !isProtectedInsertionOffset(nextUtf16Offset, ranges: protectedUtf16Ranges) {
                    result.append(" ")
                    insertedUtf16Offsets.append(nextUtf16Offset)
                }
            }

            index = nextIndex
        }

        if insertedUtf16Offsets.isEmpty {
            return NagramPanguTransform(text: text, insertedUtf16Offsets: [])
        }
        return NagramPanguTransform(text: result, insertedUtf16Offsets: insertedUtf16Offsets)
    }

    public static func transform(_ attributedText: NSAttributedString) -> NSAttributedString {
        return self.transform(attributedText, protectedUtf16Ranges: self.protectedUtf16Ranges(attributedText))
    }

    public static func transform(_ attributedText: NSAttributedString, protectedUtf16Ranges: [Range<Int>]) -> NSAttributedString {
        let transform = self.transform(attributedText.string, protectedUtf16Ranges: protectedUtf16Ranges)
        guard !transform.insertedUtf16Offsets.isEmpty else {
            return attributedText
        }

        let result = NSMutableAttributedString(attributedString: attributedText)
        for (index, offset) in transform.insertedUtf16Offsets.enumerated() {
            let insertionIndex = offset + index
            result.insert(NSAttributedString(string: " ", attributes: self.insertedSpaceAttributes(in: result, at: insertionIndex)), at: insertionIndex)
        }
        return result
    }

    public static func transformRange(_ range: Range<Int>, insertedUtf16Offsets: [Int]) -> Range<Int> {
        guard !insertedUtf16Offsets.isEmpty else {
            return range
        }

        let lowerBound = range.lowerBound + insertedUtf16Offsets.filter { $0 <= range.lowerBound }.count
        let upperBound = range.upperBound + insertedUtf16Offsets.filter { $0 < range.upperBound }.count
        return lowerBound ..< max(lowerBound, upperBound)
    }

    /// Map a display-string UTF-16 range back to the original string before pangu spaces were inserted.
    /// `insertedUtf16Offsets` uses the same convention as `transform` (original offsets, ascending).
    public static func reverseTransformRange(_ range: Range<Int>, insertedUtf16Offsets: [Int], originalLength: Int) -> Range<Int> {
        guard !insertedUtf16Offsets.isEmpty else {
            return range
        }

        // Display index of each inserted space is originalOffset + insertionIndex.
        let displayInsertPositions: [Int] = insertedUtf16Offsets.enumerated().map { index, originalOffset in
            return originalOffset + index
        }
        let displayInsertSet = Set(displayInsertPositions)
        let displayLength = originalLength + insertedUtf16Offsets.count

        func originalBoundary(fromDisplay displayIndex: Int, isEnd: Bool) -> Int {
            var index = min(max(displayIndex, 0), displayLength)
            if isEnd {
                while index > 0 && displayInsertSet.contains(index - 1) {
                    index -= 1
                }
            } else {
                while index < displayLength && displayInsertSet.contains(index) {
                    index += 1
                }
            }
            let insertsBefore = displayInsertPositions.filter { $0 < index }.count
            let original = index - insertsBefore
            return min(max(original, 0), originalLength)
        }

        let lowerBound = originalBoundary(fromDisplay: range.lowerBound, isEnd: false)
        let upperBound = originalBoundary(fromDisplay: range.upperBound, isEnd: true)
        return lowerBound ..< max(lowerBound, upperBound)
    }

    public static func reverseTransformRange(_ range: NSRange, insertedUtf16Offsets: [Int], originalLength: Int) -> NSRange {
        let swiftRange = reverseTransformRange(range.location ..< (range.location + range.length), insertedUtf16Offsets: insertedUtf16Offsets, originalLength: originalLength)
        return NSRange(location: swiftRange.lowerBound, length: swiftRange.upperBound - swiftRange.lowerBound)
    }

    private static func protectedUtf16Ranges(_ attributedText: NSAttributedString) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length), options: []) { attributes, range, _ in
            guard attributes.contains(where: { self.isProtectedAttribute(key: $0.key, value: $0.value) }) else {
                return
            }
            ranges.append(range.lowerBound ..< range.upperBound)
        }
        return ranges
    }

    private static func insertedSpaceAttributes(in attributedText: NSAttributedString, at index: Int) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any]
        if index > 0 {
            attributes = attributedText.attributes(at: index - 1, effectiveRange: nil)
        } else if index < attributedText.length {
            attributes = attributedText.attributes(at: index, effectiveRange: nil)
        } else {
            attributes = [:]
        }
        attributes = attributes.filter { !self.isProtectedAttribute(key: $0.key, value: $0.value) }
        return attributes
    }

    private static func isProtectedAttribute(key: NSAttributedString.Key, value: Any) -> Bool {
        if key.rawValue == "Attribute__Blockquote" {
            return self.isCodeBlockQuoteAttribute(value)
        }
        return self.protectedAttributeKeyNames.contains(key.rawValue)
    }

    private static func isCodeBlockQuoteAttribute(_ value: Any) -> Bool {
        for child in Mirror(reflecting: value).children {
            if child.label == "kind" {
                return String(describing: child.value).hasPrefix("code")
            }
        }
        return false
    }

    private static func normalizedProtectedUtf16Ranges(_ ranges: [Range<Int>], textLength: Int) -> [Range<Int>] {
        let ranges = ranges.compactMap { range -> Range<Int>? in
            let lowerBound = max(0, min(textLength, range.lowerBound))
            let upperBound = max(lowerBound, min(textLength, range.upperBound))
            guard lowerBound < upperBound else {
                return nil
            }
            return lowerBound ..< upperBound
        }.sorted {
            if $0.lowerBound == $1.lowerBound {
                return $0.upperBound < $1.upperBound
            }
            return $0.lowerBound < $1.lowerBound
        }

        var merged: [Range<Int>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func isProtectedInsertionOffset(_ offset: Int, ranges: [Range<Int>]) -> Bool {
        for range in ranges {
            if offset <= range.lowerBound {
                return false
            }
            if offset < range.upperBound {
                return true
            }
        }
        return false
    }

    private static func shouldInsertSpace(between left: Character, and right: Character) -> Bool {
        if isWhitespace(left) || isWhitespace(right) {
            return false
        }

        return (isCJK(left) && isWesternAlphanumeric(right)) || (isWesternAlphanumeric(left) && isCJK(right))
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        return character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWesternAlphanumeric(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A:
            return true
        default:
            return false
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 0x3040 ... 0x30FF,
             0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xAC00 ... 0xD7AF,
             0xF900 ... 0xFAFF:
            return true
        default:
            return false
        }
    }
}
