import ConfigDirector
import Foundation
import Testing

struct TrackedEventDetailsTelemetryTests {
    private func body(
        ofEvent eventName: String,
        tracked options: TrackOptions,
        logger: RecordingLogger = RecordingLogger()
    ) async throws -> String {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }

        client.track(eventName, options: options)

        #expect(await waitUntil { fixture.trackedEvents().map(\.name) == [eventName] })
        return try #require(fixture.telemetryBodies().first { $0.contains(eventName) })
    }

    @Test func sendsAWholeNumberValueAsAWholeNumber() async throws {
        let body = try await body(ofEvent: "seats-added", tracked: TrackOptions(value: 3))

        #expect(body.contains(#""value":3"#))
    }

    @Test func sendsAFractionalValueAsWritten() async throws {
        let body = try await body(ofEvent: "checkout-completed", tracked: TrackOptions(value: 0.1))

        #expect(body.contains(#""value":0.1"#))
    }

    @Test func sendsADecimalValueWithEveryDigit() async throws {
        let digits = "1234567890.12345678901234567"
        let total = try #require(Decimal(string: digits))

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(value: .decimal(total))
        )

        #expect(body.contains(#""value":\#(digits)"#))
    }

    @Test func sendsNoValueOrDetailsWhenTheEventHasNone() async throws {
        let body = try await body(ofEvent: "app-opened", tracked: TrackOptions())

        #expect(!body.contains(#""value""#))
        #expect(!body.contains(#""details""#))
    }

    @Test func sendsEmptyDetailsGivenExplicitly() async throws {
        let body = try await body(ofEvent: "app-opened", tracked: TrackOptions(details: [:]))

        #expect(body.contains(#""details":{}"#))
    }

    @Test func sendsNestedDetails() async throws {
        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["cart": ["items": [1, 2.5, "gift", true, nil]]])
        )

        #expect(body.contains(#""details":{"cart":{"items":[1,2.5,"gift",true,null]}}"#))
    }

    @Test func sendsADateInDetailsAsISO8601Text() async throws {
        let body = try await body(
            ofEvent: "trial-started",
            tracked: TrackOptions(details: ["at": .date(Date(timeIntervalSince1970: 1_800_000_000.25))])
        )

        #expect(body.contains(#""details":{"at":"2027-01-15T08:00:00.250Z"}"#))
    }

    @Test func sendsADoubleInDetailsThatIsNotFiniteAsNull() async throws {
        let logger = RecordingLogger()

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["ratio": .double(.infinity)]),
            logger: logger
        )

        #expect(body.contains(#""details":{"ratio":null}"#))
        #expect(logger.warnings.isEmpty)
    }

    @Test func keepsDetailsOf20TopLevelKeys() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let details = TrackedEventDetails(uniqueKeysWithValues: (1 ... 20).map { ("key-\($0)", true) })

        client.track("checkout-completed", options: TrackOptions(details: details))

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().first?.details?.count == 20)
        #expect(logger.warnings.isEmpty)
    }

    @Test func leavesOutDetailsOf21TopLevelKeysAndKeepsTheEvent() async throws {
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(logger: logger)
        defer { client.close() }
        let details = TrackedEventDetails(uniqueKeysWithValues: (1 ... 21).map { ("key-\($0)", true) })

        client.track("checkout-completed", options: TrackOptions(details: details))

        #expect(await waitUntil { !fixture.trackedEvents().isEmpty })
        #expect(fixture.trackedEvents().map(\.name) == ["checkout-completed"])
        #expect(fixture.trackedEvents().first?.details == nil)
        #expect(logger.warnings.count == 1)
    }

    @Test func sendsDetailsOfExactly1024BytesAsThoseBytes() async throws {
        let logger = RecordingLogger()
        let note = String(repeating: "a", count: 1013)

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["note": .string(note)]),
            logger: logger
        )

        #expect(body.contains(#""details":{"note":"\#(note)"}"#))
        #expect(logger.warnings.isEmpty)
    }

    @Test func leavesOutDetailsOf1025BytesAndKeepsTheEvent() async throws {
        let logger = RecordingLogger()
        let note = String(repeating: "a", count: 1014)

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["note": .string(note)]),
            logger: logger
        )

        #expect(!body.contains(#""details""#))
        #expect(logger.warnings.count == 1)
    }

    @Test func sendsSlashesInDetailsAtTheLimitWithoutEscapingThem() async throws {
        let logger = RecordingLogger()
        let url = String(repeating: "/", count: 1014)

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["url": .string(url)]),
            logger: logger
        )

        #expect(body.contains(#""details":{"url":"\#(url)"}"#))
        #expect(logger.warnings.isEmpty)
    }

    @Test func sendsNonASCIITextInDetailsAtTheLimitWithoutEscapingIt() async throws {
        let logger = RecordingLogger()
        let note = String(repeating: "é", count: 506) + "a"

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["note": .string(note)]),
            logger: logger
        )

        #expect(body.contains(#""details":{"note":"\#(note)"}"#))
        #expect(logger.warnings.isEmpty)
    }

    @Test func measuresDetailsInBytesRatherThanCharacters() async throws {
        let logger = RecordingLogger()
        let note = String(repeating: "é", count: 507)

        let body = try await body(
            ofEvent: "checkout-completed",
            tracked: TrackOptions(details: ["note": .string(note)]),
            logger: logger
        )

        #expect(!body.contains(#""details""#))
        #expect(logger.warnings.count == 1)
    }
}
