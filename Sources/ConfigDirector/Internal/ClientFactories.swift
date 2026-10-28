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

struct ClientDependencies {
    let session: URLSession
    let lifecycle: any AppLifecycleObserver
    let telemetryOptions: TelemetryOptions
    let makeTelemetry: TelemetryFactory
    let makeTransport: TransportFactory
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
        dependencies: ClientDependencies
    ) {
        switch plan {
        case let .connect(live):
            self = Self.connecting(
                live,
                options: options,
                identity: identity,
                clientSession: makeClientSession(),
                dependencies: dependencies
            )
        case let .stayOffline(configs):
            self = Self.offline(configs: configs, options: options)
        }
    }

    private init(
        telemetry: any TelemetryClient,
        store: ConfigStore,
        transport: any Transport,
        lifecycle: any AppLifecycleObserver
    ) {
        self.telemetry = telemetry
        self.store = store
        self.transport = transport
        self.lifecycle = lifecycle
    }

    private static func connecting(
        _ live: LiveConnection,
        options: ConfigDirectorClientOptions,
        identity: SDKIdentity,
        clientSession: ClientSession,
        dependencies: ClientDependencies
    ) -> ClientComponents {
        let metaContext = AppInfo.metaContext(metadata: options.metadata, identity: identity)
        let telemetry = dependencies.makeTelemetry(
            HTTPEventReporter(
                clientSDKKey: live.clientSDKKey,
                instanceID: clientSession.instanceID,
                baseURL: live.baseURL,
                metaContext: metaContext,
                logger: options.logger,
                session: dependencies.session
            ),
            options.logger,
            dependencies.telemetryOptions
        )
        let store = ConfigStore(
            logger: options.logger,
            telemetry: telemetry,
            caching: CachingPlan.decide(
                options.caching,
                clientSDKKey: live.clientSDKKey,
                instanceID: clientSession.instanceID,
                logger: options.logger
            )
        )
        let transport = dependencies.makeTransport(
            live.mode,
            TransportOptions(
                clientSDKKey: live.clientSDKKey,
                baseURL: live.baseURL,
                metaContext: metaContext,
                clientSession: clientSession,
                logger: options.logger,
                pollingInterval: live.pollingInterval,
                session: dependencies.session
            ),
            { [store] configSet in store.applyReceivedConfigSet(configSet) }
        )
        return ClientComponents(
            telemetry: telemetry,
            store: store,
            transport: transport,
            lifecycle: dependencies.lifecycle
        )
    }

    private static func offline(
        configs: [String: ConfigState],
        options: ConfigDirectorClientOptions
    ) -> ClientComponents {
        let telemetry = DiscardingTelemetry()
        let store = ConfigStore(logger: options.logger, telemetry: telemetry, caching: .keepNothing)
        let transport = OfflineTransport(configs: configs) { [store] configSet in
            store.applyReceivedConfigSet(configSet)
        }
        return ClientComponents(
            telemetry: telemetry,
            store: store,
            transport: transport,
            lifecycle: NoLifecycleObserver()
        )
    }
}
