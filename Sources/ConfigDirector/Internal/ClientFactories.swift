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
        mode: LiveConnectionMode,
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

struct ClientComponents {
    let telemetry: any TelemetryClient
    let store: ConfigStore
    let transport: any Transport
    let lifecycle: any AppLifecycleObserver

    init(
        plan: ConnectionPlan,
        options: ConfigDirectorClientOptions,
        identity: SDKIdentity,
        makeClientSession: () -> ClientSession,
        session: URLSession,
        lifecycle: any AppLifecycleObserver,
        telemetryOptions: TelemetryOptions,
        makeTelemetry: TelemetryFactory,
        makeTransport: TransportFactory
    ) {
        switch plan {
        case let .connect(mode, clientSDKKey, baseURL, pollingInterval):
            let metaContext = AppInfo.metaContext(metadata: options.metadata, identity: identity)
            let telemetry = makeTelemetry(
                HTTPEventReporter(
                    clientSDKKey: clientSDKKey,
                    baseURL: baseURL,
                    metaContext: metaContext,
                    logger: options.logger,
                    session: session
                ),
                options.logger,
                telemetryOptions
            )
            let store = ConfigStore(logger: options.logger, telemetry: telemetry)
            self.telemetry = telemetry
            self.store = store
            transport = makeTransport(
                mode,
                TransportOptions(
                    clientSDKKey: clientSDKKey,
                    baseURL: baseURL,
                    metaContext: metaContext,
                    clientSession: makeClientSession(),
                    logger: options.logger,
                    pollingInterval: pollingInterval,
                    session: session
                ),
                { [store] configSet in store.handleConfigSet(configSet) }
            )
            self.lifecycle = lifecycle

        case let .stayOffline(configs):
            let telemetry = DiscardingTelemetry()
            let store = ConfigStore(logger: options.logger, telemetry: telemetry)
            self.telemetry = telemetry
            self.store = store
            transport = OfflineTransport(configs: configs) { [store] configSet in
                store.handleConfigSet(configSet)
            }
            self.lifecycle = NoLifecycleObserver()
        }
    }
}
