import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientEvaluateTests {
    @Test func returnsAServedValueWithItsReasonAndValueID() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let (value, evaluation) = client.evaluate("dark-mode", default: false)

        #expect(value == true)
        #expect(evaluation.key == "dark-mode")
        #expect(evaluation.value.as(Bool.self) == true)
        #expect(evaluation.valueID == "on")
        #expect(evaluation.isDefaultValue == false)
        #expect(evaluation.reason == .foundMatch)
        #expect(evaluation.context == ConfigDirectorContext(id: "user-123"))
    }

    @Test func returnsTheInCodeDefaultValueForAConfigThatDoesNotExist() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize()

        let (value, evaluation) = client.evaluate("missing", default: "fallback")

        #expect(value == "fallback")
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.valueID == nil)
        #expect(evaluation.reason == .configStateMissing)
    }

    @Test func returnsTheInCodeDefaultValueBeforeInitialization() throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }

        let (value, evaluation) = client.evaluate("dark-mode", default: false)

        #expect(value == false)
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.reason == .clientNotReady)
    }

    @Test func returnsTheInCodeDefaultValueForAValueOfAnotherType() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize()

        let (value, evaluation) = client.evaluate("max-retries", default: false)

        #expect(value == false)
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.reason == .typeMismatch)
    }

    @Test func returnsAValueKeptOnTheDeviceWithTheCachedReason() async throws {
        let provider = RecordingCachingProvider()
        try await keepValuesOnDevice(in: provider)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let (value, evaluation) = client.evaluate("dark-mode", default: false)

        #expect(value == true)
        #expect(evaluation.isDefaultValue == false)
        #expect(evaluation.valueID == "on")
        #expect(evaluation.reason == .cached)
    }

    @Test func returnsAJSONConfigDecodedWithItsReason() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([
            ServedConfig("theme", "json", #"{"primaryColor":"blue","cornerRadius":8}"#, valueID: "theme-1"),
        ]))
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize()
        let fallback = Theme(primaryColor: "red", cornerRadius: 0)

        let (value, evaluation) = client.evaluate("theme", as: Theme.self, default: fallback)

        #expect(value == Theme(primaryColor: "blue", cornerRadius: 8))
        #expect(evaluation.value.as(Theme.self) == Theme(primaryColor: "blue", cornerRadius: 8))
        #expect(evaluation.isDefaultValue == false)
        #expect(evaluation.valueID == "theme-1")
        #expect(evaluation.reason == .foundMatch)
    }

    @Test func publishesTheEvaluationItReturnsOnce() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        let evaluations = StreamReader(client.evaluations)

        let (_, evaluation) = client.evaluate("dark-mode", default: false)

        let published = await evaluations.next()
        #expect(published == evaluation)
        let another = await evaluations.next(timeout: 0.3)
        #expect(another == nil, "the read published more than one evaluation")
    }

    @Test func reportsTheReadToTelemetryOnce() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize()

        _ = client.evaluate("dark-mode", default: false)

        _ = await waitUntil {
            fixture.telemetryReports().contains { !$0.evaluations(of: "dark-mode").isEmpty }
        }
        await settle()
        let reported = fixture.telemetryReports().flatMap { $0.evaluations(of: "dark-mode") }
        #expect(reported.map(\.count) == [1])
        let event = try #require(reported.first?.event)
        #expect(event.requestedType == "Bool")
        #expect(event.evaluationReason == "found-match")
        #expect(event.evaluatedValueId == "on")
    }
}
