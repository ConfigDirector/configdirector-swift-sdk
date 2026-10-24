import Foundation

struct ClientSession: Sendable {
    var instanceID: String
    var ephemeral: Bool
}

/// Where the instance ID record lives between app launches.
protocol InstanceIDStorage: Sendable {
    /// The stored record, or `nil` when nothing is stored.
    func read() throws -> String?

    /// Stores `record`, returning whether it is now stored.
    func write(_ record: String) throws -> Bool
}

private struct StoredInstanceIDRecord: Codable {
    var version: Int
    var id: String
    var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case id, createdAt
    }
}

private enum StoredInstanceID {
    case current(String)
    case nothingUsable
    case unreadable
}

extension ClientSession {
    private static let recordVersion = 1
    private static let uuidV4Pattern =
        "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

    static func current(storage: any InstanceIDStorage, logger: any ConfigDirectorLogger) -> ClientSession {
        switch storedInstanceID(in: storage, logger: logger) {
        case let .current(instanceID):
            return ClientSession(instanceID: instanceID, ephemeral: false)
        case .unreadable:
            return ClientSession(instanceID: UUID().uuidString, ephemeral: true)
        case .nothingUsable:
            let instanceID = UUID().uuidString
            let stored = store(instanceID, in: storage, logger: logger)
            return ClientSession(instanceID: instanceID, ephemeral: !stored)
        }
    }

    private static func storedInstanceID(
        in storage: any InstanceIDStorage,
        logger: any ConfigDirectorLogger
    ) -> StoredInstanceID {
        let storedJSON: String?
        do {
            storedJSON = try storage.read()
        } catch {
            logger.warn(couldNot("read"), error: error)
            return .unreadable
        }
        guard let storedJSON else { return .nothingUsable }

        guard let record = try? JSONDecoder()
            .decode(StoredInstanceIDRecord.self, from: Data(storedJSON.utf8))
        else {
            logger.debug("The stored instance ID is not a valid record, generating a new one")
            return .nothingUsable
        }

        guard record.version == recordVersion, isUUIDV4(record.id), record.createdAt > 0 else {
            logger.debug("The stored instance ID failed validation, generating a new one")
            return .nothingUsable
        }

        return .current(record.id)
    }

    private static func isUUIDV4(_ instanceID: String) -> Bool {
        instanceID.range(of: uuidV4Pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func store(
        _ instanceID: String,
        in storage: any InstanceIDStorage,
        logger: any ConfigDirectorLogger
    ) -> Bool {
        let record = StoredInstanceIDRecord(
            version: recordVersion,
            id: instanceID,
            createdAt: Date().millisecondsSince1970
        )
        let stored: Bool
        do {
            stored = try storage.write(String(decoding: JSONEncoder().encode(record), as: UTF8.self))
        } catch {
            logger.warn(couldNot("store"), error: error)
            return false
        }

        if !stored {
            logger.warn(couldNot("store"))
        }
        return stored
    }

    private static func couldNot(_ action: String) -> String {
        """
        The ConfigDirector SDK could not \(action) its instance ID, so this app start looks like a new \
        install to ConfigDirector.
        """
    }
}
