@testable import ConfigDirector
import Foundation
import Testing

struct ClientSessionTests {
    private final class RecordingInstanceIDStorage: InstanceIDStorage, @unchecked Sendable {
        var record: String?
        var readFailure: (any Error)?
        var writeFailure: (any Error)?
        var writeStores = true
        private(set) var writes: [String] = []

        func read() throws -> String? {
            if let readFailure {
                throw readFailure
            }
            return record
        }

        func write(_ record: String) throws -> Bool {
            writes.append(record)
            if let writeFailure {
                throw writeFailure
            }
            guard writeStores else { return false }
            self.record = record
            return true
        }
    }

    private struct StorageFailure: Error {}

    private static let oneYearInMilliseconds: Int64 = 366 * 24 * 60 * 60 * 1000
    private static let storedID = "11111111-1111-4111-8111-111111111111"
    private static let uuidV4Pattern =
        "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

    private let logger = RecordingLogger()
    private let storage = RecordingInstanceIDStorage()

    private var now: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func record(id: String = storedID, createdAt: Int64, version: Int = 1) throws -> String {
        try String(
            decoding: JSONEncoder().encode(StoredRecord(version: version, id: id, createdAt: createdAt)),
            as: UTF8.self
        )
    }

    private func storedRecord() throws -> StoredRecord {
        try JSONDecoder().decode(StoredRecord.self, from: Data(#require(storage.record).utf8))
    }

    private func isUUIDV4(_ instanceID: String) -> Bool {
        instanceID.range(of: Self.uuidV4Pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    @Test func reusesTheStoredInstanceIDWithoutRewritingItAYearAfterItWasGenerated() throws {
        let createdAt = now - Self.oneYearInMilliseconds
        storage.record = try record(createdAt: createdAt)

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.instanceID == Self.storedID)
        #expect(session.ephemeral == false)
        #expect(storage.writes.isEmpty)
        #expect(try storedRecord().createdAt == createdAt)
    }

    @Test func generatesAnInstanceIDAndStoresItWithItsCreationTimeWhenNothingIsStored() throws {
        let before = now

        let session = ClientSession.current(storage: storage, logger: logger)

        let after = now
        #expect(isUUIDV4(session.instanceID))
        #expect(session.ephemeral == false)
        #expect(try storedRecord().version == 1)
        #expect(try storedRecord().id == session.instanceID)
        #expect(try (before ... after).contains(storedRecord().createdAt))
    }

    @Test func reusesTheStoredInstanceIDWhenItsCreationTimeIsInTheFuture() throws {
        storage.record = try record(createdAt: now + 60000)

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.instanceID == Self.storedID)
        #expect(session.ephemeral == false)
        #expect(storage.writes.isEmpty)
    }

    @Test func generatesANewInstanceIDWhenTheStoredCreationTimeIsNotPositive() throws {
        storage.record = try record(createdAt: 0)

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.instanceID != Self.storedID)
        #expect(try storedRecord().id == session.instanceID)
    }

    @Test func generatesANewInstanceIDWhenTheStoredCreationTimeIsTheMostNegativeInteger() throws {
        storage.record = try record(createdAt: Int64.min)

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.instanceID != Self.storedID)
        #expect(try storedRecord().id == session.instanceID)
    }

    @Test func generatesANewInstanceIDWhenTheStoredRecordHasAnotherVersion() throws {
        storage.record = try record(createdAt: now, version: 2)

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.instanceID != Self.storedID)
        #expect(try storedRecord().version == 1)
        #expect(try storedRecord().id == session.instanceID)
    }

    @Test func generatesANewInstanceIDWhenTheStoredOneIsNotAUUID() throws {
        storage.record = try record(id: "instance-1", createdAt: now)

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.instanceID != "instance-1")
        #expect(try storedRecord().id == session.instanceID)
    }

    @Test func generatesANewInstanceIDWhenTheStoredRecordCannotBeReadAsJSON() throws {
        storage.record = "{oops"

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(session.ephemeral == false)
        #expect(try storedRecord().id == session.instanceID)
    }

    @Test func usesAnEphemeralInstanceIDWithoutWritingWhenTheStorageCannotBeRead() throws {
        storage.record = try record(createdAt: now)
        storage.readFailure = StorageFailure()

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(isUUIDV4(session.instanceID))
        #expect(session.ephemeral == true)
        #expect(storage.writes.isEmpty)
        #expect(logger.warnings.count == 1)
    }

    @Test func usesAnEphemeralInstanceIDWhenTheStorageReportsTheWriteDidNotHappen() {
        storage.writeStores = false

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(isUUIDV4(session.instanceID))
        #expect(session.ephemeral == true)
        #expect(logger.warnings.count == 1)
    }

    @Test func usesAnEphemeralInstanceIDWhenWritingToTheStorageThrows() {
        storage.writeFailure = StorageFailure()

        let session = ClientSession.current(storage: storage, logger: logger)

        #expect(isUUIDV4(session.instanceID))
        #expect(session.ephemeral == true)
        #expect(storage.record == nil)
        #expect(logger.warnings.count == 1)
    }
}

/// The record the SDK stores, as the tests read it back.
private struct StoredRecord: Codable {
    var version: Int
    var id: String
    var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case id, createdAt
    }
}
