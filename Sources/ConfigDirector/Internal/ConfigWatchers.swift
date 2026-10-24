import Foundation

final class ConfigWatchers: Sendable {
    private struct Watcher: Sendable {
        let reevaluate: @Sendable () -> Void
        let finish: @Sendable () -> Void
    }

    private struct State {
        var watchers: [String: [UUID: Watcher]] = [:]
        var isFinished = false
    }

    private let state = Locked(State())

    func stream<Value: Equatable & Sendable>(
        for key: String,
        evaluate: @escaping @Sendable () -> Value
    ) -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            let lastEmitted = Locked<Value?>(nil)

            let emitIfChanged: @Sendable () -> Void = {
                let value = evaluate()
                let hasChanged = lastEmitted.withLock { last -> Bool in
                    guard last != value else { return false }
                    last = value
                    return true
                }
                if hasChanged {
                    continuation.yield(value)
                }
            }

            let isFinished = state.withLock { state -> Bool in
                guard !state.isFinished else { return true }
                state.watchers[key, default: [:]][id] = Watcher(
                    reevaluate: emitIfChanged,
                    finish: { continuation.finish() }
                )
                return false
            }

            guard !isFinished else {
                continuation.finish()
                return
            }

            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.watchers[key]?[id] = nil }
            }

            emitIfChanged()
        }
    }

    func reevaluate(keys: [String]) {
        let affected = state.withLock { state in
            keys.compactMap { state.watchers[$0] }.flatMap { Array($0.values) }
        }
        for watcher in affected {
            watcher.reevaluate()
        }
    }

    func reevaluateAll() {
        let all = state.withLock { $0.watchers.values.flatMap { Array($0.values) } }
        for watcher in all {
            watcher.reevaluate()
        }
    }

    func finishAll() {
        let all = state.withLock { state -> [Watcher] in
            state.isFinished = true
            defer { state.watchers.removeAll() }
            return state.watchers.values.flatMap { Array($0.values) }
        }
        for watcher in all {
            watcher.finish()
        }
    }
}
