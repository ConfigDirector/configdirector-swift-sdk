import Foundation

/// An error raised by the ConfigDirector SDK.
public enum ConfigDirectorError: Error, Sendable, Equatable {
    /// The client was created without a usable client SDK key.
    case missingClientSDKKey

    /// The base URL given in ``ConnectionOptions/baseURL`` is not an absolute URL.
    case invalidBaseURL(URL)

    /// ``ConnectionOptions/values`` was given while ``ConnectionOptions/mode`` is not
    /// ``ConnectionMode/offline``.
    case valuesRequireOfflineMode

    /// A value in ``ConnectionOptions/values`` cannot be served: its key is blank, or it holds a
    /// number that is not finite.
    case invalidOfflineValue(key: String)

    /// The connection to the ConfigDirector server failed, carrying the HTTP status code when one
    /// was received.
    case connectionFailed(message: String, statusCode: Int?)
}

extension ConfigDirectorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingClientSDKKey:
            "No client SDK key was provided. The client cannot be created without a valid client SDK key."
        case let .invalidBaseURL(url):
            "Invalid base URL '\(url)'. The base URL must be absolute."
        case .valuesRequireOfflineMode:
            "Values were given outside offline mode. Set the connection mode to offline to serve them."
        case let .invalidOfflineValue(key):
            "Invalid value for '\(key)'. A key must not be blank, and a number must be finite."
        case let .connectionFailed(message, statusCode):
            statusCode.map { "\(message) (HTTP \($0))" } ?? message
        }
    }
}
