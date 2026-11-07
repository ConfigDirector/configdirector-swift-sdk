import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientVariationTests {
    private func makeReadyClient(
        _ fixture: ClientFixture,
        serving configs: [ServedConfig]
    ) async throws -> ConfigDirectorClient {
        fixture.serveStream(configSetJSON(configs))
        let client = try fixture.makeClient()
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        return client
    }

    @Test func evaluateReturnsTheVariationThePayloadEntryCarries() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig(
                "checkout-cta-copy",
                "string",
                "Try it free",
                valueID: "value-treatment",
                variation: ServedVariation(id: "variation-treatment", name: "treatment"),
                ruleID: "rule-1",
                shareID: "share-treatment"
            ),
        ])
        defer { client.close() }

        let (value, evaluation) = client.evaluate("checkout-cta-copy", default: "in-code default")

        #expect(value == "Try it free")
        #expect(evaluation.variation == Variation(id: "variation-treatment", name: "treatment"))
        #expect(evaluation.valueID == "value-treatment")
        #expect(evaluation.reason == .foundMatch)
    }

    @Test func evaluateReturnsNoVariationForAConfigWithoutVariations() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig("dark-mode", "boolean", "true", valueID: "on"),
        ])
        defer { client.close() }

        let (value, evaluation) = client.evaluate("dark-mode", default: false)

        #expect(value == true)
        #expect(evaluation.variation == nil)
        #expect(evaluation.valueID == "on")
    }

    @Test func anUnnamedVariationHasNoName() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig("copy", "string", "A", variation: ServedVariation(id: "variation-a", name: nil)),
        ])
        defer { client.close() }

        let (_, evaluation) = client.evaluate("copy", default: "in-code default")

        #expect(evaluation.variation == Variation(id: "variation-a"))
    }

    @Test func aVariationWithAnEmptyNameHasNoName() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig("copy", "string", "A", variation: ServedVariation(id: "variation-a", name: "")),
        ])
        defer { client.close() }

        let (_, evaluation) = client.evaluate("copy", default: "in-code default")

        #expect(evaluation.variation == Variation(id: "variation-a"))
    }

    @Test func aVariationWithoutAnIDIsNoVariationAndTheValueIsStillServed() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(#"""
        {"environmentId":"env","projectId":"proj","kind":"full","configs":{"copy":{"id":"copy","key":"copy",\#
        "type":"string","value":"A","valueId":"value-a","variation":{"name":"treatment"}}}}
        """#)
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let (value, evaluation) = client.evaluate("copy", default: "in-code default")

        #expect(value == "A")
        #expect(evaluation.reason == .foundMatch)
        #expect(evaluation.variation == nil)
    }

    @Test func evaluateReturnsNoVariationWhenTheInCodeDefaultValueIsReturned() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig(
                "max-items",
                "integer",
                "20",
                variation: ServedVariation(id: "variation-a", name: "control")
            ),
        ])
        defer { client.close() }

        let (value, evaluation) = client.evaluate("max-items", default: false)

        #expect(value == false)
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.variation == nil)
    }

    @Test func aJSONConfigReadAsADecodableTypeCarriesItsVariation() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig(
                "theme",
                "json",
                #"{"primaryColor":"blue","cornerRadius":8}"#,
                variation: ServedVariation(id: "variation-a", name: "control")
            ),
        ])
        defer { client.close() }

        let (_, evaluation) = client.evaluate(
            "theme",
            as: Theme.self,
            default: Theme(primaryColor: "red", cornerRadius: 0)
        )

        #expect(evaluation.variation == Variation(id: "variation-a", name: "control"))
    }

    @Test func theEvaluationsStreamCarriesTheVariation() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig(
                "copy",
                "string",
                "A",
                variation: ServedVariation(id: "variation-a", name: "control")
            ),
        ])
        defer { client.close() }
        let evaluations = StreamReader(client.evaluations)

        _ = client.value(for: "copy", default: "in-code default")

        let published = try #require(await evaluations.next())
        #expect(published.variation == Variation(id: "variation-a", name: "control"))
    }

    @Test func aDeltaReplacesTheVariation() async throws {
        let fixture = ClientFixture()
        let client = try await makeReadyClient(fixture, serving: [
            ServedConfig(
                "copy",
                "string",
                "A",
                variation: ServedVariation(id: "variation-a", name: "control")
            ),
        ])
        defer { client.close() }
        let events = StreamReader(client.events)

        fixture.pushToStream(deltaConfigSet([
            ServedConfig(
                "copy",
                "string",
                "B",
                variation: ServedVariation(id: "variation-b", name: "treatment")
            ),
        ]))
        #expect(await events.next(where: isConfigsUpdated) != nil)

        let (_, evaluation) = client.evaluate("copy", default: "in-code default")
        #expect(evaluation.variation == Variation(id: "variation-b", name: "treatment"))
    }

    @Test func theDeviceKeepsTheVariationRuleAndShareAtTheSameFormatVersion() async throws {
        let provider = RecordingCachingProvider()

        try await keepValuesOnDevice(in: provider, configSet: configSetJSON([
            ServedConfig(
                "copy",
                "string",
                "A",
                variation: ServedVariation(id: "variation-a", name: "control"),
                ruleID: "rule-1",
                shareID: "share-a"
            ),
        ]))

        let entry = try #require(try provider.storedEntry())
        #expect(entry.formatVersion == 2)
        let config = try #require(entry.configs["copy"])
        #expect(config.variation?.id == "variation-a")
        #expect(config.variation?.name == "control")
        #expect(config.ruleId == "rule-1")
        #expect(config.shareId == "share-a")
    }

    @Test func aValueKeptOnTheDeviceCarriesItsVariation() async throws {
        let provider = RecordingCachingProvider()
        try await keepValuesOnDevice(in: provider, configSet: configSetJSON([
            ServedConfig(
                "copy",
                "string",
                "A",
                variation: ServedVariation(id: "variation-a", name: "control")
            ),
        ]))
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let (_, evaluation) = client.evaluate("copy", default: "in-code default")

        #expect(evaluation.reason == .cached)
        #expect(evaluation.variation == Variation(id: "variation-a", name: "control"))
    }

    @Test func aValueKeptOnTheDeviceReportsItsRuleShareAndVariation() async throws {
        let provider = RecordingCachingProvider()
        try await keepValuesOnDevice(in: provider, configSet: configSetJSON([
            ServedConfig(
                "copy",
                "string",
                "A",
                variation: ServedVariation(id: "variation-a", name: "control"),
                ruleID: "rule-1",
                shareID: "share-a"
            ),
        ]))
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(for: "copy", default: "in-code default")

        #expect(await waitUntil {
            fixture.telemetryReports().contains { !$0.evaluations(of: "copy").isEmpty }
        })
        let reported = try #require(
            fixture.telemetryReports().flatMap { $0.evaluations(of: "copy") }.first?.event
        )
        #expect(reported.evaluationReason == "cached")
        #expect(reported.contextId == "user-123")
        #expect(reported.ruleId == "rule-1")
        #expect(reported.shareId == "share-a")
        #expect(reported.variationId == "variation-a")
    }

    @Test func aValueKeptByAnEarlierVersionHasNoVariationAndIsStillServed() async throws {
        let provider = RecordingCachingProvider(stored: """
        {"formatVersion":2,\
        "clientSdkKeyDigest":"cc677751b8441e282621773a9be4622b11cd5bcffce54caabdd19f60e07d556c",\
        "contextTag":{"contextKind":"user","contextId":"user-123"},"environmentId":"env","projectId":"proj",\
        "configs":{"copy":{"id":"copy","key":"copy","type":"string","value":"A","valueId":"value-a"}},\
        "receivedAt":1761000000000}
        """)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let (value, evaluation) = client.evaluate("copy", default: "in-code default")

        #expect(value == "A")
        #expect(evaluation.reason == .cached)
        #expect(evaluation.valueID == "value-a")
        #expect(evaluation.variation == nil)
    }

    @Test func anOfflineValueHasNoVariation() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: ["copy": "A"])
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        let (value, evaluation) = client.evaluate("copy", default: "in-code default")

        #expect(value == "A")
        #expect(evaluation.variation == nil)
    }

    @Test func theReasonForASkippedRolloutHasTheNameEverySDKReportsItBy() {
        #expect(EvaluationReason.rolloutSkippedNoIdentifier.rawValue == "rollout-skipped-no-identifier")
    }
}
