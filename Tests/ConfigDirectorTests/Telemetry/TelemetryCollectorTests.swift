@testable import ConfigDirector
import Foundation
import Testing

/// Records what it was asked to report, and whether any of that work landed on the main thread.
private final class RecordingReporter: EventReporter, Sendable {
    private struct State {
        var reports: [EventReport] = []
        var sawMainThread = false
        var outcome = ReportOutcome.succeeded
    }

    private let state = Locked(State())

    var reports: [EventReport] {
        state.withLock { $0.reports }
    }

    var sawMainThread: Bool {
        state.withLock { $0.sawMainThread }
    }

    func failFatally() {
        state.withLock { $0.outcome = .failedFatally }
    }

    func report(_ report: EventReport) async -> ReportOutcome {
        // Compaction and aggregation happen inside the real reporter, so this is the thread they run
        // on there too.
        _ = report.snapshot.events.map { $0.compacted() }

        return state.withLock { state in
            state.reports.append(report)
            state.sawMainThread = state.sawMainThread || Thread.isMainThread
            return state.outcome
        }
    }

    func close() {}
}

struct TelemetryCollectorTests {
    private func makeEvent(key: String = "dark-mode") -> EvaluatedConfigEvent {
        EvaluatedConfigEvent(
            key: key,
            defaultValue: TelemetryValue(value: "false"),
            requestedType: "Bool",
            evaluatedValue: TelemetryValue(value: String(repeating: "a", count: 600)),
            usedDefault: false,
            evaluationReason: .foundMatch
        )
    }

    private func makeCollector(
        _ reporter: RecordingReporter,
        flushInterval: TimeInterval = 0.05
    ) -> TelemetryEventCollector {
        TelemetryEventCollector(
            reporter: reporter,
            logger: ConsoleLogger(level: .off),
            options: TelemetryOptions(flushInterval: flushInterval, initialFlushDelay: flushInterval)
        )
    }

    @MainActor
    @Test func neitherCollectsNorReportsOnTheMainThread() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter)
        defer { collector.close() }

        for _ in 0 ..< 50 {
            collector.evaluatedConfig(makeEvent())
        }

        #expect(await waitUntil { !reporter.reports.isEmpty })
        #expect(reporter.sawMainThread == false, "telemetry was aggregated and reported on the main thread")
    }

    @Test func reportsOnTheFlushInterval() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter)
        defer { collector.close() }

        collector.evaluatedConfig(makeEvent(key: "one"))
        #expect(await waitUntil { reporter.reports.count == 1 })

        collector.evaluatedConfig(makeEvent(key: "two"))
        #expect(await waitUntil { reporter.reports.count == 2 })
        #expect(reporter.reports.map { $0.snapshot.events.map(\.key) } == [["one"], ["two"]])
    }

    @Test func reportsNothingWhenNothingWasCollected() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter)
        defer { collector.close() }

        await settle(0.3)

        #expect(reporter.reports.isEmpty)
    }

    @Test func stopsCollectingAfterAFatalReport() async {
        let reporter = RecordingReporter()
        reporter.failFatally()
        let collector = makeCollector(reporter)
        defer { collector.close() }

        collector.evaluatedConfig(makeEvent())
        #expect(await waitUntil { reporter.reports.count == 1 })

        collector.evaluatedConfig(makeEvent())
        await settle(0.3)

        #expect(reporter.reports.count == 1)
    }

    @Test func reportsWhatIsLeftOnClose() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter, flushInterval: 60)

        collector.evaluatedConfig(makeEvent())
        collector.close()

        #expect(await waitUntil { reporter.reports.count == 1 })
        #expect(reporter.reports.first?.snapshot.events.count == 1)
    }

    @Test func collectsNothingOnceClosed() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter, flushInterval: 0.05)
        collector.close()

        collector.evaluatedConfig(makeEvent())
        await settle(0.3)

        #expect(reporter.reports.isEmpty)
        #expect(collector.pendingEventCount == 0, "events piled up with nothing left to report them")
    }

    @Test func collectsNothingAfterAFatalReport() async {
        let reporter = RecordingReporter()
        reporter.failFatally()
        let collector = makeCollector(reporter)
        defer { collector.close() }

        collector.evaluatedConfig(makeEvent())
        #expect(await waitUntil { reporter.reports.count == 1 })

        collector.evaluatedConfig(makeEvent())
        await settle(0.2)

        #expect(collector.pendingEventCount == 0, "events piled up with nothing left to report them")
    }

    @Test func keepsAtMost20ContextKindSamplesAndCountsTheRestWithoutASample() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter, flushInterval: 60)
        defer { collector.close() }

        for index in 0 ..< 23 {
            collector.recordInvalidContextSubmission(contextKindSample: "Tenant\(index)")
        }
        collector.recordInvalidContextSubmission(contextKindSample: "Tenant0")
        await collector.flush()

        let submissions = reporter.reports.flatMap(\.invalidContextSubmissions)
        #expect(submissions.count == 21)
        #expect(Set(submissions.map(\.event)) == [
            .sampled(contextKindSample: "Tenant0"), .sampled(contextKindSample: "Tenant1"),
            .sampled(contextKindSample: "Tenant2"), .sampled(contextKindSample: "Tenant3"),
            .sampled(contextKindSample: "Tenant4"), .sampled(contextKindSample: "Tenant5"),
            .sampled(contextKindSample: "Tenant6"), .sampled(contextKindSample: "Tenant7"),
            .sampled(contextKindSample: "Tenant8"), .sampled(contextKindSample: "Tenant9"),
            .sampled(contextKindSample: "Tenant10"), .sampled(contextKindSample: "Tenant11"),
            .sampled(contextKindSample: "Tenant12"), .sampled(contextKindSample: "Tenant13"),
            .sampled(contextKindSample: "Tenant14"), .sampled(contextKindSample: "Tenant15"),
            .sampled(contextKindSample: "Tenant16"), .sampled(contextKindSample: "Tenant17"),
            .sampled(contextKindSample: "Tenant18"), .sampled(contextKindSample: "Tenant19"),
            .beyondContextKindSampleLimit,
        ])
        #expect(submissions.first { $0.event == .sampled(contextKindSample: "Tenant0") }?.count == 2)
        #expect(submissions.first { $0.event == .beyondContextKindSampleLimit }?.count == 3)
    }

    @Test func startsSamplingContextKindsAfreshAfterEachReport() async {
        let reporter = RecordingReporter()
        let collector = makeCollector(reporter, flushInterval: 60)
        defer { collector.close() }
        for index in 0 ..< 21 {
            collector.recordInvalidContextSubmission(contextKindSample: "Tenant\(index)")
        }
        await collector.flush()

        collector.recordInvalidContextSubmission(contextKindSample: "Tenant20")
        await collector.flush()

        let secondReport = reporter.reports.last?.invalidContextSubmissions
        #expect(reporter.reports.count == 2)
        #expect(secondReport?.count == 1)
        #expect(secondReport?.first?.event == .sampled(contextKindSample: "Tenant20"))
        #expect(secondReport?.first?.count == 1)
    }

    @Test func collectsNoInvalidContextSubmissionsAfterAFatalReport() async {
        let reporter = RecordingReporter()
        reporter.failFatally()
        let collector = makeCollector(reporter)
        defer { collector.close() }
        collector.evaluatedConfig(makeEvent())
        #expect(await waitUntil { reporter.reports.count == 1 })

        collector.recordInvalidContextSubmission(contextKindSample: "Tenant")
        await collector.flush()

        #expect(reporter.reports.count == 1)
    }
}
