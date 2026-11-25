import ConfigDirector
import Foundation
import Testing

private func reportedInvalidContextSubmissions(
    _ fixture: ClientFixture
) async -> [TelemetryReport.AggregatedInvalidContextSubmission] {
    #expect(await waitUntil { !fixture.telemetryReports().flatMap(\.aggregatedEvents.invalidContext).isEmpty
    })
    return fixture.telemetryReports().flatMap(\.aggregatedEvents.invalidContext)
}

private func traits(ofJSONBytes jsonBytes: Int) -> [String: ConfigDirectorContext.TraitValue] {
    ["note": .string(String(repeating: "x", count: jsonBytes - #"{"note":""}"#.utf8.count))]
}

struct ConfigDirectorClientContextSizeTests {
    @Test func initializeWithAnIDOf257CharactersSendsNoContextLogsTheIDLimitAndReportsIdentifierTooLong(
    ) async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: String(repeating: "i", count: 257)))

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [[]])
        #expect(client.context == nil)
        #expect(client.isReady)
        #expect(logger.errors.count == 1)
        #expect(logger.errors.first?
            .contains("for initialization because its id is longer than 256 characters;") == true)
        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["identifier-too-long"])
        #expect(submissions.map(\.event.kindSample) == [nil])
        #expect(submissions.map(\.count) == [1])
    }

    @Test func initializeWithAnIDOf256CharactersSendsIt() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let id = String(repeating: "i", count: 256)

        await client.initialize(context: ConfigDirectorContext(id: id))

        #expect(fixture.streamRequests.map(\.payload?.givenContext.id) == [id])
        #expect(client.context == ConfigDirectorContext(id: id))
        #expect(logger.errors.isEmpty)
    }

    @Test func initializeWithANameOf257CharactersSendsNoContextLogsTheNameLimitAndReportsNameTooLong(
    ) async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: "42",
            name: String(repeating: "n", count: 257)
        ))

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [[]])
        #expect(client.context == nil)
        #expect(logger.errors.count == 1)
        #expect(logger.errors.first?
            .contains("for initialization because its name is longer than 256 characters;") == true)
        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["name-too-long"])
        #expect(submissions.map(\.event.kindSample) == [nil])
        #expect(submissions.map(\.count) == [1])
    }

    @Test func initializeWithANameOf256CharactersSendsIt() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let name = String(repeating: "n", count: 256)

        await client.initialize(context: ConfigDirectorContext(id: "42", name: name))

        #expect(fixture.streamRequests.map(\.payload?.givenContext.name) == [name])
        #expect(client.context == ConfigDirectorContext(id: "42", name: name))
        #expect(logger.errors.isEmpty)
    }

    @Test func initializeWithTraitsOf65537BytesSendsNoContextLogsTheTraitsLimitAndReportsTraitsTooLarge(
    ) async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "42", traits: traits(ofJSONBytes: 65537)))

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [[]])
        #expect(client.context == nil)
        #expect(logger.errors.count == 1)
        #expect(logger.errors.first?
            .contains("for initialization because its traits are over 64 KB of JSON;") == true)
        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["traits-too-large"])
        #expect(submissions.map(\.event.kindSample) == [nil])
        #expect(submissions.map(\.count) == [1])
    }

    @Test func initializeWithTraitsOfExactly65536BytesSendsThem() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let context = ConfigDirectorContext(id: "42", traits: traits(ofJSONBytes: 65536))

        await client.initialize(context: context)

        #expect(fixture.streamRequests.map(\.givenContextTraits?["note"]?.count) == [65525])
        #expect(client.context == context)
        #expect(logger.errors.isEmpty)
    }

    @Test func initializeWithTraitsOfFewerThan65536CharactersButMoreThan65536BytesIgnoresTheContext(
    ) async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: "42",
            traits: ["note": .string(String(repeating: "é", count: 40000))]
        ))

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [[]])
        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["traits-too-large"])
    }

    @Test func initializeWithTraitsOfExactly65536BytesWrittenWithSlashesSendsThem() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let slashes = String(repeating: "/", count: 65525)

        await client.initialize(context: ConfigDirectorContext(id: "42", traits: ["note": .string(slashes)]))

        #expect(fixture.streamRequests.map(\.givenContextTraits?["note"]) == [slashes])
        #expect(fixture.streamRequests.map { $0.body?.contains(#"\/"#) } == [false])
        #expect(logger.errors.isEmpty)
    }

    @Test func initializeWithAnIDOf200EmojiSendsIt() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let id = String(repeating: "😀", count: 200)

        await client.initialize(context: ConfigDirectorContext(id: id))

        #expect(fixture.streamRequests.map(\.payload?.givenContext.id) == [id])
        #expect(logger.errors.isEmpty)
    }

    @Test func initializeWithAnIDOf129AccentedLettersWrittenAs258CodePointsIgnoresTheContext() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: String(repeating: "e\u{301}", count: 129)))

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [[]])
        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["identifier-too-long"])
    }

    @Test func initializeWithAContextOverTheIDAndTraitsLimitsReportsOneSubmissionForTheID() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: String(repeating: "i", count: 257),
            traits: traits(ofJSONBytes: 65537)
        ))

        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["identifier-too-long"])
        #expect(submissions.map(\.count) == [1])
        #expect(logger.errors.count == 1)
    }

    @Test func initializeWithAContextOverTheIDAndNameLimitsReportsTheID() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: String(repeating: "i", count: 257),
            name: String(repeating: "n", count: 257)
        ))

        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["identifier-too-long"])
    }

    @Test func initializeWithAContextOverTheNameAndTraitsLimitsReportsTheName() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: "42",
            name: String(repeating: "n", count: 257),
            traits: traits(ofJSONBytes: 65537)
        ))

        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["name-too-long"])
    }

    @Test func initializeWithAnInvalidContextKindAndAnIDOverTheLimitReportsTheInvalidContextKindOnly(
    ) async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: String(repeating: "i", count: 257),
            kind: "Device"
        ))

        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["invalid-context-kind"])
        #expect(submissions.map(\.event.kindSample) == ["Device"])
        #expect(logger.errors.count == 1)
        #expect(logger.errors.first?.contains("'Device'") == true)
    }

    @Test func updateContextWithANameOf257CharactersStopsUsingThePreviousContextAndLogsTheContextUpdate(
    ) async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "42"))
        let events = StreamReader(client.events)

        await client.updateContext(ConfigDirectorContext(id: "43", name: String(repeating: "n", count: 257)))

        #expect(fixture.streamRequests.map(\.givenContextFieldNames) == [["id"], []])
        #expect(client.context == nil)
        #expect(await events.contextOfNextContextUpdate() == .some(nil))
        #expect(logger.errors.count == 1)
        #expect(logger.errors.first?
            .contains("for context update because its name is longer than 256 characters;") == true)
        let submissions = await reportedInvalidContextSubmissions(fixture)
        #expect(submissions.map(\.event.reason) == ["name-too-long"])
    }

    @Test func pollingSendsNoContextForAContextOverTheTraitsLimitAndReportsItOnce() async throws {
        let fixture = ClientFixture()
        fixture.servePolling(servedConfigSet, servedConfigSet, servedConfigSet, servedConfigSet)
        let client = try fixture.makeClient(mode: .polling, makeTransport: transportPolling(every: 0.05))
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "42", traits: traits(ofJSONBytes: 65537)))

        #expect(await waitUntil { fixture.pollRequests.count >= 3 })
        #expect(fixture.pollRequests.prefix(3).map(\.givenContextFieldNames) == [[], [], []])
        await settle(0.2)
        let submissions = fixture.telemetryReports().flatMap(\.aggregatedEvents.invalidContext)
        #expect(submissions.map(\.event.reason) == ["traits-too-large"])
        #expect(submissions.map(\.count) == [1])
    }
}
