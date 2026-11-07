import ConfigDirector
import Foundation
import Testing

struct TrackedEventTelemetryTests {
    @Test func putsATrackedEventOnTheNextBatch() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        client.track("checkout-completed", options: TrackOptions(value: 49.9, details: ["plan": "pro"]))

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        #expect(fixture.trackedEvents().count == 1)
        #expect(event.name == "checkout-completed")
        #expect(event.contextKind == "user")
        #expect(event.contextIdentifier == "user-123")

        let body = try #require(fixture.telemetryBodies().first { $0.contains("checkout-completed") })
        #expect(body.contains(#""value":49.9"#))
        #expect(body.contains(#""details":{"plan":"pro"}"#))
    }

    @Test func stampsTheEventWhenTrackIsCalled() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(telemetryFlushInterval: 0.3)
        defer { client.close() }

        let beforeTheCall = Date()
        client.track("checkout-completed")
        let afterTheCall = Date()

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        let happenedAt = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(event.happenedAt)
        let millisecondRounding: TimeInterval = 0.002
        #expect(happenedAt > beforeTheCall.addingTimeInterval(-millisecondRounding))
        #expect(happenedAt <= afterTheCall)
    }

    @Test func reportsAnEventTrackedBeforeTheClientHasAContextWithoutOne() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track("app-opened")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        #expect(event.name == "app-opened")
        #expect(event.contextKind == nil)
        #expect(event.contextIdentifier == nil)
        #expect(logger.warnings.isEmpty)
    }

    @Test func reportsAnEventForAContextWithoutAnIdentifierWithoutOne() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(kind: "device", name: "Kitchen tablet"))

        client.track("app-opened")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        #expect(event.contextKind == nil)
        #expect(event.contextIdentifier == nil)
        #expect(logger.warnings.isEmpty)
    }

    @Test func withholdsTheIdentifierOfAContextMarkedAnonymous() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123", isAnonymous: true))

        client.track("app-opened")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        #expect(event.contextKind == nil)
        #expect(event.contextIdentifier == nil)
        #expect(fixture.telemetryBodies().contains { $0.contains(#""contextIdentifier""#) } == false)
    }

    @Test func reportsTheContextKindGivenWithTheIdentifier() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "device-42", kind: "device"))

        client.track("app-opened")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        #expect(event.contextKind == "device")
        #expect(event.contextIdentifier == "device-42")
    }

    @Test func reportsAnEventWithoutAContextOnceAnInvalidContextKindWasIgnored() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        await client.initialize(context: contextWithAnInvalidContextKind)

        client.track("app-opened")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let event = try #require(fixture.trackedEvents().first)
        #expect(event.contextKind == nil)
        #expect(event.contextIdentifier == nil)
        #expect(logger.errors.count == 1)
        #expect(logger.warnings.isEmpty)
    }

    @Test func tracksForTheContextTheClientHadWhenTrackWasCalled() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-a"))

        client.track("before-the-update")
        await client.updateContext(ConfigDirectorContext(id: "user-b"))
        client.track("after-the-update")

        #expect(await waitUntil { fixture.trackedEvents().count == 2 })
        let identifiersByName = Dictionary(
            uniqueKeysWithValues: fixture.trackedEvents().map { ($0.name, $0.contextIdentifier) }
        )
        #expect(identifiersByName == ["before-the-update": "user-a", "after-the-update": "user-b"])
    }

    @Test func carriesATrackedEventInTheReportOfAnInvalidContextKindThatFollows() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(telemetryFlushInterval: 60)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        client.track("ft-probe-event")
        await client.updateContext(contextWithAnInvalidContextKind)

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        let reports = fixture.telemetryReports()
        let report = try #require(reports.first { !$0.discreteEvents.trackedEvents.isEmpty })
        #expect(report.discreteEvents.trackedEvents.first?.contextIdentifier == "user-123")
        #expect(report.aggregatedEvents.invalidContext.count == 1)
    }

    @Test func sendsAnEventStillWaitingWhenTheClientCloses() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(telemetryFlushInterval: 60)

        client.track("last-event")
        client.close()

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["last-event"])
    }

    @Test func sendsNothingForAnEventTrackedAfterClose() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient()

        client.close()
        client.track("too-late")
        await settle(0.3)

        #expect(fixture.telemetryRequests.isEmpty)
    }

    @Test func sendsNothingForAnEventTrackedAfterTelemetryStoppedOnAFatalResponse() async throws {
        let fixture = ClientFixture(telemetryStatus: 401)
        let client = try fixture.makeClient()
        defer { client.close() }

        client.track("first")
        #expect(await waitUntil { fixture.telemetryRequests.count == 1 })
        await settle(0.1)

        client.track("second")
        await settle(0.3)

        #expect(fixture.telemetryRequests.count == 1)
    }

    @Test func sendsTheNextReportAfterOneRefusedAsTooLarge() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture(telemetryStatus: nil)
        StubURLProtocol.enqueue(
            [.json("{}", statusCode: 413), .json("{}", statusCode: 202)],
            for: fixture.telemetryURL
        )
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track("first")
        #expect(await waitUntil { fixture.telemetryRequests.count == 1 })
        await settle(0.1)

        client.track("second")

        #expect(await waitUntil { fixture.telemetryRequests.count == 2 })
        #expect(fixture.trackedEvents().map(\.name) == ["first", "second"])
        #expect(logger.warnings.count == 1)
    }
}
