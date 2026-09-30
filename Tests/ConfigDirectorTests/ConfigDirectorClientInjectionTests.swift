@testable import ConfigDirector
import Foundation
import Testing

/// Exercises the seams the in-memory connection relies on: the transport learns what prompted each
/// attempt, and telemetry is built through the factory the client is given.
struct ConfigDirectorClientInjectionTests {
    private final class ReasonRecorder: Sendable {
        let reasons = Locked<[ConnectReason]>([])

        var makeTransport: TransportFactory {
            { [reasons] mode, options, onConfigSet in
                RecordingTransport(
                    inner: ConfigDirectorClient.makeTransport(
                        mode: mode,
                        options: options,
                        onConfigSet: onConfigSet
                    ),
                    reasons: reasons
                )
            }
        }
    }

    private struct RecordingTransport: Transport {
        let inner: any Transport
        let reasons: Locked<[ConnectReason]>

        func connect(
            context: ConfigDirectorContext,
            timeout: TimeInterval,
            reason: ConnectReason
        ) async throws {
            reasons.withLock { $0.append(reason) }
            try await inner.connect(context: context, timeout: timeout, reason: reason)
        }

        func disconnect() {
            inner.disconnect()
        }

        func close() {
            inner.close()
        }
    }

    private final class RecordingTelemetry: TelemetryClient {
        let events = Locked<[EvaluatedConfigEvent]>([])

        func evaluatedConfig(_ event: EvaluatedConfigEvent) {
            events.withLock { $0.append(event) }
        }

        func updateContext(_: ConfigDirectorContext?) {}

        func flush() async {}

        func close() {}
    }

    @Test func tellsTheTransportWhatPromptedEachAttempt() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        fixture.serveStream(servedConfigSet)
        let recorder = ReasonRecorder()
        let client = try fixture.makeClient(makeTransport: recorder.makeTransport)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-a"))
        await client.updateContext(ConfigDirectorContext(id: "user-b"))
        client.pauseNetwork()
        await client.resumeNetwork()

        #expect(recorder.reasons.withLock { $0 } == [.initialization, .contextUpdate, .networkResume])
    }

    @Test func buildsTelemetryThroughTheFactoryItIsGiven() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let telemetry = RecordingTelemetry()
        let client = try fixture.makeClient(makeTelemetry: { _, _, _ in telemetry })
        defer { client.close() }
        await client.initialize()

        _ = client.value(for: "dark-mode", default: false)

        #expect(telemetry.events.withLock { $0.map(\.key) } == ["dark-mode"])
        await settle()
        #expect(fixture.telemetryRequests.isEmpty)
    }
}
