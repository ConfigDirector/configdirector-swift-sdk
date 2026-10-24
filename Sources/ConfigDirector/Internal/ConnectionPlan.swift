import Foundation

enum LiveConnectionMode: Sendable {
    case streaming
    case polling
}

struct LiveConnection: Sendable {
    var mode: LiveConnectionMode
    var clientSDKKey: String
    var baseURL: URL
    var pollingInterval: TimeInterval
}

enum ConnectionPlan {
    case connect(LiveConnection)
    case stayOffline(configs: [String: ConfigState])

    static func decide(
        clientSDKKey: String,
        connection: ConnectionOptions,
        logger: any ConfigDirectorLogger
    ) throws(ConfigDirectorError) -> ConnectionPlan {
        switch connection.mode {
        case .streaming:
            try planToConnect(.streaming, clientSDKKey: clientSDKKey, connection: connection, logger: logger)
        case .polling:
            try planToConnect(.polling, clientSDKKey: clientSDKKey, connection: connection, logger: logger)
        case .offline:
            try .stayOffline(configs: ServedValue.configStates(connection.values ?? [:]))
        }
    }

    var networkControl: NetworkControl {
        switch self {
        case .connect: .pausesAndResumesTheTransport
        case .stayOffline: .doesNothing
        }
    }

    private static func planToConnect(
        _ mode: LiveConnectionMode,
        clientSDKKey: String,
        connection: ConnectionOptions,
        logger: any ConfigDirectorLogger
    ) throws(ConfigDirectorError) -> ConnectionPlan {
        guard !clientSDKKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigDirectorError.missingClientSDKKey
        }
        guard connection.values == nil else {
            throw ConfigDirectorError.valuesRequireOfflineMode
        }

        let baseURL = try absoluteBaseURL(connection.baseURL)
        if baseURL.scheme?.lowercased() != "https" {
            logger.warn("""
            The base URL '\(baseURL)' is not HTTPS. The client SDK key, every context you send, and \
            every config value served back travel in plain text.
            """)
        }

        return .connect(LiveConnection(
            mode: mode,
            clientSDKKey: clientSDKKey,
            baseURL: baseURL,
            pollingInterval: pollingIntervalRaisedToMinimum(
                connection.pollingInterval,
                mode: mode,
                logger: logger
            )
        ))
    }

    private static func absoluteBaseURL(_ baseURL: URL?) throws(ConfigDirectorError) -> URL {
        guard let baseURL else { return Constants.clientBaseURL }
        guard baseURL.scheme != nil, baseURL.host != nil else {
            throw ConfigDirectorError.invalidBaseURL(baseURL)
        }
        return baseURL
    }

    private static func pollingIntervalRaisedToMinimum(
        _ configuredInterval: TimeInterval,
        mode: LiveConnectionMode,
        logger: any ConfigDirectorLogger
    ) -> TimeInterval {
        guard mode == .polling else { return configuredInterval }
        let minimumInterval = ConnectionOptions.minimumPollingInterval
        if configuredInterval >= minimumInterval {
            return configuredInterval
        }

        logger.warn("""
        pollingInterval of \(configuredInterval) seconds is below the minimum of \(minimumInterval) \
        seconds. Using \(minimumInterval) seconds.
        """)
        return minimumInterval
    }
}

enum NetworkControl {
    case pausesAndResumesTheTransport
    case doesNothing
}
