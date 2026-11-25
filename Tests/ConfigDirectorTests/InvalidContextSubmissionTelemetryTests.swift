import ConfigDirector
import Foundation
import Testing

struct InvalidContextSubmissionTelemetryTests {
    private func reportedInvalidContextSubmissionCount(_ fixture: ClientFixture) -> Int {
        fixture.telemetryReports().flatMap(\.aggregatedEvents.invalidContext).map(\.count).reduce(0, +)
    }

    @Test func reportsAnIgnoredContextByItsContextKindAloneEvenWithoutEvaluations() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: contextWithAnInvalidContextKind)

        #expect(await waitUntil { reportedInvalidContextSubmissionCount(fixture) == 1 })
        let report = try #require(fixture.telemetryReports()
            .first { !$0.aggregatedEvents.invalidContext.isEmpty })
        let submission = try #require(report.aggregatedEvents.invalidContext.first)
        #expect(report.aggregatedEvents.invalidContext.count == 1)
        #expect(report.aggregatedEvents.evaluatedConfig.isEmpty)
        #expect(submission.count == 1)
        #expect(submission.event.reason == "invalid-context-kind")
        #expect(submission.event.kindSample == "Device")
        #expect(submission.startTime <= submission.endTime)

        let bodies = fixture.telemetryRequests.compactMap(\.body)
        #expect(bodies.contains { $0.contains("device-42") } == false)
        #expect(bodies.contains { $0.contains("Kitchen tablet") } == false)
        #expect(bodies.contains { $0.contains("t-1000") } == false)
    }

    @Test func reportsTheFirst128CharactersOfALongInvalidContextKind() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(
            id: "device-42",
            kind: String(repeating: "D", count: 200)
        ))

        #expect(await waitUntil { reportedInvalidContextSubmissionCount(fixture) == 1 })
        let submission = try #require(fixture.telemetryReports().flatMap(\.aggregatedEvents.invalidContext)
            .first)
        #expect(submission.event.kindSample == String(repeating: "D", count: 128))
    }

    @Test func countsOneInvalidSubmissionPerInitializationAndContextUpdate() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        await client.initialize(context: contextWithAnInvalidContextKind)
        await client.updateContext(contextWithAnInvalidContextKind)

        #expect(await waitUntil { reportedInvalidContextSubmissionCount(fixture) == 2 })
        await settle(0.3)
        #expect(reportedInvalidContextSubmissionCount(fixture) == 2)
    }

    @Test func countsNoFurtherInvalidSubmissionWhenConfigsAreRead() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: contextWithAnInvalidContextKind)

        _ = client.value(for: "dark-mode", default: false)
        _ = client.value(for: "welcome-message", default: "")

        #expect(await waitUntil {
            fixture.telemetryReports().contains { !$0.evaluations(of: "dark-mode").isEmpty }
        })
        await settle(0.3)
        #expect(reportedInvalidContextSubmissionCount(fixture) == 1)
    }

    @Test func countsNoFurtherInvalidSubmissionWhenTheNetworkResumes() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: contextWithAnInvalidContextKind)
        #expect(await waitUntil { reportedInvalidContextSubmissionCount(fixture) == 1 })

        client.pauseNetwork()
        await client.resumeNetwork()

        #expect(fixture.streamRequests.count == 2)
        await settle(0.3)
        #expect(reportedInvalidContextSubmissionCount(fixture) == 1)
    }

    @Test func countsNoFurtherInvalidSubmissionWhenTheStreamReconnects() async throws {
        let fixture = ClientFixture()
        StubURLProtocol.enqueue(
            [.init(chunks: [sseEvent(servedConfigSet)], endsStream: true)],
            for: fixture.streamURL
        )
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(makeTransport: transportRetrying(after: 0.01))
        defer { client.close() }

        await client.initialize(context: contextWithAnInvalidContextKind)

        #expect(await waitUntil { fixture.streamRequests.count == 2 })
        await settle(0.3)
        #expect(reportedInvalidContextSubmissionCount(fixture) == 1)
    }

    @Test func countsNoFurtherInvalidSubmissionWhenPolling() async throws {
        let fixture = ClientFixture()
        fixture.servePolling(
            servedConfigSet,
            servedConfigSet,
            servedConfigSet,
            servedConfigSet,
            servedConfigSet
        )
        let client = try fixture.makeClient(mode: .polling, makeTransport: transportPolling(every: 0.05))
        defer { client.close() }

        await client.initialize(context: contextWithAnInvalidContextKind)

        #expect(await waitUntil { fixture.pollRequests.count >= 3 })
        await settle(0.2)
        #expect(reportedInvalidContextSubmissionCount(fixture) == 1)
    }

    @Test func reportsAContextOverASizeLimitByItsReasonAloneEvenWithoutEvaluations() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        let id = String(repeating: "i", count: 257)

        await client.initialize(context: ConfigDirectorContext(
            id: id,
            name: "Kitchen tablet",
            traits: ["model": "t-1000"]
        ))

        #expect(await waitUntil { reportedInvalidContextSubmissionCount(fixture) == 1 })
        let report = try #require(fixture.telemetryReports()
            .first { !$0.aggregatedEvents.invalidContext.isEmpty })
        let submission = try #require(report.aggregatedEvents.invalidContext.first)
        #expect(report.aggregatedEvents.invalidContext.count == 1)
        #expect(report.aggregatedEvents.evaluatedConfig.isEmpty)
        #expect(submission.count == 1)
        #expect(submission.event.reason == "identifier-too-long")
        #expect(submission.event.kindSample == nil)
        #expect(submission.startTime <= submission.endTime)

        let bodies = fixture.telemetryRequests.compactMap(\.body)
        #expect(bodies.contains { $0.contains(id) } == false)
        #expect(bodies.contains { $0.contains("Kitchen tablet") } == false)
        #expect(bodies.contains { $0.contains("t-1000") } == false)
    }

    @Test func reportsTwoContextsOverTheIDLimitAsOneSubmissionWhenTheFirstConnectionFails() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.rejectStream(statusCode: 401)
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(telemetryFlushInterval: 60)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "42"))

        await client.updateContext(ConfigDirectorContext(id: String(repeating: "i", count: 257)))
        await client.updateContext(ConfigDirectorContext(id: String(repeating: "j", count: 257)))

        #expect(await waitUntil { reportedInvalidContextSubmissionCount(fixture) == 2 })
        let submissions = fixture.telemetryReports().flatMap(\.aggregatedEvents.invalidContext)
        #expect(submissions.map(\.event.reason) == ["identifier-too-long"])
        #expect(submissions.map(\.count) == [2])
    }
}
