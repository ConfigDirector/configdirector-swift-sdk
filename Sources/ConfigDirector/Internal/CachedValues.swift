import Foundation

enum CachingPlan: Sendable {
    case keepValues(CachedValuesStore)
    case keepNothing

    static func decide(
        _ caching: CachingOptions,
        clientSDKKey: String,
        instanceID: String,
        logger: any ConfigDirectorLogger
    ) -> CachingPlan {
        guard caching.enabled else {
            logger.debug("No values are kept on the device: caching is turned off")
            return .keepNothing
        }

        return .keepValues(CachedValuesStore(
            provider: caching.provider ?? UserDefaultsCachingProvider(clientSDKKey: clientSDKKey),
            clientSDKKey: clientSDKKey,
            instanceID: instanceID,
            logger: logger
        ))
    }
}

enum ContextTag: Equatable, Sendable {
    case identified(contextKind: String, contextID: String)
    case anonymous(contextKind: String, instanceID: String)

    private static let defaultContextKind = "user"

    init(context: ConfigDirectorContext?, instanceID: String) {
        let contextKind = context?.kind ?? Self.defaultContextKind
        if let contextID = context?.id {
            self = .identified(contextKind: contextKind, contextID: contextID)
        } else {
            self = .anonymous(contextKind: contextKind, instanceID: instanceID)
        }
    }
}

extension ContextTag: Codable {
    private enum CodingKeys: String, CodingKey {
        case contextKind
        case contextID = "contextId"
        case anonymousInstanceID = "anonymousInstanceId"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let contextKind = try container.decode(String.self, forKey: .contextKind)
        if let contextID = try container.decodeIfPresent(String.self, forKey: .contextID) {
            self = .identified(contextKind: contextKind, contextID: contextID)
        } else {
            self = try .anonymous(
                contextKind: contextKind,
                instanceID: container.decode(String.self, forKey: .anonymousInstanceID)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .identified(contextKind, contextID):
            try container.encode(contextKind, forKey: .contextKind)
            try container.encode(contextID, forKey: .contextID)
        case let .anonymous(contextKind, instanceID):
            try container.encode(contextKind, forKey: .contextKind)
            try container.encode(instanceID, forKey: .anonymousInstanceID)
        }
    }
}

struct CachedValues: Sendable, Equatable, Codable {
    var contextTag: ContextTag
    var environmentID: String
    var projectID: String
    var configs: [String: ConfigState]
    var receivedAt: Int64

    private enum CodingKeys: String, CodingKey {
        case contextTag, configs, receivedAt
        case environmentID = "environmentId"
        case projectID = "projectId"
    }
}

enum CachedValuesRead: Sendable {
    case stored(CachedValues)
    case nothingStored
    case notAnEntry
    case storageFailed
}

enum CachedValuesAdoption: Equatable {
    case adopt
    case liveValuesAlreadyArrived
    case contextMismatch
    case clientClosed

    static func decide(
        _ cachedValues: CachedValues,
        launchContextTag: ContextTag,
        hasReceivedLiveValues: Bool,
        isClosed: Bool
    ) -> CachedValuesAdoption {
        if isClosed {
            return .clientClosed
        }
        if hasReceivedLiveValues {
            return .liveValuesAlreadyArrived
        }
        if cachedValues.contextTag != launchContextTag {
            return .contextMismatch
        }
        return .adopt
    }
}

struct CachedValuesEntry: Codable {
    private static let currentFormatVersion = 1

    private let formatVersion: Int
    private let clientSDKKey: String
    private let cachedValues: CachedValues

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case clientSDKKey = "clientSdkKey"
    }

    init(clientSDKKey: String, cachedValues: CachedValues) {
        formatVersion = Self.currentFormatVersion
        self.clientSDKKey = clientSDKKey
        self.cachedValues = cachedValues
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        clientSDKKey = try container.decode(String.self, forKey: .clientSDKKey)
        cachedValues = try CachedValues(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(clientSDKKey, forKey: .clientSDKKey)
        try cachedValues.encode(to: encoder)
    }

    func serialized() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func cachedValues(in serialized: String, for clientSDKKey: String) -> CachedValues? {
        guard let entry = try? JSONDecoder().decode(CachedValuesEntry.self, from: Data(serialized.utf8)),
              entry.formatVersion == currentFormatVersion,
              entry.clientSDKKey == clientSDKKey
        else { return nil }

        return entry.cachedValues
    }
}
