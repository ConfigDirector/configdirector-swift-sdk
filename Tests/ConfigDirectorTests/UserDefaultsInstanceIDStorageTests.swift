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

    @Test func reusesTheInstanceIDAnEarlierVersionOfTheSDKStored() throws {
        try withDefaults { defaults in
            let storedByEarlierVersion =
                #"{"v":1,"id":"6B1D5C2E-0F4A-4B7C-9D3E-2A1F0C9B8E7D","createdAt":1760000000000}"#
            defaults.set(storedByEarlierVersion, forKey: "configdirector-sdk.instance-id")

            let session = ClientSession.current(
                storage: UserDefaultsInstanceIDStorage(defaults: defaults),
                logger: RecordingLogger()
            )

            #expect(session.instanceID == "6B1D5C2E-0F4A-4B7C-9D3E-2A1F0C9B8E7D")
            #expect(session.ephemeral == false)
            #expect(defaults.string(forKey: "configdirector-sdk.instance-id") == storedByEarlierVersion)
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
