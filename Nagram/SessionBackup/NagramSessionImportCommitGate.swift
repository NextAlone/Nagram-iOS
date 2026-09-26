import Foundation

// Serializes cancellation with the final account-manager transaction. A queued
// transaction must not publish an account after its importing screen has closed.
public final class NagramSessionImportCommitGate {
    private let lock = NSLock()
    private var finished = false

    public init() {
    }

    public func cancel() {
        self.lock.lock()
        self.finished = true
        self.lock.unlock()
    }

    public func commit<T>(_ action: () -> T) -> T? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.finished else {
            return nil
        }
        self.finished = true
        return action()
    }
}
