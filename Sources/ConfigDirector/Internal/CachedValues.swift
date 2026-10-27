import CryptoKit
import Foundation

enum CachingPlan: Sendable {
    case keepValues(CachedValuesStore)
    case keepNothing

    static func decide(
        _ caching: CachingOptions,
        clientSDKKey: String,
        instanceID: String,
        logger: any ConfigDirectorLogger,
        defaults: UserDefaults = .standard
    ) -> CachingPlan {
        guard caching.enabled else {
            logger.debug("No values are kept on the device: caching is turned off")
            return .keepNothing
        }

        let clientSDKKeyDigest = sha256HexDigest(of: clientSDKKey)
        return .keepValues(CachedValuesStore(
            provider: caching.provider ?? UserDefaultsCachingProvider(
                clientSDKKeyDigest: clientSDKKeyDigest,
                defaults: defaults
            ),
            clientSDKKeyDigest: clientSDKKeyDigest,
            instanceID: instanceID,
            logger: logger
        ))
    }

    private static func sha256HexDigest(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
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
    case firstFormatEntry
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
    enum ParseOutcome {
        case cachedValues(CachedValues)
        case firstFormatEntry
        case notAnEntry
    }

    private struct FormatVersion: Decodable {
        let formatVersion: Int
    }

    private static let currentFormatVersion = 2
    private static let firstFormatVersion = 1

    private let clientSDKKeyDigest: String
    private let cachedValues: CachedValues

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case clientSDKKeyDigest = "clientSdkKeyDigest"
    }

    init(clientSDKKeyDigest: String, cachedValues: CachedValues) {
        self.clientSDKKeyDigest = clientSDKKeyDigest
        self.cachedValues = cachedValues
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientSDKKeyDigest = try container.decode(String.self, forKey: .clientSDKKeyDigest)
        cachedValues = try CachedValues(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentFormatVersion, forKey: .formatVersion)
        try container.encode(clientSDKKeyDigest, forKey: .clientSDKKeyDigest)
        try cachedValues.encode(to: encoder)
    }

    func serialized() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func parse(_ serialized: String, for clientSDKKeyDigest: String) -> ParseOutcome {
        let data = Data(serialized.utf8)
        guard let version = try? JSONDecoder().decode(FormatVersion.self, from: data) else {
            return .notAnEntry
        }

        switch version.formatVersion {
        case currentFormatVersion:
            guard let entry = try? JSONDecoder().decode(CachedValuesEntry.self, from: data),
                  entry.clientSDKKeyDigest == clientSDKKeyDigest
            else { return .notAnEntry }
            return .cachedValues(entry.cachedValues)
        case firstFormatVersion:
            return .firstFormatEntry
        default:
            return .notAnEntry
        }
    }
}
