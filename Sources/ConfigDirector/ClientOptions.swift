import Foundation

/// How the client connects to the ConfigDirector server.
public enum ConnectionMode: Sendable {
    /// Keeps a connection open and receives updates as soon as config state changes in the
    /// ConfigDirector dashboard.
    case streaming

    /// Fetches config state during initialization and then every ``ConnectionOptions/pollingInterval``
    /// seconds: 60 by default, and never less than 30. A value below the minimum is raised to the
    /// minimum and a warning is logged.
    case polling

    /// Never connects to the ConfigDirector server. The client serves the values given in
    /// ``ConnectionOptions/values`` to every context, or every config's in-code default value when
    /// none are given, is ready as soon as ``ConfigDirectorClient/initialize(context:)`` is called,
    /// and sends nothing, so the app is invisible to the ConfigDirector dashboard.
    case offline
}

/// How the client connects to the ConfigDirector server.
public struct ConnectionOptions: Sendable {
    /// The ``pollingInterval`` used when none is given: 60 seconds.
    public static let defaultPollingInterval: TimeInterval = 60

    static let minimumPollingInterval: TimeInterval = 30

    /// The connection mode to use.
    public var mode: ConnectionMode

    /// The values to serve in ``ConnectionMode/offline`` mode, one per config key, to every context.
    /// Leaving it `nil` in offline mode serves every config's in-code default value. It can be given
    /// only in offline mode: creating a client with values in another mode throws
    /// ``ConfigDirectorError/valuesRequireOfflineMode``.
    public var values: [String: ServedValue]?

    /// How often, in seconds, to re-fetch config state when ``mode`` is ``ConnectionMode/polling``.
    /// Defaults to ``defaultPollingInterval``, 60 seconds; the minimum is 30 seconds. A value below
    /// the minimum is raised to the minimum and a warning is logged. It has no effect when streaming.
    public var pollingInterval: TimeInterval

    /// How long to wait for initialization and context updates.
    ///
    /// The operation may still succeed after it times out, as long as no unrecoverable errors are
    /// encountered: streaming keeps reconnecting, and polling tries again on ``pollingInterval``.
    public var timeout: TimeInterval

    /// The base URL of the ConfigDirector SDK server. Set this only when routing through a proxy.
    public var baseURL: URL?

    /// Whether to pause the connection while the app is in the background and resume it when the app
    /// returns to the foreground.
    ///
    /// Mobile operating systems terminate background connections on their own, so this is enabled by
    /// default. Set it to `false` to manage the connection yourself with
    /// ``ConfigDirectorClient/pauseNetwork()`` and ``ConfigDirectorClient/resumeNetwork()``.
    ///
    /// It has no effect on macOS, where an app keeps running, and keeps its connections, once it
    /// leaves the foreground.
    public var pausesWhileBackgrounded: Bool

    public init(
        mode: ConnectionMode = .streaming,
        values: [String: ServedValue]? = nil,
        pollingInterval: TimeInterval = Self.defaultPollingInterval,
        timeout: TimeInterval = 3,
        baseURL: URL? = nil,
        pausesWhileBackgrounded: Bool = true
    ) {
        self.mode = mode
        self.values = values
        self.pollingInterval = pollingInterval
        self.timeout = timeout
        self.baseURL = baseURL
        self.pausesWhileBackgrounded = pausesWhileBackgrounded
    }
}

/// Configuration for a ``ConfigDirectorClient``.
public struct ConfigDirectorClientOptions: Sendable {
    /// Metadata about your application that stays constant for the lifetime of the connection.
    public var metadata: ConfigDirectorMetaContext?

    /// Connection options.
    public var connection: ConnectionOptions

    /// Whether, and where, the client keeps the last values it received on the device and serves
    /// them on the next launch of the same context until live values arrive. On by default, in the
    /// app's `UserDefaults`; ignored in ``ConnectionMode/offline`` mode.
    public var caching: CachingOptions

    /// Where the SDK writes its logs. Defaults to a ``ConsoleLogger`` at the
    /// ``ConfigDirectorLogLevel/warn`` level.
    ///
    /// ```swift
    /// ConfigDirectorClientOptions(logger: ConsoleLogger(level: .debug))
    /// ```
    public var logger: any ConfigDirectorLogger

    public init(
        metadata: ConfigDirectorMetaContext? = nil,
        connection: ConnectionOptions = ConnectionOptions(),
        caching: CachingOptions = CachingOptions(),
        logger: any ConfigDirectorLogger = ConsoleLogger()
    ) {
        self.metadata = metadata
        self.connection = connection
        self.caching = caching
        self.logger = logger
    }
}
