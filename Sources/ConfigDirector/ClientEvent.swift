import Foundation

/// What prompted the client to (re)connect.
public enum ConnectReason: Sendable {
    /// The client connected for the first time, from ``ConfigDirectorClient/initialize(context:)``.
    case initialization

    /// The client reconnected to re-evaluate configs against a new context.
    case contextUpdate

    /// The client reconnected after the network was resumed.
    case networkResume
}

/// Something the client did, published on ``ConfigDirectorClient/events``.
public enum ClientEvent: Sendable {
    /// The client became ready after connecting.
    case ready(ConnectReason)

    /// Config state was received from the server, carrying the keys it contained and the keys a
    /// full update no longer contained.
    case configsUpdated(ConfigsUpdate)

    /// A new context has taken effect.
    case contextUpdated(ConfigDirectorContext?)
}

/// What a ``ClientEvent/configsUpdated(_:)`` event carries.
public struct ConfigsUpdate: Sendable {
    /// The keys of the configs the update carried. On a delta update these are only the configs
    /// that changed.
    public let keys: [String]

    /// The keys of the configs a full update no longer carried, so the client stopped serving them.
    /// Empty when nothing was removed, and always empty on a delta update.
    public let removedKeys: [String]

    /// Creates an update carrying `keys` and, for a full update, the `removedKeys` it dropped.
    public init(keys: [String], removedKeys: [String] = []) {
        self.keys = keys
        self.removedKeys = removedKeys
    }
}

extension ConnectReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .initialization: "initialization"
        case .contextUpdate: "context update"
        case .networkResume: "network resume"
        }
    }
}
