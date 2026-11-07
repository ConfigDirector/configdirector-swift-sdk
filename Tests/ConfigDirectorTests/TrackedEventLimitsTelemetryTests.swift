import ConfigDirector
import Foundation
import Testing

struct TrackedEventLimitsTelemetryTests {
    private struct BatchFixture {
        let fixture = ClientFixture()
        let logger = RecordingLogger()

        func makeClient() throws -> ConfigDirectorClient {
            try fixture.makeClient(telemetryFlushInterval: 60, logger: logger)
        }

        func sendBatch(expectingReports reportCount: Int = 1) async {
            fixture.enterBackground()
            _ = await waitUntil { fixture.telemetryReports().count == reportCount }
        }
    }

    @Test func keepsTheFirst1000EventsOfABatchAndWarnsOnce() async throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }

        for index in 0 ..< 1002 {
            client.track("event-\(index)")
        }
        await batch.sendBatch()

        let names = batch.fixture.trackedEvents().map(\.name)
        #expect(names.count == 1000)
        #expect(names.first == "event-0")
        #expect(names.last == "event-999")
        #expect(batch.logger.warnings.count == 1)
    }

    @Test func keeps1000EventsOfABatchWithoutAWarning() async throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }

        for index in 0 ..< 1000 {
            client.track("event-\(index)")
        }
        await batch.sendBatch()

        #expect(batch.fixture.trackedEvents().count == 1000)
        #expect(batch.logger.warnings.isEmpty)
    }

    @Test func holdsAnotherFullBatchAfterTheFirstIsSent() async throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }

        for index in 0 ..< 1001 {
            client.track("event-\(index)")
        }
        await batch.sendBatch()

        for index in 0 ..< 1001 {
            client.track("event-\(index)")
        }
        await batch.sendBatch(expectingReports: 2)

        #expect(batch.fixture.trackedEvents().count == 2000)
        #expect(batch.logger.warnings.count == 2)
    }

    @Test func dropsAnEventWithAnEmptyNameAndWarns() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track("")
        client.track("kept")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["kept"])
        #expect(logger.warnings.count == 1)
    }

    @Test func keepsAnEventWhoseNameHas150Characters() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let name = String(repeating: "n", count: 150)

        client.track(name)

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == [name])
        #expect(logger.warnings.isEmpty)
    }

    @Test func dropsAnEventWhoseNameHas151CharactersAndWarns() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track(String(repeating: "n", count: 151))
        client.track("kept")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["kept"])
        #expect(logger.warnings.count == 1)
    }

    @Test func countsANameAsTheServerDoesRatherThanByWhatReadsAsOneCharacter() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let familyOfFiveScalars = "👨‍👩‍👧"

        client.track(String(repeating: familyOfFiveScalars, count: 30) + "n")
        client.track("kept")

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["kept"])
        #expect(logger.warnings.count == 1)
    }

    @Test func keepsANameOf150CharactersThatTakeMoreThan150Bytes() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let name = String(repeating: "é", count: 150)

        client.track(name)

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == [name])
        #expect(logger.warnings.isEmpty)
    }

    @Test func leavesOutAValueThatIsNotANumberAndKeepsTheEvent() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track("checkout-completed", options: TrackOptions(value: .double(.nan)))

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["checkout-completed"])
        #expect(fixture.trackedEvents().first?.value == nil)
        #expect(logger.warnings.count == 1)
    }

    @Test func leavesOutAnInfiniteValueAndKeepsTheEvent() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track("checkout-completed", options: TrackOptions(value: .double(.infinity)))

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["checkout-completed"])
        #expect(fixture.trackedEvents().first?.value == nil)
        #expect(logger.warnings.count == 1)
    }

    @Test func leavesOutADecimalThatIsNotANumberAndKeepsTheEvent() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track("checkout-completed", options: TrackOptions(value: .decimal(.nan)))

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["checkout-completed"])
        #expect(fixture.trackedEvents().first?.value == nil)
        #expect(logger.warnings.count == 1)
    }

    @Test func logsOneWarningForTwoNamesOutsideTheLimitInABatch() throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }

        client.track("")
        client.track(String(repeating: "n", count: 151))

        #expect(batch.logger.warnings.count == 1)
    }

    @Test func logsOneWarningForTwoValuesLeftOutInABatch() throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }

        client.track("first", options: TrackOptions(value: .double(.nan)))
        client.track("second", options: TrackOptions(value: .decimal(.nan)))

        #expect(batch.logger.warnings.count == 1)
    }

    @Test func logsOneWarningForTwoDetailsLeftOutInABatch() throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }
        let oversizedDetails: TrackedEventDetails = ["note": .string(String(repeating: "a", count: 1014))]

        client.track("first", options: TrackOptions(details: oversizedDetails))
        client.track("second", options: TrackOptions(details: oversizedDetails))

        #expect(batch.logger.warnings.count == 1)
    }

    @Test func logsASeparateWarningForEachCauseInABatch() throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }
        let oversizedDetails: TrackedEventDetails = ["note": .string(String(repeating: "a", count: 1014))]

        client.track("")
        client.track("kept", options: TrackOptions(value: .double(.nan)))
        client.track("kept", options: TrackOptions(details: oversizedDetails))

        #expect(batch.logger.warnings.count == 3)
    }

    @Test func warnsAgainAboutTheSameCauseInTheNextBatch() async throws {
        let batch = BatchFixture()
        let client = try batch.makeClient()
        defer { client.close() }

        client.track("")
        client.track("")
        client.track("kept")
        await batch.sendBatch()
        #expect(batch.logger.warnings.count == 1)

        client.track("")

        #expect(batch.logger.warnings.count == 2)
    }

    @Test func logsNothingOnceTelemetryIsClosed() throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)

        client.close()
        client.track("")

        #expect(logger.warnings.isEmpty)
    }
}
