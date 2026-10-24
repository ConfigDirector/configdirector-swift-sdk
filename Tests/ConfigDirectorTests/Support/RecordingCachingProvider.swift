@testable import ConfigDirector
import Foundation
import Testing

/// A caching provider that keeps the entry in memory and records every call, so a test can see
/// what the SDK read, wrote and removed, and make any operation fail.
final class RecordingCachingProvider: CachingProvider, @unchecked Sendable {
    struct Failure: Error {}

    private struct State {
        var stored: String?
        var reads = 0
        var writes: [String] = []
        var removes = 0
        var readFails = false
        var writeFails = false
        var removeFails = false
        var limit = 256 * 1024
    }

    private let state = Locked(State())

    init(stored: String? = nil, limit: Int = 256 * 1024) {
        state.withLock {
            $0.stored = stored
            $0.limit = limit
        }
    }

    var stored: String? {
        state.withLock(\.stored)
    }

    var reads: Int {
        state.withLock(\.reads)
    }

    var writes: [String] {
        state.withLock(\.writes)
    }

    var removes: Int {
        state.withLock(\.removes)
    }

    func failReads() {
        state.withLock { $0.readFails = true }
    }

    func failWrites() {
        state.withLock { $0.writeFails = true }
    }

    func failRemoves() {
        state.withLock { $0.removeFails = true }
    }

    func read() throws -> String? {
        try state.withLock { state in
            state.reads += 1
            if state.readFails {
                throw Failure()
            }
            return state.stored
        }
    }

    func write(_ value: String) throws {
        try state.withLock { state in
            if state.writeFails {
                throw Failure()
            }
            state.writes.append(value)
            state.stored = value
        }
    }

    func remove() throws {
        try state.withLock { state in
            state.removes += 1
            if state.removeFails {
                throw Failure()
            }
            state.stored = nil
        }
    }

    func sizeLimit() -> Int {
        state.withLock(\.limit)
    }
}

/// The entry the SDK keeps on the device, as the tests read it back.
struct StoredCachedValuesEntry: Decodable {
    struct ContextTag: Decodable {
        var contextKind: String
        var contextId: String?
        var anonymousInstanceId: String?
    }

    struct Config: Decodable {
        var id: String
        var key: String
        var type: String
        var value: String?
        var valueId: String?
    }

    var formatVersion: Int
    var clientSdkKey: String
    var contextTag: ContextTag
    var environmentId: String
    var projectId: String
    var configs: [String: Config]
    var receivedAt: Int64
}

extension RecordingCachingProvider {
    func storedEntry() throws -> StoredCachedValuesEntry? {
        try stored.map { try JSONDecoder().decode(StoredCachedValuesEntry.self, from: Data($0.utf8)) }
    }
}

/// Runs a client to its first payload so `provider` holds an entry for `context`, the way a launch
/// with a network leaves the device before the launch under test.
func keepValuesOnDevice(
    in provider: RecordingCachingProvider,
    configSet: String = servedConfigSet,
    context: ConfigDirectorContext? = ConfigDirectorContext(id: "user-123"),
    mode: ConnectionMode = .streaming
) async throws {
    let fixture = ClientFixture()
    switch mode {
    case .streaming: fixture.serveStream(configSet)
    case .polling: fixture.servePolling(configSet)
    case .offline: break
    }
    let client = try fixture.makeClient(mode: mode, caching: CachingOptions(provider: provider))
    defer { client.close() }
    let writesBefore = provider.writes.count

    await client.initialize(context: context)

    #expect(await waitUntil { provider.writes.count > writesBefore })
}

func isCachedValuesLoaded(_ event: ClientEvent) -> Bool {
    if case .cachedValuesLoaded = event {
        true
    } else {
        false
    }
}

func isConfigsUpdated(_ event: ClientEvent) -> Bool {
    if case .configsUpdated = event {
        true
    } else {
        false
    }
}

func isReady(_ event: ClientEvent) -> Bool {
    if case .ready = event {
        true
    } else {
        false
    }
}

extension ClientFixture {
    /// A client launched after `keepValuesOnDevice(in:)` against a stream that never answers, so
    /// only the values kept on the device can be served.
    func makeClientWithoutNetwork(
        provider: RecordingCachingProvider,
        logger: any ConfigDirectorLogger = ConsoleLogger(level: .off),
        makeClientSession: () -> ClientSession = { ClientSession(instanceID: "instance-1", ephemeral: false) }
    ) throws -> ConfigDirectorClient {
        serveStream()
        return try makeClient(
            timeout: 0.3,
            caching: CachingOptions(provider: provider),
            logger: logger,
            makeClientSession: makeClientSession
        )
    }
}
