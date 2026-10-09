import Foundation
import NagramSettings
import SwiftSignalKit
import TelegramCore

/// Identifies one chat-message translation request. The source text is part of it, so an edited message is requested again.
struct NagramTranslationRequestKey: Hashable {
    let accountPeerId: EnginePeer.Id
    let messageId: EngineMessage.Id
    let provider: NagramTranslationProvider
    let toLang: String
    let keepsFormatting: Bool
    let sourceText: String
}

// MARK: NAGRAM — Shared by every chat: the history list resubmits visible messages while their translation is still running, and one batch may hold dozens of messages.
final class NagramTranslationRequestQueue {
    static let shared = NagramTranslationRequestQueue(limit: 5)

    private final class Entry {
        var start: (() -> Void)?
        var isRunning = false
        var isFinished = false
    }

    private let queue = Queue()
    private let limit: Int
    private var runningCount = 0
    private var pending: [Entry] = []
    private let inFlightKeys = Atomic<Set<NagramTranslationRequestKey>>(value: Set())

    private init(limit: Int) {
        self.limit = limit
    }

    /// Starts `signal` once fewer than `limit` signals are running. Time spent waiting is not part of `signal`.
    func limited<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> {
        return Signal { subscriber in
            let entry = Entry()
            let disposable = MetaDisposable()
            let finish: () -> Void = {
                self.queue.async {
                    guard !entry.isFinished else {
                        return
                    }
                    entry.isFinished = true
                    entry.start = nil
                    if entry.isRunning {
                        self.runningCount -= 1
                        self.startPending()
                    }
                }
            }
            entry.start = {
                disposable.set(signal.start(next: { next in
                    subscriber.putNext(next)
                }, error: { error in
                    subscriber.putError(error)
                    finish()
                }, completed: {
                    subscriber.putCompletion()
                    finish()
                }))
            }
            self.queue.async {
                self.pending.append(entry)
                self.startPending()
            }
            return ActionDisposable {
                disposable.dispose()
                finish()
            }
        }
    }

    /// Runs `signal` unless a signal with the same `key` is still running, in which case it completes right away.
    func deduplicated(key: NagramTranslationRequestKey, _ signal: Signal<Never, NoError>) -> Signal<Never, NoError> {
        return Signal { subscriber in
            var isNew = false
            let _ = self.inFlightKeys.modify { keys in
                var keys = keys
                isNew = keys.insert(key).inserted
                return keys
            }
            guard isNew else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let disposable = signal.start(completed: {
                subscriber.putCompletion()
            })
            return ActionDisposable {
                disposable.dispose()
                let _ = self.inFlightKeys.modify { keys in
                    var keys = keys
                    keys.remove(key)
                    return keys
                }
            }
        }
    }

    private func startPending() {
        while self.runningCount < self.limit && !self.pending.isEmpty {
            let entry = self.pending.removeFirst()
            guard !entry.isFinished, let start = entry.start else {
                continue
            }
            entry.start = nil
            entry.isRunning = true
            self.runningCount += 1
            start()
        }
    }
}
