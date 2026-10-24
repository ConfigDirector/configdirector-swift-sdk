import Foundation

/// The ConfigDirector SDK client.
///
/// Applications should create a single instance and initialize it during startup.
///
/// ```swift
/// let client = try ConfigDirectorClient(clientSDKKey: "YOUR-SDK-KEY")
/// await client.initialize(context: ConfigDirectorContext(id: "user-123"))
///
/// let darkMode = client.value(for: "dark-mode", default: false)
/// ```
///
/// After initialization, call ``updateContext(_:)`` to re-evaluate configs against a new context,
/// and ``close()`` when the client is no longer needed.
public final class ConfigDirectorClient: Sendable {
    private struct ConnectionState {
        var isInitializing = false
        var isClosed = false
        var hasConnected = false
        var isPausedWhileBackgrounded = false
    }

    private let logger: any ConfigDirectorLogger
    private let timeout: TimeInterval
    private let pausesWhileBackgrounded: Bool
    private let store: ConfigStore
    private let transport: any Transport
    private let telemetry: any TelemetryClient
    private let lifecycle: any AppLifecycleObserver
    private let networkControl: NetworkControl
    private let connectionState = Locked(ConnectionState())
    private let connectQueue = SerialAsyncQueue()

    /// Creates a client for `clientSDKKey`, the client SDK key from the ConfigDirector dashboard.
    ///
    /// The client cannot serve config values until ``initialize(context:)`` completes. Until then,
    /// every config evaluates to its default value.
    ///
    /// - Throws: ``ConfigDirectorError/missingClientSDKKey`` when the key is blank outside
    ///   ``ConnectionMode/offline`` mode, ``ConfigDirectorError/invalidBaseURL(_:)`` when
    ///   ``ConnectionOptions/baseURL`` is not absolute, ``ConfigDirectorError/valuesRequireOfflineMode``
    ///   when ``ConnectionOptions/values`` is given outside offline mode, and
    ///   ``ConfigDirectorError/invalidOfflineValue(key:)`` when one of those values cannot be served.
    public convenience init(
        clientSDKKey: String,
        options: ConfigDirectorClientOptions = ConfigDirectorClientOptions()
    ) throws(ConfigDirectorError) {
        try self.init(clientSDKKey: clientSDKKey, options: options, identity: .swiftClientSDK)
    }

    /// Creates a client in ``ConnectionMode/offline`` mode, which needs no client SDK key.
    ///
    /// - Throws: ``ConfigDirectorError/missingClientSDKKey`` when ``ConnectionOptions/mode`` is not
    ///   ``ConnectionMode/offline``, and ``ConfigDirectorError/invalidOfflineValue(key:)`` when a
    ///   value in ``ConnectionOptions/values`` cannot be served.
    public convenience init(options: ConfigDirectorClientOptions) throws(ConfigDirectorError) {
        try self.init(clientSDKKey: "", options: options, identity: .swiftClientSDK)
    }

    /// Creates a client in ``ConnectionMode/offline`` mode on behalf of a wrapper SDK identified by
    /// `identity`. Otherwise identical to ``init(options:)``; an offline client sends nothing, so the
    /// identity is never reported.
    @_spi(ConfigDirectorWrapper)
    public convenience init(
        options: ConfigDirectorClientOptions,
        identity: SDKIdentity
    ) throws(ConfigDirectorError) {
        try self.init(clientSDKKey: "", options: options, identity: identity)
    }

    /// Creates a client that reports `identity` to the server instead of this SDK's own name and
    /// version. Otherwise identical to ``init(clientSDKKey:options:)``.
    @_spi(ConfigDirectorWrapper)
    public convenience init(
        clientSDKKey: String,
        options: ConfigDirectorClientOptions = ConfigDirectorClientOptions(),
        identity: SDKIdentity
    ) throws(ConfigDirectorError) {
        try self.init(
            clientSDKKey: clientSDKKey,
            options: options,
            identity: identity,
            makeClientSession: {
                ClientSession.current(storage: UserDefaultsInstanceIDStorage(), logger: options.logger)
            },
            session: URLSession(configuration: .default),
            lifecycle: NotificationCenterLifecycleObserver(),
            telemetryOptions: TelemetryOptions(),
            makeTelemetry: Self.makeTelemetry,
            makeTransport: Self.makeTransport
        )
    }

    init(
        clientSDKKey: String,
        options: ConfigDirectorClientOptions,
        identity: SDKIdentity,
        makeClientSession: () -> ClientSession,
        session: URLSession,
        lifecycle: any AppLifecycleObserver,
        telemetryOptions: TelemetryOptions,
        makeTelemetry: @escaping TelemetryFactory,
        makeTransport: @escaping TransportFactory
    ) throws(ConfigDirectorError) {
        let plan = try ConnectionPlan.decide(
            clientSDKKey: clientSDKKey,
            connection: options.connection,
            logger: options.logger
        )
        let components = ClientComponents(
            plan: plan,
            options: options,
            identity: identity,
            makeClientSession: makeClientSession,
            dependencies: ClientDependencies(
                session: session,
                lifecycle: lifecycle,
                telemetryOptions: telemetryOptions,
                makeTelemetry: makeTelemetry,
                makeTransport: makeTransport
            )
        )

        logger = options.logger
        timeout = options.connection.timeout
        pausesWhileBackgrounded = options.connection.pausesWhileBackgrounded
        networkControl = plan.networkControl
        store = components.store
        telemetry = components.telemetry
        transport = components.transport
        self.lifecycle = components.lifecycle

        self.lifecycle.start { [weak self] phase in self?.handle(phase) }
    }

    /// The context the client is currently evaluating configs against, or `nil` when there is none,
    /// as after a context with an invalid ``ConfigDirectorContext/kind`` was ignored.
    ///
    /// This does not change the moment ``updateContext(_:)`` is called: configs are evaluated against
    /// the previous context until the underlying connection succeeds or times out.
    public var context: ConfigDirectorContext? {
        store.context
    }

    /// Whether the client is ready, meaning the connection to the server succeeded and config state
    /// was received, or, in ``ConnectionMode/offline`` mode, the values were loaded. It stays `false`
    /// while the client serves the values kept on the device from an earlier launch; see
    /// ``ConfigDirectorClientOptions/caching``.
    public var isReady: Bool {
        store.isReady
    }

    /// Whether the client is trying to get its very first config state from the server.
    ///
    /// It is `false` on creation, becomes `true` when ``initialize(context:)`` is called on a
    /// client that has never received config state, stays `true` through timeouts and retries, and
    /// becomes `false` when the first config state arrives, when an unrecoverable connection error
    /// stops the retries, or on ``close()``. ``updateContext(_:)`` and ``resumeNetwork()`` never
    /// set it, and it stays `true` while the client serves the values kept on the device from an
    /// earlier launch.
    public var isInitializing: Bool {
        connectionState.withLock { $0.isInitializing } && !store.hasReceivedConfigSet
    }

    /// Every event the client publishes, from the moment this stream is created.
    ///
    /// Each access returns an independent stream; the client publishes to all of them.
    ///
    /// ```swift
    /// for await event in client.events {
    ///     if case let .configsUpdated(update) = event { print(update.keys, update.removedKeys) }
    /// }
    /// ```
    public var events: AsyncStream<ClientEvent> {
        store.events.subscribe()
    }

    /// Every config evaluation the client makes, from the moment this stream is created.
    ///
    /// One is published for every read, whether by ``value(for:default:)`` or by a
    /// ``values(for:default:)`` stream, so reading a config from a SwiftUI `body` publishes one per
    /// frame. Each access returns an independent stream.
    ///
    /// Do not update view state straight from this stream: the state change re-renders the view,
    /// which reads the config again, which publishes another evaluation.
    ///
    /// ```swift
    /// for await evaluation in client.evaluations where evaluation.isDefaultValue {
    ///     logger.notice("'\(evaluation.key)' fell back: \(evaluation.reason.rawValue)")
    /// }
    /// ```
    public var evaluations: AsyncStream<ConfigEvaluation> {
        store.evaluations.subscribe()
    }

    /// Connects to ConfigDirector to retrieve config evaluations. Until initialization succeeds,
    /// every config returns the default value passed to ``value(for:default:)`` or
    /// ``values(for:default:)``, or, on a launch after one that received config state for the same
    /// context, the value kept on the device; see ``ConfigDirectorClientOptions/caching``.
    ///
    /// If the connection fails or is interrupted by a transient error the client keeps trying to
    /// connect. If it fails with a persistent error, such as an invalid SDK key, the client stops
    /// trying and logs an error.
    ///
    /// A context with an invalid ``ConfigDirectorContext/kind`` is ignored: the client logs an error
    /// and connects as if no context was given.
    ///
    /// In ``ConnectionMode/offline`` mode nothing is connected: the client is ready, serving
    /// ``ConnectionOptions/values``, before this returns.
    ///
    /// - Parameter context: The current user's context, used to evaluate targeting rules.
    public func initialize(context: ConfigDirectorContext? = nil) async {
        connectionState.withLock { $0.isInitializing = true }
        await connect(context: context, reason: .initialization)
    }

    /// Updates the user's context and re-evaluates every config against it.
    ///
    /// A context with an invalid ``ConfigDirectorContext/kind`` is ignored: the client logs an error
    /// and stops using the previous context, re-evaluating every config as if no context was given.
    ///
    /// In ``ConnectionMode/offline`` mode the new context takes effect at once and no value changes.
    public func updateContext(_ context: ConfigDirectorContext) async {
        await connect(context: context, reason: .contextUpdate)
    }

    /// Evaluates `key` against the current context and targeting rules.
    ///
    /// Returns `defaultValue` when config state is unavailable — for instance when called before
    /// initialization completes, or when the served value cannot be represented as `Value`.
    public func value<Value: ConfigValue>(for key: String, default defaultValue: Value) -> Value {
        store.value(for: key, default: defaultValue)
    }

    /// Evaluates a JSON config, decoding it into `type`.
    ///
    /// Returns `defaultValue` when config state is unavailable, when the config is not a JSON config,
    /// or when its document cannot be decoded into `type`.
    ///
    /// ```swift
    /// let theme = client.value(for: "theme", as: Theme.self, default: .fallback)
    /// ```
    public func value<Value: Decodable & Sendable>(
        for key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> Value {
        store.value(for: key, as: type, default: defaultValue)
    }

    /// Watches `key` for changes, which can come from an update in the ConfigDirector dashboard or
    /// from a call to ``updateContext(_:)``.
    ///
    /// The stream yields the config's current value immediately and then every time the evaluated
    /// value changes. Consecutive identical values are not re-emitted. When a full update no longer
    /// carries `key`, the stream yields `defaultValue`, as ``value(for:default:)`` would now return
    /// it. Cancelling the consuming task stops watching.
    ///
    /// ```swift
    /// .task {
    ///     for await darkMode in client.values(for: "dark-mode", default: false) {
    ///         self.darkMode = darkMode
    ///     }
    /// }
    /// ```
    public func values<Value: ConfigValue>(
        for key: String,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        store.values(for: key, default: defaultValue)
    }

    /// Watches a JSON config for changes, decoding each value into `type`.
    public func values<Value: Decodable & Sendable & Equatable>(
        for key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        store.values(for: key, as: type, default: defaultValue)
    }

    /// Pauses the network connection without discarding config state, event streams, or watch
    /// streams. Call ``resumeNetwork()`` to re-establish the connection. It does nothing in
    /// ``ConnectionMode/offline`` mode.
    public func pauseNetwork() {
        switch networkControl {
        case .pausesAndResumesTheTransport:
            logger.debug("pauseNetwork() called, pausing the transport connection")
            transport.disconnect()
            store.markNotReady()
        case .doesNothing:
            break
        }
    }

    /// Resumes a connection paused by ``pauseNetwork()``, reusing the current ``context``. It does
    /// nothing in ``ConnectionMode/offline`` mode.
    public func resumeNetwork() async {
        switch networkControl {
        case .pausesAndResumesTheTransport:
            await connect(context: store.context, reason: .networkResume)
        case .doesNothing:
            break
        }
    }

    /// Closes the connection, every watch stream, and every event stream.
    ///
    /// The client closes itself when it is released, so calling this is only necessary to shut it
    /// down while a reference to it is still held. The client cannot be used afterwards.
    public func close() {
        let wasClosed = connectionState.exchange(\.isClosed, with: true)
        guard !wasClosed else { return }

        logger.debug("close() called, closing the connection to the server and removing all observers")
        connectionState.withLock { $0.isInitializing = false }
        lifecycle.stop()
        telemetry.close()
        store.close()
        transport.close()
    }

    deinit {
        close()
    }

    private func connect(context: ConfigDirectorContext?, reason: ConnectReason) async {
        await connectQueue.enqueue { [self] in await connectNow(context: context, reason: reason) }
    }

    private func connectNow(context suppliedContext: ConfigDirectorContext?, reason: ConnectReason) async {
        let context = store.beginConnect(reason: reason, suppliedContext: suppliedContext)
        let startedAt = ProcessInfo.processInfo.systemUptime

        do {
            try await transport.connect(
                context: context ?? ConfigDirectorContext(),
                timeout: timeout,
                reason: reason
            )
        } catch {
            connectionState.withLock { $0.isInitializing = false }
            store.abandonConnect()
            logger.error("An error occurred during \(reason)", error: error)
            return
        }

        connectionState.withLock { $0.hasConnected = true }
        store.applyPendingContext()

        let remaining = timeout - (ProcessInfo.processInfo.systemUptime - startedAt)
        if remaining > 0 {
            await store.waitUntilReady(timeout: remaining)
        }

        guard store.isReady else {
            logger.warn("""
            Timed out waiting for \(reason) after \(timeout)s. The client will keep retrying as long \
            as no fatal errors are detected. Configs return their default value until the connection \
            succeeds.
            """)
            return
        }
    }

    private func handle(_ phase: AppLifecyclePhase) {
        switch phase {
        case .background:
            Task { [telemetry] in await telemetry.flush() }

            let shouldPause = connectionState.withLock { state -> Bool in
                guard !state.isClosed, state.hasConnected, pausesWhileBackgrounded else { return false }
                state.isPausedWhileBackgrounded = true
                return true
            }

            guard shouldPause else { return }
            logger.info("The app entered the background, pausing the connection to the server")
            pauseNetwork()

        case .foreground:
            let shouldResume = connectionState.withLock { state -> Bool in
                guard !state.isClosed, state.isPausedWhileBackgrounded else { return false }
                state.isPausedWhileBackgrounded = false
                return true
            }

            guard shouldResume else { return }
            logger.info("The app returned to the foreground, resuming the connection to the server")
            Task { await resumeNetwork() }
        }
    }
}
