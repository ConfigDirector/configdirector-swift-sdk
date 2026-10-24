@testable import ConfigDirector
import Foundation
import Testing

extension UserDefaultsStorageTests {
    struct InstanceIDStorage {
        private func withDefaults<Outcome>(_ body: (UserDefaults) throws -> Outcome) async throws -> Outcome {
            try await UserDefaultsStorageTests.withDefaults(body)
        }

        @Test func readsNothingWhenNoRecordWasStored() async throws {
            try await withDefaults { defaults in
                let storage = UserDefaultsInstanceIDStorage(defaults: defaults)

                #expect(storage.read() == nil)
            }
        }

        @Test func readsBackTheRecordItStored() async throws {
            try await withDefaults { defaults in
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

        @Test func reusesTheInstanceIDAnEarlierVersionOfTheSDKStored() async throws {
            try await withDefaults { defaults in
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

        @Test func reportsAWriteThatAnotherDomainOverrides() async throws {
            try await withDefaults { defaults in
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
}
