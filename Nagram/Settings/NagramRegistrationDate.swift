import Foundation

public struct NagramRegistrationDateResult: Equatable {
    public enum Kind: Equatable {
        case exact
        case approximately
        case newerThan
        case olderThan
    }

    public let kind: Kind
    public let date: String
}

public enum NagramRegistrationDateState: Equatable {
    case loading
    case ready(NagramRegistrationDateResult)
    case failed
}

public final class NagramRegistrationDateService {
    public static let shared = NagramRegistrationDateService()

    private struct RequestBody: Encodable {
        let telegramId: Int64
    }

    private struct ResponseBody: Decodable {
        struct Payload: Decodable {
            let type: String
            let date: String
        }

        let data: Payload
    }

    private let endpoint = URL(string: "https://restore-access.indream.app/regdate")!
    private let apiKey = "e758fb28-79be-4d1c-af6b-066633ded128"
    private let lock = NSLock()
    private var states: [Int64: NagramRegistrationDateState] = [:]
    private var callbacks: [Int64: [() -> Void]] = [:]
    private var failureTimestamps: [Int64: Date] = [:]

    private init() {
    }

    public func state(for userId: Int64) -> NagramRegistrationDateState? {
        self.lock.lock()
        let state = self.states[userId]
        self.lock.unlock()
        return state
    }

    public func request(userId: Int64, completion: @escaping () -> Void) {
        guard userId != 0 else {
            return
        }

        var shouldStartRequest = false
        self.lock.lock()
        if let state = self.states[userId] {
            switch state {
            case .ready:
                self.lock.unlock()
                return
            case .loading:
                var callbacks = self.callbacks[userId] ?? []
                callbacks.append(completion)
                self.callbacks[userId] = callbacks
                self.lock.unlock()
                return
            case .failed:
                if let failureTimestamp = self.failureTimestamps[userId], Date().timeIntervalSince(failureTimestamp) < 60.0 {
                    self.lock.unlock()
                    return
                }
            }
        }

        self.states[userId] = .loading
        self.callbacks[userId] = (self.callbacks[userId] ?? []) + [completion]
        shouldStartRequest = true
        self.lock.unlock()

        if shouldStartRequest {
            self.startRequest(userId: userId)
        }
    }

    private func startRequest(userId: Int64) {
        var request = URLRequest(url: self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("okhttp/4.5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(self.apiKey, forHTTPHeaderField: "X-Api-Key")

        do {
            request.httpBody = try JSONEncoder().encode(RequestBody(telegramId: userId))
        } catch {
            self.complete(userId: userId, state: .failed)
            return
        }

        URLSession.shared.dataTask(with: request, completionHandler: { [weak self] data, response, error in
            guard let self else {
                return
            }
            guard error == nil, let data else {
                self.complete(userId: userId, state: .failed)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
                self.complete(userId: userId, state: .failed)
                return
            }

            do {
                let response = try JSONDecoder().decode(ResponseBody.self, from: data)
                guard let kind = NagramRegistrationDateResult.Kind(apiType: response.data.type), !response.data.date.isEmpty else {
                    self.complete(userId: userId, state: .failed)
                    return
                }
                self.complete(userId: userId, state: .ready(NagramRegistrationDateResult(kind: kind, date: response.data.date)))
            } catch {
                self.complete(userId: userId, state: .failed)
            }
        }).resume()
    }

    private func complete(userId: Int64, state: NagramRegistrationDateState) {
        self.lock.lock()
        self.states[userId] = state
        if state == .failed {
            self.failureTimestamps[userId] = Date()
        } else {
            self.failureTimestamps.removeValue(forKey: userId)
        }
        let callbacks = self.callbacks.removeValue(forKey: userId) ?? []
        self.lock.unlock()

        DispatchQueue.main.async {
            for callback in callbacks {
                callback()
            }
        }
    }
}

private extension NagramRegistrationDateResult.Kind {
    init?(apiType: String) {
        switch apiType {
        case "TYPE_EXACTLY":
            self = .exact
        case "TYPE_APPROX":
            self = .approximately
        case "TYPE_NEWER":
            self = .newerThan
        case "TYPE_OLDER":
            self = .olderThan
        default:
            return nil
        }
    }
}
