import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientOfflineTests {
    private let offlineValues: [String: ServedValue] = [
        "dark-mode": true,
        "welcome-message": "Hello",
        "max-retries": 3,
        "discount-rate": 0.15,
        "theme": ["primaryColor": "blue", "cornerRadius": 8],
    ]

    @Test func servesEachValueAsItsConfigType() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-1"))

        #expect(client.value(for: "dark-mode", default: false) == true)
        #expect(client.value(for: "welcome-message", default: "") == "Hello")
        #expect(client.value(for: "max-retries", default: 0) == 3)
        #expect(client.value(for: "discount-rate", default: 0.0) == 0.15)
        #expect(
            client.value(for: "theme", as: Theme.self, default: Theme(primaryColor: "", cornerRadius: 0))
                == Theme(primaryColor: "blue", cornerRadius: 8)
        )
    }

    @Test func servesAValueWithTheFoundMatchReason() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-1"))

        let evaluations = StreamReader(client.evaluations)
        _ = client.value(for: "dark-mode", default: false)

        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .foundMatch)
        #expect(evaluation.isDefaultValue == false)
        #expect(evaluation.context == ConfigDirectorContext(id: "user-1"))
    }

    @Test func servesTheSameValuesToAnotherContext() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-1"))

        await client.updateContext(ConfigDirectorContext(id: "user-2", traits: ["plan": "pro"]))

        #expect(client.context == ConfigDirectorContext(id: "user-2", traits: ["plan": "pro"]))
        #expect(client.value(for: "dark-mode", default: false) == true)
        #expect(client.value(for: "max-retries", default: 0) == 3)
    }

    @Test func noSourceServesInCodeDefaultsAsConfigStateMissing() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline)
        defer { client.close() }

        await client.initialize()

        #expect(client.isReady)
        let evaluations = StreamReader(client.evaluations)
        #expect(client.value(for: "dark-mode", default: false) == false)
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.reason == .configStateMissing)
    }

    @Test func isReadyAtOnceWithTheReadyEventPublishedOnce() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues, timeout: 5)
        defer { client.close() }
        let events = StreamReader(client.events)
        let startedAt = ProcessInfo.processInfo.systemUptime

        await client.initialize(context: ConfigDirectorContext(id: "user-1"))

        #expect(ProcessInfo.processInfo.systemUptime - startedAt < 1)
        #expect(client.isReady)
        #expect(client.isInitializing == false)
        #expect(await describe(events.next()) == "contextUpdated(user-1)")
        #expect(await describe(events.next()) == "ready(initialization)")
        #expect(await describe(events.next()) == "configsUpdated")
        #expect(await events.next(timeout: 0.3) == nil)
    }

    @Test func updateContextCompletesAtOnceAndKeepsEveryValue() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues, timeout: 5)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-1"))
        let events = StreamReader(client.events)
        let startedAt = ProcessInfo.processInfo.systemUptime

        await client.updateContext(ConfigDirectorContext(id: "user-2"))

        #expect(ProcessInfo.processInfo.systemUptime - startedAt < 1)
        #expect(client.value(for: "welcome-message", default: "") == "Hello")
        #expect(await describe(events.next()) == "contextUpdated(user-2)")
        #expect(await describe(events.next()) == "ready(context update)")
        #expect(await describe(events.next()) == "configsUpdated")
        #expect(await events.next(timeout: 0.3) == nil)
    }

    @Test func aWatchYieldsTheValueOnceAndNeverAgain() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }
        let retries = StreamReader(client.values(for: "max-retries", default: 0))
        #expect(await retries.next() == 0)

        await client.initialize()
        #expect(await retries.next() == 3)

        await client.updateContext(ConfigDirectorContext(id: "user-2"))
        #expect(await retries.next(timeout: 0.3) == nil)
    }

    @Test func aValueOfAnotherTypeServesTheInCodeDefault() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }
        await client.initialize()

        let evaluations = StreamReader(client.evaluations)
        #expect(client.value(for: "dark-mode", default: "off") == "off")

        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.reason == .typeMismatch)
    }

    @Test func opensNoConnectionAndSendsNoTelemetry() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-1"))

        for _ in 0 ..< 5 {
            _ = client.value(for: "dark-mode", default: false)
        }
        await settle(0.3)

        #expect(fixture.streamRequests.isEmpty)
        #expect(fixture.pollRequests.isEmpty)
        #expect(fixture.telemetryRequests.isEmpty)
    }

    @Test func doesNotObserveTheAppLifecycle() async throws {
        let fixture = ClientFixture()
        let observer = RecordingLifecycleObserver()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues, lifecycle: observer)
        defer { client.close() }

        await client.initialize()

        #expect(observer.isObserving == false)
    }

    @Test func pauseNetworkAndResumeNetworkDoNothing() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues)
        defer { client.close() }
        await client.initialize()
        let events = StreamReader(client.events)

        client.pauseNetwork()
        #expect(client.isReady)

        await client.resumeNetwork()
        #expect(client.isReady)
        #expect(client.value(for: "dark-mode", default: false) == true)
        #expect(await events.next(timeout: 0.3) == nil)
    }
}

private func describe(_ event: ClientEvent?) -> String? {
    switch event {
    case let .ready(reason)?: "ready(\(reason))"
    case .configsUpdated?: "configsUpdated"
    case let .contextUpdated(context)?: "contextUpdated(\(context?.id ?? "none"))"
    case nil: nil
    }
}
