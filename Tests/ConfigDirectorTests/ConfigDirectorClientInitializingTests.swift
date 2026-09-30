import ConfigDirector
import Foundation
import Testing

/// Exercises when `isInitializing` starts and stops through the public API against a stubbed
/// ConfigDirector server, with nothing inside the SDK replaced.
struct ConfigDirectorClientInitializingTests {
    @Test func stopsInitializingWhenTheServerRejectsTheConnection() async throws {
        let fixture = ClientFixture()
        fixture.rejectStream(statusCode: 401)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize()

        #expect(client.isInitializing == false)
    }

    @Test func stopsInitializingOnceConfigStateArrivesAfterTheTimeout() async throws {
        let fixture = ClientFixture()
        fixture.serveStream()
        let client = try fixture.makeClient(timeout: 0.3)
        defer { client.close() }
        await client.initialize()
        #expect(client.isInitializing)

        fixture.pushToStream(servedConfigSet)

        #expect(await waitUntil { client.isReady })
        #expect(client.isInitializing == false)
    }

    @Test func stopsInitializingWhenClosed() async throws {
        let fixture = ClientFixture()
        fixture.serveStream()
        let client = try fixture.makeClient(timeout: 0.5)
        let initialization = Task { await client.initialize() }
        #expect(await waitUntil { client.isInitializing })

        client.close()

        #expect(client.isInitializing == false)
        await initialization.value
    }

    @Test func aLaterInitializeDoesNotStartInitializingAgain() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream()
        let client = try fixture.makeClient(timeout: 0.3)
        defer { client.close() }
        await client.initialize()

        let secondInitialization = Task { await client.initialize() }
        #expect(await waitUntil { fixture.streamRequests.count == 2 })
        #expect(client.isInitializing == false)
        await secondInitialization.value
        #expect(client.isInitializing == false)
    }

    @Test func updateContextDoesNotStartInitializing() async throws {
        let fixture = ClientFixture()
        fixture.serveStream()
        let client = try fixture.makeClient(timeout: 0.3)
        defer { client.close() }

        let update = Task { await client.updateContext(ConfigDirectorContext(id: "user-123")) }
        #expect(await waitUntil { fixture.streamRequests.count == 1 })
        #expect(client.isInitializing == false)
        await update.value
        #expect(client.isInitializing == false)
    }
}
