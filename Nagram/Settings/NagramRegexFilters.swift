import Foundation

public extension Notification.Name {
    static let nagramRegexFiltersDidChange = Notification.Name("NagramRegexFiltersDidChange")
}

public enum NagramRegexFilterAction: String, Codable, Equatable {
    case mask
    case maskMessage
    case replace
    case hide

    public static var allCases: [NagramRegexFilterAction] {
        return [.mask, .maskMessage, .replace, .hide]
    }
}

public enum NagramRegexFilterResult: Equatable {
    case visible(text: String, spoilerRanges: [Range<Int>])
    case contentHidden
    case hidden
}

public struct NagramRegexFilterRule: Codable, Equatable {
    public var id: String
    public var title: String
    public var pattern: String
    public var isEnabled: Bool
    public var action: NagramRegexFilterAction
    public var replacement: String

    public init(id: String = UUID().uuidString, title: String, pattern: String, isEnabled: Bool = true, action: NagramRegexFilterAction = .hide, replacement: String = "") {
        self.id = id
        self.title = title
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.action = action
        self.replacement = replacement
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case pattern
        case isEnabled
        case action
        case replacement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.pattern = try container.decode(String.self, forKey: .pattern)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.action = try container.decodeIfPresent(NagramRegexFilterAction.self, forKey: .action) ?? .hide
        self.replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.pattern, forKey: .pattern)
        try container.encode(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.action, forKey: .action)
        try container.encode(self.replacement, forKey: .replacement)
    }

    public var displayTitle: String {
        let trimmedTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return self.pattern
    }

    public static func isValidPattern(_ pattern: String) -> Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return false
        }
        return (try? NSRegularExpression(pattern: trimmedPattern, options: [])) != nil
    }

    public static func matches(text: String, rules: [NagramRegexFilterRule], peerId: Int64?) -> Bool {
        guard NagramSettings.shared.isRegexFilteringEnabled(peerId: peerId) else {
            return false
        }
        return NagramRegexFilterMatcher(rules: rules).matches(text)
    }
}

public struct NagramRegexFilterMatcher {
    private struct CompiledRule {
        let expression: NSRegularExpression
        let action: NagramRegexFilterAction
    }

    private let rules: [CompiledRule]

    public init(rules: [NagramRegexFilterRule]) {
        self.rules = rules.compactMap { rule -> CompiledRule? in
            guard rule.isEnabled else {
                return nil
            }
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else {
                return nil
            }
            guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
                return nil
            }
            return CompiledRule(expression: expression, action: rule.action)
        }
    }

    public var isEmpty: Bool {
        return self.rules.isEmpty
    }

    public func apply(to text: String) -> NagramRegexFilterResult {
        guard !self.rules.isEmpty, !text.isEmpty else {
            return .visible(text: text, spoilerRanges: [])
        }
        let currentText = text
        var spoilerRanges: [Range<Int>] = []
        for rule in self.rules {
            let range = NSRange(location: 0, length: (currentText as NSString).length)
            guard rule.expression.firstMatch(in: currentText, options: [], range: range) != nil else {
                continue
            }
            switch rule.action {
            case .hide:
                return .hidden
            case .mask:
                let matches = rule.expression.matches(in: currentText, options: [], range: range)
                for match in matches where match.range.length > 0 {
                    spoilerRanges.append(match.range.location ..< (match.range.location + match.range.length))
                }
            case .maskMessage:
                if range.length > 0 {
                    spoilerRanges.append(0 ..< range.length)
                }
            case .replace:
                return .contentHidden
            }
        }
        return .visible(text: currentText, spoilerRanges: spoilerRanges)
    }

    public func matches(_ text: String) -> Bool {
        if case .hidden = self.apply(to: text) {
            return true
        }
        return false
    }
}

private let nagramRegexFilterRulesKey = "nagram.regexFilters.rules"
private let nagramRegexFilterDisabledPeerIdsKey = "nagram.regexFilters.disabledPeerIds"

public extension NagramSettings {
    var regexFilterRules: [NagramRegexFilterRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: nagramRegexFilterRulesKey),
                  let rules = try? JSONDecoder().decode([NagramRegexFilterRule].self, from: data) else {
                return []
            }
            return rules
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: nagramRegexFilterRulesKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: nagramRegexFilterRulesKey)
            }
            self.notifyRegexFiltersChanged()
        }
    }

    func upsertRegexFilterRule(_ rule: NagramRegexFilterRule) {
        var rules = self.regexFilterRules
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        self.regexFilterRules = rules
    }

    func removeRegexFilterRule(id: String) {
        var rules = self.regexFilterRules
        rules.removeAll(where: { $0.id == id })
        self.regexFilterRules = rules
    }

    func setRegexFilterRuleEnabled(id: String, enabled: Bool) {
        var rules = self.regexFilterRules
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled = enabled
        self.regexFilterRules = rules
    }

    func isRegexFilteringEnabled(peerId: Int64?) -> Bool {
        guard let peerId else {
            return true
        }
        return !self.regexFilterDisabledPeerIds.contains(peerId)
    }

    func setRegexFilteringEnabled(_ enabled: Bool, peerId: Int64) {
        var disabledPeerIds = self.regexFilterDisabledPeerIds
        let shouldBeDisabled = !enabled
        guard disabledPeerIds.contains(peerId) != shouldBeDisabled else {
            return
        }
        if enabled {
            disabledPeerIds.remove(peerId)
        } else {
            disabledPeerIds.insert(peerId)
        }
        self.regexFilterDisabledPeerIds = disabledPeerIds
        self.notifyRegexFiltersChanged()
    }

    func regexFilterMatcher(peerId: Int64?) -> NagramRegexFilterMatcher? {
        guard self.isRegexFilteringEnabled(peerId: peerId) else {
            return nil
        }
        let matcher = NagramRegexFilterMatcher(rules: self.regexFilterRules)
        return matcher.isEmpty ? nil : matcher
    }
}

private extension NagramSettings {
    var regexFilterDisabledPeerIds: Set<Int64> {
        get {
            let values = UserDefaults.standard.stringArray(forKey: nagramRegexFilterDisabledPeerIdsKey) ?? []
            return Set(values.compactMap(Int64.init))
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: nagramRegexFilterDisabledPeerIdsKey)
            } else {
                UserDefaults.standard.set(newValue.map { String($0) }.sorted(), forKey: nagramRegexFilterDisabledPeerIdsKey)
            }
        }
    }

    func notifyRegexFiltersChanged() {
        NotificationCenter.default.post(name: .nagramRegexFiltersDidChange, object: self)
    }
}
