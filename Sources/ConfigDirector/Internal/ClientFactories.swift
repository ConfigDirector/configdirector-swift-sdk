import Foundation

/// What the client builds for itself when nothing is injected: the production telemetry collector
/// and the transport for the configured connection mode.
extension ConfigDirectorClient {
    static func makeTelemetry(
        reporter: any EventReporter,
        logger: any ConfigDirectorLogger,
        options: TelemetryOptions
    ) -> any TelemetryClient {
        TelemetryEventCollector(reporter: reporter, logger: logger, options: options)
    }

    static func makeTransport(
        mode: ConnectionMode,
        options: TransportOptions,
        onConfigSet: @escaping ConfigSetHandler
    ) -> any Transport {
        switch mode {
        case .streaming:
            StreamingTransport(options: options, onConfigSet: onConfigSet)
        case .polling:
            PollingTransport(options: options, onConfigSet: onConfigSet)
        }
    }
}
