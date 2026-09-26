import Postbox

public class AudioTranscriptionMessageAttribute: MessageAttribute, Equatable {
    // MARK: NAGRAM — Keep external transcripts separate from Telegram updates and ratings.
    public enum Source: Int32 {
        case legacy = 0
        case telegram = 1
        case local = 2
        case external = 3
    }

    public enum TranscriptionError: Int32, Error {
        case generic = 0
        case tooLong = 1
    }
    
    public let id: Int64
    public let text: String
    public let isPending: Bool
    public let didRate: Bool
    public let error: TranscriptionError?

    // MARK: NAGRAM
    public let source: Source
    public let requestId: Int64?

    public var canRate: Bool {
        return self.id != 0 && (self.source == .legacy || self.source == .telegram)
    }

    public var associatedPeerIds: [PeerId] {
        return []
    }
    
    // MARK: NAGRAM
    public init(id: Int64, text: String, isPending: Bool, didRate: Bool, error: TranscriptionError?, source: Source = .legacy, requestId: Int64? = nil) {
        self.id = id
        self.text = text
        self.isPending = isPending
        self.didRate = didRate
        self.error = error
        self.source = source
        self.requestId = requestId
    }
    
    required public init(decoder: PostboxDecoder) {
        self.id = decoder.decodeInt64ForKey("id", orElse: 0)
        self.text = decoder.decodeStringForKey("text", orElse: "")
        self.isPending = decoder.decodeBoolForKey("isPending", orElse: false)
        self.didRate = decoder.decodeBoolForKey("didRate", orElse: false)
        if let errorValue = decoder.decodeOptionalInt32ForKey("error") {
            self.error = TranscriptionError(rawValue: errorValue)
        } else {
            self.error = nil
        }
        // MARK: NAGRAM
        self.source = Source(rawValue: decoder.decodeInt32ForKey("nagramSource", orElse: 0)) ?? .legacy
        self.requestId = decoder.decodeOptionalInt64ForKey("nagramRequestId")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.id, forKey: "id")
        encoder.encodeString(self.text, forKey: "text")
        encoder.encodeBool(self.isPending, forKey: "isPending")
        encoder.encodeBool(self.didRate, forKey: "didRate")
        if let error = self.error {
            encoder.encodeInt32(error.rawValue, forKey: "error")
        } else {
            encoder.encodeNil(forKey: "error")
        }
        // MARK: NAGRAM
        encoder.encodeInt32(self.source.rawValue, forKey: "nagramSource")
        if let requestId = self.requestId {
            encoder.encodeInt64(requestId, forKey: "nagramRequestId")
        } else {
            encoder.encodeNil(forKey: "nagramRequestId")
        }
    }
    
    public static func ==(lhs: AudioTranscriptionMessageAttribute, rhs: AudioTranscriptionMessageAttribute) -> Bool {
        if lhs.id != rhs.id {
            return false
        }
        if lhs.text != rhs.text {
            return false
        }
        if lhs.isPending != rhs.isPending {
            return false
        }
        if lhs.didRate != rhs.didRate {
            return false
        }
        if lhs.error != rhs.error {
            return false
        }
        // MARK: NAGRAM
        if lhs.source != rhs.source || lhs.requestId != rhs.requestId {
            return false
        }
        return true
    }
    
    func merge(withPrevious other: AudioTranscriptionMessageAttribute) -> AudioTranscriptionMessageAttribute {
        // MARK: NAGRAM — Only an explicit new client request may replace an external transcript.
        if other.source == .external && self.source != .external {
            if !((self.source == .telegram || self.source == .local) && self.requestId != nil && self.isPending && self.id == 0) {
                return other
            }
        }
        let sameTranscription = self.id == other.id && self.canRate && other.canRate
        return AudioTranscriptionMessageAttribute(id: self.id, text: self.text, isPending: self.isPending, didRate: self.didRate || (sameTranscription && other.didRate), error: self.error, source: self.source, requestId: self.requestId)
    }
    
    func withDidRate() -> AudioTranscriptionMessageAttribute {
        // MARK: NAGRAM
        return AudioTranscriptionMessageAttribute(id: self.id, text: self.text, isPending: self.isPending, didRate: true, error: self.error, source: self.source, requestId: self.requestId)
    }
}
