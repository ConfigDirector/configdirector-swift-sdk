@testable import ConfigDirector
import Foundation
import Testing

private final class RecordingTelemetry: TelemetryClient {
    private let contexts = Locked<[ConfigDirectorContext?]>([])

    var updatedContexts: [ConfigDirectorContext?] {
        contexts.withLock { $0 }
    }

    func evaluatedConfig(_: EvaluatedConfigEvent) {}

    func recordInvalidContextSubmission(contextKindSample _: String) {}

    func updateContext(_ context: ConfigDirectorContext?) {
        contexts.withLock { $0.append(context) }
    }

    func flush() async {}

    func close() {}
}

struct ConfigStoreTests {
    private let telemetry = RecordingTelemetry()
    private let store: ConfigStore
    private let events: StreamReader<ClientEvent>

    init() {
        store = ConfigStore(logger: ConsoleLogger(level: .off), telemetry: telemetry, caching: .keepNothing)
        events = StreamReader(store.events.subscribe())
    }

    private func nextEvents(_ count: Int) async -> [String] {
        var names: [String] = []
        while names.count < count, let event = await events.next() {
            switch event {
            case .ready: names.append("ready")
            case .configsUpdated: names.append("configsUpdated")
            case .contextUpdated: names.append("contextUpdated")
            case .cachedValuesLoaded: names.append("cachedValuesLoaded")
            }
        }
        return names
    }

    private func nextConfigsUpdate() async -> ConfigsUpdate? {
        while let event = await events.next() {
            if case let .configsUpdated(update) = event {
                return update
            }
        }
        return nil
    }

    @Test func reportsTheKeysAFullSetDroppedAsRemoved() async {
        store.applyReceivedConfigSet(ConfigSet(configs: [
            "a": .make(key: "a", type: .string, value: "1"),
            "b": .make(key: "b", type: .string, value: "2"),
            "c": .make(key: "c", type: .string, value: "3"),
        ]))
        _ = await nextConfigsUpdate()

        store.applyReceivedConfigSet(ConfigSet(configs: [
            "b": .make(key: "b", type: .string, value: "changed"),
        ]))

        let update = await nextConfigsUpdate()
        #expect(update?.keys == ["b"])
        #expect(update?.removedKeys.sorted() == ["a", "c"])
        #expect(store.evaluate("a", default: "gone").value == "gone")
    }

    @Test func reportsNothingRemovedOnTheFirstSetOrADelta() async {
        store.applyReceivedConfigSet(ConfigSet(configs: [
            "a": .make(key: "a", type: .string, value: "1"),
        ]))
        let first = await nextConfigsUpdate()

        store.applyReceivedConfigSet(ConfigSet(
            configs: ["b": .make(key: "b", type: .string, value: "2")],
            kind: .delta
        ))

        let delta = await nextConfigsUpdate()
        #expect(first?.removedKeys == [])
        #expect(delta?.keys == ["b"])
        #expect(delta?.removedKeys == [])
        #expect(store.evaluate("a", default: "gone").value == "1")
    }

    @Test func appliesThePendingContextBeforeReadyWhenConfigStateArrivesFirst() async {
        let context = ConfigDirectorContext(id: "user-1")
        _ = store.beginConnect(reason: .contextUpdate, suppliedContext: context)

        store.applyReceivedConfigSet(ConfigSet(configs: [:]))

        #expect(store.context == context)
        #expect(telemetry.updatedContexts == [context])
        #expect(await nextEvents(3) == ["contextUpdated", "ready", "configsUpdated"])
    }

    @Test func appliesThePendingContextOnlyOnceWhenTheTransportConnectsFirst() async {
        let context = ConfigDirectorContext(id: "user-1")
        _ = store.beginConnect(reason: .initialization, suppliedContext: context)

        store.applyPendingContext()
        store.applyReceivedConfigSet(ConfigSet(configs: [:]))

        #expect(store.context == context)
        #expect(telemetry.updatedContexts == [context])
        #expect(await nextEvents(3) == ["contextUpdated", "ready", "configsUpdated"])
        #expect(await events.next(timeout: 0.1) == nil)
    }

    @Test func stopsWaitingForReadyWhenTheCallerIsCancelled() async {
        let waiting = Task { [store] in
            await store.waitUntilReady(timeout: 5)
        }
        await settle(0.05)

        waiting.cancel()

        #expect(await withTimeout { await waiting.value } != nil, "a cancelled caller kept waiting")
    }

    @Test func returnsAtOnceWhenTheCallerWasCancelledBeforeWaitingForReady() async {
        let waiting = Task { [store] in
            withUnsafeCurrentTask { $0?.cancel() }
            await store.waitUntilReady(timeout: 5)
        }

        #expect(await withTimeout { await waiting.value } != nil, "a cancelled caller kept waiting")
    }

    @Test func abandoningAConnectKeepsThePreviousContext() {
        let previous = ConfigDirectorContext(id: "previous")
        _ = store.beginConnect(reason: .initialization, suppliedContext: previous)
        store.applyPendingContext()

        _ = store.beginConnect(
            reason: .contextUpdate,
            suppliedContext: ConfigDirectorContext(id: "abandoned")
        )
        store.abandonConnect()
        store.applyReceivedConfigSet(ConfigSet(configs: [:]))

        #expect(store.context == previous)
        #expect(telemetry.updatedContexts == [previous])
    }
}
