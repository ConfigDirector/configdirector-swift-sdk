import ConfigDirector
import Foundation

func withTimeout<Value: Sendable>(
    _ seconds: TimeInterval = 2,
    operation: @escaping @Sendable () async -> Value
) async -> Value? {
    await withTaskGroup(of: Value?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next().flatMap(\.self)
        group.cancelAll()
        return result
    }
}

/// Reads an `AsyncStream` one element at a time, giving up rather than hanging the test run.
final class StreamReader<Element: Sendable>: @unchecked Sendable {
    private var iterator: AsyncStream<Element>.AsyncIterator

    init(_ stream: AsyncStream<Element>) {
        iterator = stream.makeAsyncIterator()
    }

    func next(timeout: TimeInterval = 2) async -> Element? {
        await withTimeout(timeout) { [self] in await iterator.next() }.flatMap(\.self)
    }
}

/// Gives already-scheduled work a chance to run before the test looks at the result.
func settle(_ seconds: TimeInterval = 0.15) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

/// Polls `condition` until it holds, rather than sleeping for a fixed time and hoping.
func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        await settle(0.01)
    }
    return condition()
}

/// Keeps what the SDK logged, so a test can assert on what an application would see.
final class RecordingLogger: ConfigDirectorLogger {
    private struct Entry {
        var level: ConfigDirectorLogLevel
        var message: String
        var error: (any Error)?
    }

    let level = ConfigDirectorLogLevel.debug

    private let entries = Locked<[Entry]>([])

    var warnings: [String] {
        entries.withLock { $0.filter { $0.level == .warn }.map(\.message) }
    }

    var errors: [String] {
        entries.withLock { $0.filter { $0.level == .error }.map(\.message) }
    }

    var errorDescriptions: [String] {
        entries.withLock { $0.compactMap { $0.error?.localizedDescription } }
    }

    var messagesAboveDebug: [String] {
        entries.withLock { $0.filter { $0.level != .debug }.map(\.message) }
    }

    func log(_ level: ConfigDirectorLogLevel, message: String, error: (any Error)?) {
        entries.withLock { $0.append(Entry(level: level, message: message, error: error)) }
    }
}

/// A lock for test bookkeeping, since the SDK's own is not visible here.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
