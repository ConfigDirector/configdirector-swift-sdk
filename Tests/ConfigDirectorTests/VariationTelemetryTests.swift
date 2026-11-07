import ConfigDirector
import Foundation
import Testing

struct VariationTelemetryTests {
    private func firstReport(
        _ fixture: ClientFixture,
        containing key: String
    ) async -> TelemetryReport.AggregatedEvaluation? {
        _ = await waitUntil { fixture.telemetryReports().contains { !$0.evaluations(of: key).isEmpty } }
        return fixture.telemetryReports().lazy.compactMap { $0.evaluations(of: key).first }.first
    }

    @Test func reportsTheRuleShareAndVariationThatServedTheValue() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([
            ServedConfig(
                "checkout-cta-copy",
                "string",
                "Try it free",
                valueID: "value-treatment",
                variation: ServedVariation(id: "variation-treatment", name: "treatment"),
                ruleID: "rule-1",
                shareID: "share-treatment"
            ),
        ]))
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(for: "checkout-cta-copy", default: "in-code default")

        let evaluation = try #require(await firstReport(fixture, containing: "checkout-cta-copy"))
        #expect(evaluation.event.ruleId == "rule-1")
        #expect(evaluation.event.shareId == "share-treatment")
        #expect(evaluation.event.variationId == "variation-treatment")
        #expect(evaluation.event.evaluationReason == "found-match")
    }

    @Test func reportsOnlyTheVariationForAValueNoRolloutServed() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([
            ServedConfig(
                "checkout-cta-copy",
                "string",
                "Try it free",
                valueID: "value-treatment",
                variation: ServedVariation(id: "variation-treatment", name: "treatment")
            ),
        ]))
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(for: "checkout-cta-copy", default: "in-code default")

        let evaluation = try #require(await firstReport(fixture, containing: "checkout-cta-copy"))
        #expect(evaluation.event.ruleId == nil)
        #expect(evaluation.event.shareId == nil)
        #expect(evaluation.event.variationId == "variation-treatment")
    }

    @Test func reportsNoRuleShareOrVariationForAConfigWithoutVariations() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([ServedConfig("dark-mode", "boolean", "true", valueID: "on")]))
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(for: "dark-mode", default: false)

        let evaluation = try #require(await firstReport(fixture, containing: "dark-mode"))
        #expect(evaluation.event.ruleId == nil)
        #expect(evaluation.event.shareId == nil)
        #expect(evaluation.event.variationId == nil)
    }

    @Test func reportsNoRuleShareOrVariationWhenTheInCodeDefaultValueIsReturned() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([
            ServedConfig(
                "checkout-cta-copy",
                "string",
                "Try it free",
                valueID: "value-treatment",
                variation: ServedVariation(id: "variation-treatment", name: "treatment"),
                ruleID: "rule-1",
                shareID: "share-treatment"
            ),
        ]))
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(for: "checkout-cta-copy", default: 0)

        let evaluation = try #require(await firstReport(fixture, containing: "checkout-cta-copy"))
        #expect(evaluation.event.usedDefault)
        #expect(evaluation.event.evaluationReason == "invalid-number")
        #expect(evaluation.event.ruleId == nil)
        #expect(evaluation.event.shareId == nil)
        #expect(evaluation.event.variationId == nil)
    }

    @Test func reportsNoRuleShareOrVariationWhenAJSONDocumentDoesNotDecode() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([
            ServedConfig(
                "checkout-layout",
                "json",
                "[1, 2, 3]",
                valueID: "value-treatment",
                variation: ServedVariation(id: "variation-treatment", name: "treatment"),
                ruleID: "rule-1",
                shareID: "share-treatment"
            ),
        ]))
        let client = try fixture.makeClient()
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        _ = client.value(
            for: "checkout-layout",
            as: Theme.self,
            default: Theme(primaryColor: "red", cornerRadius: 0)
        )

        let evaluation = try #require(await firstReport(fixture, containing: "checkout-layout"))
        #expect(evaluation.event.usedDefault)
        #expect(evaluation.event.evaluationReason == "type-mismatch")
        #expect(evaluation.event.ruleId == nil)
        #expect(evaluation.event.shareId == nil)
        #expect(evaluation.event.variationId == nil)
    }

    @Test func countsEvaluationsOfAnotherRuleSeparately() async throws {
        let counted = try await countedAcrossAnUpdate(
            from: ServedConfig("copy", "string", "A", ruleID: "rule-1"),
            to: ServedConfig("copy", "string", "A", ruleID: "rule-2")
        )

        #expect(counted.sorted { $0.count > $1.count }.map(\.event.ruleId) == ["rule-1", "rule-2"])
        #expect(counted.map(\.count).sorted() == [1, 2])
    }

    @Test func countsEvaluationsOfAnotherShareSeparately() async throws {
        let counted = try await countedAcrossAnUpdate(
            from: ServedConfig("copy", "string", "A", ruleID: "rule-1", shareID: "share-a"),
            to: ServedConfig("copy", "string", "A", ruleID: "rule-1", shareID: "share-b")
        )

        #expect(counted.sorted { $0.count > $1.count }.map(\.event.shareId) == ["share-a", "share-b"])
        #expect(counted.map(\.count).sorted() == [1, 2])
    }

    @Test func countsEvaluationsOfAnotherVariationSeparately() async throws {
        let counted = try await countedAcrossAnUpdate(
            from: ServedConfig("copy", "string", "A", variation: ServedVariation(id: "variation-a")),
            to: ServedConfig("copy", "string", "A", variation: ServedVariation(id: "variation-b"))
        )

        #expect(
            counted.sorted { $0.count > $1.count }.map(\.event.variationId) == ["variation-a", "variation-b"]
        )
        #expect(counted.map(\.count).sorted() == [1, 2])
    }

    private func countedAcrossAnUpdate(
        from first: ServedConfig,
        to second: ServedConfig
    ) async throws -> [TelemetryReport.AggregatedEvaluation] {
        let fixture = ClientFixture()
        fixture.serveStream(configSetJSON([first]))
        let client = try fixture.makeClient(telemetryFlushInterval: 60)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        let events = StreamReader(client.events)
        _ = client.value(for: first.key, default: "in-code default")
        _ = client.value(for: first.key, default: "in-code default")

        fixture.pushToStream(deltaConfigSet([second]))
        #expect(await events.next(where: isConfigsUpdated) != nil)
        _ = client.value(for: first.key, default: "in-code default")
        fixture.enterBackground()

        _ = await waitUntil { fixture.telemetryReports().contains { !$0.evaluations(of: first.key).isEmpty } }
        return fixture.telemetryReports().flatMap { $0.evaluations(of: first.key) }
    }
}
