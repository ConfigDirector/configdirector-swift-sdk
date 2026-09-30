@testable import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientPollingIntervalTests {
    private final class TransportOptionsRecorder: Sendable {
        private let recorded = Locked<[TransportOptions]>([])

        var pollingIntervals: [TimeInterval] {
            recorded.withLock { $0.map(\.pollingInterval) }
        }

        var makeTransport: TransportFactory {
            { [recorded] _, options, _ in
                recorded.withLock { $0.append(options) }
                return IdleTransport()
            }
        }
    }

    private struct IdleTransport: Transport {
        func connect(
            context _: ConfigDirectorContext,
            timeout _: TimeInterval,
            reason _: ConnectReason
        ) async throws {}
        func disconnect() {}
        func close() {}
    }

    private let fixture = ClientFixture()
    private let logger = RecordingLogger()
    private let transports = TransportOptionsRecorder()

    private func makeClient(
        mode: ConnectionMode,
        pollingInterval: TimeInterval? = nil
    ) throws -> ConfigDirectorClient {
        try fixture.makeClient(
            mode: mode,
            timeout: 0.01,
            pollingInterval: pollingInterval,
            logger: logger,
            makeTransport: transports.makeTransport
        )
    }

    private var minimumWarnings: [String] {
        logger.warnings.filter { $0.contains("below the minimum") }
    }

    @Test func pollsOnTheDefaultIntervalWhenNoneIsConfigured() throws {
        let client = try makeClient(mode: .polling)
        defer { client.close() }

        #expect(transports.pollingIntervals == [60])
        #expect(minimumWarnings.isEmpty)
    }

    @Test func raisesAnIntervalBelowTheMinimumAndWarnsOnce() async throws {
        let client = try makeClient(mode: .polling, pollingInterval: 10)
        defer { client.close() }

        #expect(transports.pollingIntervals == [30])
        #expect(minimumWarnings.count == 1)
        #expect(minimumWarnings.first?.contains("pollingInterval") == true)

        await client.updateContext(ConfigDirectorContext(id: "user-456"))

        #expect(transports.pollingIntervals == [30])
        #expect(minimumWarnings.count == 1)
    }

    @Test func acceptsExactlyTheMinimumUnchanged() throws {
        let client = try makeClient(mode: .polling, pollingInterval: 30)
        defer { client.close() }

        #expect(transports.pollingIntervals == [30])
        #expect(minimumWarnings.isEmpty)
    }

    @Test func raisesZeroToTheMinimum() throws {
        let client = try makeClient(mode: .polling, pollingInterval: 0)
        defer { client.close() }

        #expect(transports.pollingIntervals == [30])
        #expect(minimumWarnings.count == 1)
    }

    @Test func raisesANegativeIntervalToTheMinimum() throws {
        let client = try makeClient(mode: .polling, pollingInterval: -5)
        defer { client.close() }

        #expect(transports.pollingIntervals == [30])
        #expect(minimumWarnings.count == 1)
    }

    @Test func streamingModeLeavesALowIntervalAloneAndStaysQuiet() throws {
        let client = try makeClient(mode: .streaming, pollingInterval: 10)
        defer { client.close() }

        #expect(transports.pollingIntervals == [10])
        #expect(minimumWarnings.isEmpty)
    }

    @Test func theOptionsKeepTheConfiguredInterval() {
        let options = ConnectionOptions(mode: .polling, pollingInterval: 10)

        #expect(options.pollingInterval == 10)
    }
}
