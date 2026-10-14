@testable import ConfigDirector
import Foundation
import Testing

/// Serialized because the argument domain one test overrides is shared by the whole process.
@Suite(.serialized)
struct UserDefaultsInstanceIDStorageTests {
    /// A suite of its own in a temporary directory: `UserDefaults` takes a path as a suite name and
    /// keeps the plist there, so the test leaves nothing in the user's Preferences folder.
    private func withDefaults<Outcome>(_ body: (UserDefaults) throws -> Outcome) throws -> Outcome {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("configdirector-sdk-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try #require(
            UserDefaults(suiteName: directory.appendingPathComponent("instance-id.plist").path)
        )

        return try body(defaults)
    }

    @Test func readsNothingWhenNoRecordWasStored() throws {
        try withDefaults { defaults in
            let storage = UserDefaultsInstanceIDStorage(defaults: defaults)

            #expect(storage.read() == nil)
        }
    }

    @Test func readsBackTheRecordItStored() throws {
        try withDefaults { defaults in
            let storage = UserDefaultsInstanceIDStorage(defaults: defaults)

            let stored = storage.write(#"{"v":1,"id":"an-id","createdAt":1}"#)

            #expect(stored == true)
            #expect(storage.read() == #"{"v":1,"id":"an-id","createdAt":1}"#)
            #expect(
                defaults.string(forKey: "configdirector-sdk.instance-id")
                    == #"{"v":1,"id":"an-id","createdAt":1}"#
            )
        }
    }

    @Test func reportsAWriteThatAnotherDomainOverrides() throws {
        try withDefaults { defaults in
            defaults.setVolatileDomain(
                ["configdirector-sdk.instance-id": "managed"],
                forName: UserDefaults.argumentDomain
            )
            defer { defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
            let storage = UserDefaultsInstanceIDStorage(defaults: defaults)

            let stored = storage.write(#"{"v":1,"id":"an-id","createdAt":1}"#)

            #expect(stored == false)
        }
    }
}
