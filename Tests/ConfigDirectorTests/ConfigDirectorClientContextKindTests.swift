import ConfigDirector
import Foundation
import Testing

private let userContext = ConfigDirectorContext(id: "user-123")

private extension StreamReader<ClientEvent> {
    func contextOfNextContextUpdate() async -> ConfigDirectorContext?? {
        let event = await next {
            if case .contextUpdated = $0 {
                true
            } else {
                false
            }
        }
        guard case let .contextUpdated(context) = event else { return nil }
        return .some(context)
    }
}

struct ConfigDirectorClientContextKindTests {
    @Test func streamingInitializationIgnoresAContextWithAnInvalidContextKind() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let events = StreamReader(client.events)

        await client.initialize(context: contextWithAnInvalidContextKind)

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [[]])
        #expect(client.context == nil)
        #expect(await events.contextOfNextContextUpdate() == .some(nil))
        #expect(logger.errors.count == 1)
        #expect(logger.errors.first?.contains("Device") == true)
        #expect(client.isReady)
    }

    @Test func streamingContextUpdateDropsThePreviousContextForAnInvalidContextKind() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        await client.initialize(context: userContext)
        let events = StreamReader(client.events)
        let evaluations = StreamReader(client.evaluations)

        await client.updateContext(contextWithAnInvalidContextKind)
        _ = client.value(for: "dark-mode", default: false)

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [["id"], []])
        #expect(client.context == nil)
        #expect(await events.contextOfNextContextUpdate() == .some(nil))
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.context == nil)
        #expect(logger.errors.count == 1)
    }

    @Test func pollingInitializationIgnoresAContextWithAnInvalidContextKind() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.servePolling(servedConfigSet)
        let client = try fixture.makeClient(mode: .polling, logger: logger)
        defer { client.close() }
        let events = StreamReader(client.events)

        await client.initialize(context: contextWithAnInvalidContextKind)

        #expect(fixture.pollRequests.map(\.givenContextFieldNames) == [[]])
        #expect(client.context == nil)
        #expect(await events.contextOfNextContextUpdate() == .some(nil))
        #expect(logger.errors.count == 1)
        #expect(client.isReady)
    }

    @Test func pollingContextUpdateDropsThePreviousContextForAnInvalidContextKind() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.servePolling(servedConfigSet, servedConfigSet)
        let client = try fixture.makeClient(mode: .polling, logger: logger)
        defer { client.close() }
        await client.initialize(context: userContext)
        let events = StreamReader(client.events)

        await client.updateContext(contextWithAnInvalidContextKind)

        #expect(fixture.pollRequests.map(\.givenContextFieldNames) == [["id"], []])
        #expect(client.context == nil)
        #expect(await events.contextOfNextContextUpdate() == .some(nil))
        #expect(logger.errors.count == 1)
    }

    @Test func logsEveryContextUpdateWithAnInvalidContextKind() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        await client.initialize(context: contextWithAnInvalidContextKind)

        await client.updateContext(contextWithAnInvalidContextKind)
        await client.updateContext(contextWithAnInvalidContextKind)

        #expect(logger.errors.count == 3)
    }

    @Test func logsTheFirst128CharactersOfALongInvalidContextKind() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: "device-42",
            kind: String(repeating: "D", count: 200)
        ))

        let error = try #require(logger.errors.first)
        #expect(error.contains(String(repeating: "D", count: 128)))
        #expect(error.contains(String(repeating: "D", count: 129)) == false)
    }

    @Test func resumingAfterAnIgnoredContextReconnectsWithNoContext() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: userContext)
        await client.updateContext(contextWithAnInvalidContextKind)

        client.pauseNetwork()
        await client.resumeNetwork()

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [["id"], [], []])
        #expect(client.context == nil)
    }

    @Test func keepsThePreviousContextWhenTheConnectionAfterAnIgnoredContextFails() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.rejectStream(statusCode: 401)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: userContext)

        await client.updateContext(contextWithAnInvalidContextKind)

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [["id"], []])
        #expect(client.context == userContext)
    }
}
