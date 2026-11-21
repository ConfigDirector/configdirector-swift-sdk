import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientLateFetchTests {
    @Test func pollingModeStaysNotReadyUntilResumeWhenPausedDuringAContextUpdate() async throws {
        let fixture = ClientFixture()
        let logger = RecordingLogger()
        fixture.servePolling(servedConfigSet)
        let client = try fixture.makeClient(mode: .polling, timeout: 0.3, logger: logger)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "before"))

        fixture.servePollingWhenReleased(configSetJSON([ServedConfig("dark-mode", "boolean", "false")]))
        fixture.servePolling(servedConfigSet)
        let events = client.events.collectUntilFinished()

        let updating = Task { await client.updateContext(ConfigDirectorContext(id: "after")) }
        #expect(await waitUntil { fixture.pollRequests.count == 2 })
        client.pauseNetwork()
        fixture.releaseHeldPollingResponses()
        await updating.value

        #expect(client.isReady == false)
        #expect(client.value(for: "dark-mode", default: false) == true)
        #expect(logger.warnings.contains { $0.contains("Timed out waiting for context update") })

        await client.resumeNetwork()

        #expect(client.isReady)

        client.close()
        let recorded = try #require(await withTimeout { await events.value })
        #expect(readyReasons(in: recorded) == [.networkResume])
    }

    @Test func pollingModeServesTheInCodeDefaultValueWhenClosedDuringTheFirstFetch() async throws {
        let fixture = ClientFixture()
        fixture.servePollingWhenReleased(servedConfigSet)
        let client = try fixture.makeClient(mode: .polling)
        let initializing = Task { await client.initialize(context: ConfigDirectorContext(id: "user-123")) }
        #expect(await waitUntil { fixture.pollRequests.count == 1 })

        client.close()
        fixture.releaseHeldPollingResponses()
        await initializing.value

        #expect(client.value(for: "dark-mode", default: false) == false)
    }
}

private func readyReasons(in events: [ClientEvent]) -> [ConnectReason] {
    events.compactMap { event in
        guard case let .ready(reason) = event else { return nil }
        return reason
    }
}
