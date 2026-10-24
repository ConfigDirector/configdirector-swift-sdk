import ConfigDirector
import Foundation
import Testing

/// A client that received config state, then relaunched with the same context and no network,
/// serves the values kept on the device until live values arrive.
struct ConfigDirectorClientCachedValuesTests {
    private let provider = RecordingCachingProvider()

    @Test func servesTheKeptValuesWithTheCachedReasonWhenTheServerCannotBeReached() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        let evaluations = StreamReader(client.evaluations)

        let value = client.value(for: "dark-mode", default: false)

        #expect(value == true)
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .cached)
        #expect(evaluation.isDefaultValue == false)
        #expect(evaluation.valueID == "on")
    }

    @Test func isNotReadyWhileServingTheKeptValues() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.value(for: "welcome-message", default: "") == "Hello")
        #expect(client.isReady == false)
        #expect(client.isInitializing)
    }

    @Test func publishesCachedValuesLoadedThenConfigsUpdatedWithTheKeptKeys() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        let events = StreamReader(client.events)

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(await events.next(where: isCachedValuesLoaded) != nil)
        guard case let .configsUpdated(update)? = await events.next(where: isConfigsUpdated) else {
            Issue.record("configsUpdated was not published after cachedValuesLoaded")
            return
        }
        #expect(update.keys.sorted() == [
            "dark-mode",
            "discount-rate",
            "max-retries",
            "theme",
            "welcome-message",
        ])
        #expect(update.removedKeys.isEmpty)
        #expect(
            await events.next(timeout: 0.3, where: isReady) == nil,
            "ready is not published for kept values"
        )
    }

    @Test func aWatchYieldsTheKeptValue() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        let retries = StreamReader(client.values(for: "max-retries", default: 0))
        #expect(await retries.next() == 0)

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(await retries.next() == 3)
    }

    @Test func liveValuesReplaceTheKeptValuesAndTheClientBecomesReady() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([ServedConfig("dark-mode", "boolean", "false", valueID: "off")]))
        let client = try fixture.makeClient(caching: CachingOptions(provider: provider))
        defer { client.close() }
        let events = StreamReader(client.events)

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.isReady)
        #expect(client.isInitializing == false)
        #expect(await events.next(where: isReady) != nil)
        let evaluations = StreamReader(client.evaluations)
        #expect(client.value(for: "dark-mode", default: true) == false)
        #expect(try #require(await evaluations.next()).reason == .foundMatch)
        #expect(client.value(for: "welcome-message", default: "gone") == "gone")
        #expect(try #require(await evaluations.next()).reason == .configStateMissing)
    }

    @Test func rewritesTheEntryWithTheLivePayloadThatReplacedTheKeptValues() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([ServedConfig("dark-mode", "boolean", "false", valueID: "off")]))
        let client = try fixture.makeClient(caching: CachingOptions(provider: provider))
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(await waitUntil { (try? provider.storedEntry())?.configs["dark-mode"]?.value == "false" })
        #expect(try provider.storedEntry()?.configs["welcome-message"] == nil)
    }

    @Test func aFullPayloadReplacingKeptValuesListsTheKeysItNoLongerCarriesAsRemoved() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([ServedConfig("dark-mode", "boolean", "false")]))
        let client = try fixture.makeClient(caching: CachingOptions(provider: provider))
        defer { client.close() }
        let events = StreamReader(client.events)

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let withRemovals = await events.next {
            if case let .configsUpdated(update) = $0, !update.removedKeys.isEmpty {
                true
            } else {
                false
            }
        }
        guard case let .configsUpdated(update)? = withRemovals else {
            Issue.record("no configsUpdated with removed keys was published")
            return
        }
        #expect(update.removedKeys.sorted() == ["discount-rate", "max-retries", "theme", "welcome-message"])
    }

    @Test func rewritesTheEntryWithTheMergedMapAfterADelta() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(caching: CachingOptions(provider: provider))
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        #expect(await waitUntil { provider.writes.count == 1 })

        fixture.pushToStream(deltaConfigSet([ServedConfig("max-retries", "integer", "5", valueID: "five")]))

        #expect(await waitUntil { provider.writes.count == 2 })
        let entry = try #require(try provider.storedEntry())
        #expect(entry.configs["max-retries"]?.value == "5")
        #expect(entry.configs["max-retries"]?.valueId == "five")
        #expect(entry.configs["dark-mode"]?.value == "true")
        #expect(entry.configs.count == 5)
    }

    @Test func aLaunchWithAnotherContextServesInCodeDefaultsUntilLiveValuesArrive() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        let events = StreamReader(client.events)

        await client.initialize(context: ConfigDirectorContext(id: "user-456"))

        let evaluations = StreamReader(client.evaluations)
        #expect(client.value(for: "dark-mode", default: false) == false)
        #expect(try #require(await evaluations.next()).reason == .clientNotReady)
        #expect(await events.next(where: isCachedValuesLoaded) == nil)
        #expect(provider.removes == 0, "the previous person's entry stays until a payload replaces it")
    }

    @Test func thePayloadForAnotherContextReplacesTheEntry() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([ServedConfig("dark-mode", "boolean", "false")]))
        let client = try fixture.makeClient(caching: CachingOptions(provider: provider))
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-456"))

        #expect(await waitUntil { (try? provider.storedEntry())?.contextTag.contextId == "user-456" })
        #expect(try provider.storedEntry()?.configs["dark-mode"]?.value == "false")
    }

    @Test func aFirstLaunchServesInCodeDefaultsUntilThePayloadArrives() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.value(for: "dark-mode", default: false) == false)
        #expect(provider.reads == 1)
        #expect(provider.writes.isEmpty)
        #expect(provider.removes == 0)
    }

    @Test func aContextUpdateWithoutNetworkKeepsServingTheKeptValues() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        #expect(client.value(for: "dark-mode", default: false) == true)

        await client.updateContext(ConfigDirectorContext(id: "user-456"))

        let evaluations = StreamReader(client.evaluations)
        #expect(client.value(for: "dark-mode", default: false) == true)
        #expect(try #require(await evaluations.next()).reason == .cached)
        #expect(client.isReady == false)
    }

    @Test func aRelaunchPollsWithoutAWatermark() async throws {
        try await keepValuesOnDevice(
            in: provider,
            configSet: configSetJSON(
                [ServedConfig("dark-mode", "boolean", "true")],
                timestamp: "2026-08-29T00:00:00Z"
            ),
            mode: .polling
        )
        let fixture = ClientFixture()
        fixture.servePolling(configSetJSON([ServedConfig("dark-mode", "boolean", "false")]))
        let client = try fixture.makeClient(mode: .polling, caching: CachingOptions(provider: provider))
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(fixture.pollRequests.count == 1)
        #expect(fixture.pollRequests.first?.payload?.lastUpdateTimestamp == nil)
        #expect(client.value(for: "dark-mode", default: true) == false)
    }

    @Test func aKeyAbsentFromTheKeptValuesReportsClientNotReady() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        let evaluations = StreamReader(client.evaluations)

        let value = client.value(for: "unknown", default: "fallback")

        #expect(value == "fallback")
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .clientNotReady)
        #expect(evaluation.isDefaultValue)
    }

    @Test func aKeptValueOfAnotherTypeServesTheInCodeDefault() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        let evaluations = StreamReader(client.evaluations)

        let value = client.value(for: "dark-mode", default: "off")

        #expect(value == "off")
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .typeMismatch)
        #expect(evaluation.isDefaultValue)
    }

    @Test func reportsAnEvaluationServedFromKeptValuesToTelemetryWithTheCachedReason() async throws {
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(for: "dark-mode", default: false)

        #expect(await waitUntil {
            fixture.telemetryReports().contains { !$0.evaluations(of: "dark-mode").isEmpty }
        })
        let reported = try #require(
            fixture.telemetryReports().flatMap { $0.evaluations(of: "dark-mode") }.first?.event
        )
        #expect(reported.evaluationReason == "cached")
        #expect(reported.usedDefault == false)
        #expect(reported.evaluatedValueId == "on")
    }
}
