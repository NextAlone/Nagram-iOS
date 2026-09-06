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

public enum NagramRegexFilterPatternValidation: Equatable {
    case valid
    case empty
    case invalid(String)

    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .valid:
            return nil
        case .empty:
            return nil
        case let .invalid(reason):
            return reason
        }
    }
}

public struct NagramRegexFilterRule: Codable, Equatable {
    public var id: String
    public var title: String
    public var pattern: String
    public var isEnabled: Bool
    public var action: NagramRegexFilterAction
    public var replacement: String
    public var authorPeerId: Int64?

    public init(id: String = UUID().uuidString, title: String, pattern: String, isEnabled: Bool = true, action: NagramRegexFilterAction = .hide, replacement: String = "", authorPeerId: Int64? = nil) {
        self.id = id
        self.title = title
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.action = action
        self.replacement = replacement
        self.authorPeerId = authorPeerId
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case pattern
        case isEnabled
        case action
        case replacement
        case authorPeerId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.pattern = try container.decode(String.self, forKey: .pattern)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.action = try container.decodeIfPresent(NagramRegexFilterAction.self, forKey: .action) ?? .hide
        self.replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        self.authorPeerId = try container.decodeIfPresent(Int64.self, forKey: .authorPeerId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.pattern, forKey: .pattern)
        try container.encode(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.action, forKey: .action)
        try container.encode(self.replacement, forKey: .replacement)
        try container.encodeIfPresent(self.authorPeerId, forKey: .authorPeerId)
    }

    public var displayTitle: String {
        let trimmedTitle = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        if let authorPeerId = self.authorPeerId {
            return "User ID \(authorPeerId)"
        }
        return self.pattern
    }

    public static func isValidPattern(_ pattern: String) -> Bool {
        return self.validatePattern(pattern).isValid
    }

    public static func validatePattern(_ pattern: String) -> NagramRegexFilterPatternValidation {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return .empty
        }
        do {
            _ = try NSRegularExpression(pattern: trimmedPattern, options: [])
            return .valid
        } catch {
            return .invalid((error as NSError).localizedDescription)
        }
    }

    public static func matches(text: String, rules: [NagramRegexFilterRule], peerId: Int64?, authorPeerId: Int64? = nil, isOutgoing: Bool = false) -> Bool {
        guard NagramSettings.shared.isRegexFilteringEnabled(peerId: peerId, isOutgoing: isOutgoing) else {
            return false
        }
        return NagramRegexFilterMatcher(rules: rules).matches(text, authorPeerId: authorPeerId)
    }
}

private final class NagramRegexFilterResultCache {
    private let limit: Int
    private var values: [String: NagramRegexFilterResult] = [:]
    private var keys: [String] = []
    private let lock = NSLock()

    init(limit: Int) {
        self.limit = limit
    }

    func get(_ key: String) -> NagramRegexFilterResult? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.values[key]
    }

    func set(_ value: NagramRegexFilterResult, for key: String) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if self.values[key] == nil {
            self.keys.append(key)
        }
        self.values[key] = value
        while self.keys.count > self.limit {
            let removedKey = self.keys.removeFirst()
            self.values.removeValue(forKey: removedKey)
        }
    }
}

public struct NagramRegexFilterMatcher {
    private struct CompiledRule {
        let expression: NSRegularExpression?
        let action: NagramRegexFilterAction
        let authorPeerId: Int64?
    }

    private let rules: [CompiledRule]
    private let resultCache = NagramRegexFilterResultCache(limit: 512)

    public init(rules: [NagramRegexFilterRule]) {
        self.rules = rules.compactMap { rule -> CompiledRule? in
            guard rule.isEnabled else {
                return nil
            }
            if let authorPeerId = rule.authorPeerId {
                return CompiledRule(expression: nil, action: .hide, authorPeerId: authorPeerId)
            }
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty, let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
                return nil
            }
            return CompiledRule(expression: expression, action: rule.action, authorPeerId: nil)
        }
    }

    public var isEmpty: Bool {
        return self.rules.isEmpty
    }

    public func apply(to text: String, authorPeerId: Int64? = nil) -> NagramRegexFilterResult {
        guard !self.rules.isEmpty else {
            return .visible(text: text, spoilerRanges: [])
        }
        let shouldCache = text.utf16.count <= 4096
        let cacheKey = "\(authorPeerId.map(String.init) ?? "")\u{1f}\(text)"
        if shouldCache, let cachedResult = self.resultCache.get(cacheKey) {
            return cachedResult
        }
        let result = self.applyUncached(to: text, authorPeerId: authorPeerId)
        if shouldCache {
            self.resultCache.set(result, for: cacheKey)
        }
        return result
    }

    private func applyUncached(to text: String, authorPeerId: Int64?) -> NagramRegexFilterResult {
        let currentText = text
        var spoilerRanges: [Range<Int>] = []
        let matchRange = NSRange(location: 0, length: (currentText as NSString).length)
        for rule in self.rules {
            if let ruleAuthorPeerId = rule.authorPeerId {
                if ruleAuthorPeerId == authorPeerId {
                    return .hidden
                }
                continue
            }
            guard let expression = rule.expression else {
                continue
            }
            guard !currentText.isEmpty else {
                continue
            }
            guard expression.firstMatch(in: currentText, options: [], range: matchRange) != nil else {
                continue
            }
            switch rule.action {
            case .hide:
                return .hidden
            case .mask:
                let matches = expression.matches(in: currentText, options: [], range: matchRange)
                for match in matches where match.range.length > 0 {
                    spoilerRanges.append(match.range.location ..< (match.range.location + match.range.length))
                }
            case .maskMessage:
                if matchRange.length > 0 {
                    spoilerRanges.append(0 ..< matchRange.length)
                }
            case .replace:
                return .contentHidden
            }
        }
        return .visible(text: currentText, spoilerRanges: spoilerRanges)
    }

    public func isHidden(text: String, authorPeerId: Int64? = nil) -> Bool {
        if case .hidden = self.apply(to: text, authorPeerId: authorPeerId) {
            return true
        }
        return false
    }

    public func matches(_ text: String, authorPeerId: Int64? = nil) -> Bool {
        return self.isHidden(text: text, authorPeerId: authorPeerId)
    }
}

private let nagramRegexFilterRulesKey = "nagram.regexFilters.rules"
private let nagramRegexFilterDisabledPeerIdsKey = "nagram.regexFilters.disabledPeerIds"
private let nagramRegexFiltersEnabledKey = "nagram.regexFilters.isEnabled"
private let nagramRegexFiltersFilterOutgoingKey = "nagram.regexFilters.filterOutgoing"

// NotificationService 与主 App 不共享 standard defaults，屏蔽规则额外镜像到现有 App Group。
private let nagramRegexFilterSharedDefaults: UserDefaults? = {
    guard !NagramDemoMode.isEnabled else {
        return nil
    }
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
        return nil
    }
    let extensionSuffix = ".NotificationService"
    let baseBundleIdentifier = bundleIdentifier.hasSuffix(extensionSuffix) ? String(bundleIdentifier.dropLast(extensionSuffix.count)) : bundleIdentifier
    return UserDefaults(suiteName: "group.\(baseBundleIdentifier)")
}()

private let nagramRegexFilterDefaults: UserDefaults = {
    let standardDefaults = NagramDemoMode.userDefaults
    guard Bundle.main.bundleIdentifier?.hasSuffix(".NotificationService") != true else {
        return nagramRegexFilterSharedDefaults ?? standardDefaults
    }
    if let sharedDefaults = nagramRegexFilterSharedDefaults {
        for key in [nagramRegexFilterRulesKey, nagramRegexFilterDisabledPeerIdsKey, nagramRegexFiltersEnabledKey, nagramRegexFiltersFilterOutgoingKey] {
            if let value = standardDefaults.object(forKey: key) {
                sharedDefaults.set(value, forKey: key)
            } else {
                sharedDefaults.removeObject(forKey: key)
            }
        }
    }
    return standardDefaults
}()

private func nagramMirrorRegexFilterValue(_ value: Any?, forKey key: String) {
    guard let sharedDefaults = nagramRegexFilterSharedDefaults else {
        return
    }
    if let value {
        sharedDefaults.set(value, forKey: key)
    } else {
        sharedDefaults.removeObject(forKey: key)
    }
}

private final class NagramRegexFilterMatcherCache {
    private var rules: [NagramRegexFilterRule]?
    private var matcher: NagramRegexFilterMatcher?
    private let lock = NSLock()

    func matcher(for rules: [NagramRegexFilterRule]) -> NagramRegexFilterMatcher? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if self.rules == rules {
            return self.matcher
        }
        let matcher = NagramRegexFilterMatcher(rules: rules)
        self.rules = rules
        self.matcher = matcher.isEmpty ? nil : matcher
        return self.matcher
    }

    func invalidate() {
        self.lock.lock()
        self.rules = nil
        self.matcher = nil
        self.lock.unlock()
    }
}

private let nagramRegexFilterMatcherCache = NagramRegexFilterMatcherCache()

public extension NagramSettings {
    var regexFiltersEnabled: Bool {
        get {
            guard nagramRegexFilterDefaults.object(forKey: nagramRegexFiltersEnabledKey) != nil else {
                return true
            }
            return nagramRegexFilterDefaults.bool(forKey: nagramRegexFiltersEnabledKey)
        }
        set {
            guard self.regexFiltersEnabled != newValue else {
                return
            }
            if newValue {
                NagramDemoMode.userDefaults.removeObject(forKey: nagramRegexFiltersEnabledKey)
                nagramMirrorRegexFilterValue(nil, forKey: nagramRegexFiltersEnabledKey)
            } else {
                NagramDemoMode.userDefaults.set(false, forKey: nagramRegexFiltersEnabledKey)
                nagramMirrorRegexFilterValue(false, forKey: nagramRegexFiltersEnabledKey)
            }
            self.notifyRegexFiltersChanged()
        }
    }

    var regexFiltersFilterOutgoing: Bool {
        get {
            guard nagramRegexFilterDefaults.object(forKey: nagramRegexFiltersFilterOutgoingKey) != nil else {
                return true
            }
            return nagramRegexFilterDefaults.bool(forKey: nagramRegexFiltersFilterOutgoingKey)
        }
        set {
            guard self.regexFiltersFilterOutgoing != newValue else {
                return
            }
            if newValue {
                NagramDemoMode.userDefaults.removeObject(forKey: nagramRegexFiltersFilterOutgoingKey)
                nagramMirrorRegexFilterValue(nil, forKey: nagramRegexFiltersFilterOutgoingKey)
            } else {
                NagramDemoMode.userDefaults.set(false, forKey: nagramRegexFiltersFilterOutgoingKey)
                nagramMirrorRegexFilterValue(false, forKey: nagramRegexFiltersFilterOutgoingKey)
            }
            self.notifyRegexFiltersChanged()
        }
    }

    var regexFilterRules: [NagramRegexFilterRule] {
        get {
            guard let data = nagramRegexFilterDefaults.data(forKey: nagramRegexFilterRulesKey),
                  let rules = try? JSONDecoder().decode([NagramRegexFilterRule].self, from: data) else {
                return []
            }
            return rules
        }
        set {
            if newValue.isEmpty {
                NagramSettingsCloudSync.shared.removeObject(forKey: nagramRegexFilterRulesKey)
                nagramMirrorRegexFilterValue(nil, forKey: nagramRegexFilterRulesKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                NagramSettingsCloudSync.shared.set(data, forKey: nagramRegexFilterRulesKey)
                nagramMirrorRegexFilterValue(data, forKey: nagramRegexFilterRulesKey)
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

    func isRegexFilteringEnabled(peerId: Int64?, isOutgoing: Bool = false) -> Bool {
        guard self.regexFiltersEnabled else {
            return false
        }
        if isOutgoing && !self.regexFiltersFilterOutgoing {
            return false
        }
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

    func regexFilterMatcher(peerId: Int64?, isOutgoing: Bool = false) -> NagramRegexFilterMatcher? {
        guard self.isRegexFilteringEnabled(peerId: peerId, isOutgoing: isOutgoing) else {
            return nil
        }
        return nagramRegexFilterMatcherCache.matcher(for: self.regexFilterRules)
    }
}

private extension NagramSettings {
    var regexFilterDisabledPeerIds: Set<Int64> {
        get {
            let values = nagramRegexFilterDefaults.stringArray(forKey: nagramRegexFilterDisabledPeerIdsKey) ?? []
            return Set(values.compactMap(Int64.init))
        }
        set {
            if newValue.isEmpty {
                NagramSettingsCloudSync.shared.removeObject(forKey: nagramRegexFilterDisabledPeerIdsKey)
                nagramMirrorRegexFilterValue(nil, forKey: nagramRegexFilterDisabledPeerIdsKey)
            } else {
                let values = newValue.map { String($0) }.sorted()
                NagramSettingsCloudSync.shared.set(values, forKey: nagramRegexFilterDisabledPeerIdsKey)
                nagramMirrorRegexFilterValue(values, forKey: nagramRegexFilterDisabledPeerIdsKey)
            }
        }
    }

    func notifyRegexFiltersChanged() {
        nagramRegexFilterMatcherCache.invalidate()
        NotificationCenter.default.post(name: .nagramRegexFiltersDidChange, object: self)
    }
}
