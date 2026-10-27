@testable import ConfigDirector
import Foundation
import Testing

extension UserDefaultsStorageTests {
    struct CachingProvider {
        private static let instanceIDKey = "configdirector-sdk.instance-id"
        private static let clientSDKKeyDigest =
            "cc677751b8441e282621773a9be4622b11cd5bcffce54caabdd19f60e07d556c"
        private static let cachedValuesKey = "configdirector-sdk.cached-values." + clientSDKKeyDigest

        private func withDefaults<Outcome>(
            _ body: (UserDefaults) async throws -> Outcome
        ) async throws -> Outcome {
            try await UserDefaultsStorageTests.withDefaults(body)
        }

        @Test func readsNothingWhenNoEntryWasStored() async throws {
            try await withDefaults { defaults in
                let provider = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )

                #expect(provider.read() == nil)
            }
        }

        @Test func keepsTheEntryUnderAKeyNamedAfterTheClientSDKKeyDigest() async throws {
            try await withDefaults { defaults in
                let provider = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )

                try provider.write("the entry")

                #expect(provider.read() == "the entry")
                #expect(defaults.string(forKey: Self.cachedValuesKey) == "the entry")
            }
        }

        @Test func removesTheEntry() async throws {
            try await withDefaults { defaults in
                let provider = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )
                try provider.write("the entry")

                provider.remove()

                #expect(provider.read() == nil)
                #expect(defaults.object(forKey: Self.cachedValuesKey) == nil)
            }
        }

        @Test func theClientsDefaultStoreKeepsTheDigestOfTheClientSDKKeyNeverTheKey() async throws {
            try await withDefaults { defaults in
                let plan = CachingPlan.decide(
                    CachingOptions(),
                    clientSDKKey: "sdk-key",
                    instanceID: "instance-1",
                    logger: ConsoleLogger(level: .off),
                    defaults: defaults
                )
                guard case let .keepValues(store) = plan else {
                    Issue.record("expected the client to keep values in its default store")
                    return
                }

                store.replace(CachedValues(
                    contextTag: .identified(contextKind: "user", contextID: "user-123"),
                    environmentID: "env",
                    projectID: "proj",
                    configs: [:],
                    receivedAt: 1_761_000_000_000
                ))

                let reader = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )
                #expect(await waitUntil { reader.read() != nil })
                let stored = try #require(defaults.string(forKey: Self.cachedValuesKey))
                #expect(!stored.contains("sdk-key"))
                let entry = try JSONDecoder().decode(StoredCachedValuesEntry.self, from: Data(stored.utf8))
                #expect(entry.clientSdkKeyDigest == Self.clientSDKKeyDigest)
            }
        }

        @Test func acceptsEntriesUpTo256KB() async throws {
            try await withDefaults { defaults in
                let provider = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )

                #expect(provider.sizeLimit() == 262_144)
            }
        }

        @Test func keepsTheValuesBesideTheInstanceIDWithoutTouchingIt() async throws {
            try await withDefaults { defaults in
                let instanceIDStorage = UserDefaultsInstanceIDStorage(defaults: defaults)
                let provider = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )
                let firstLaunch = ClientFixture()
                firstLaunch.serveStream(servedConfigSet)
                let firstClient = try firstLaunch.makeClient(
                    caching: CachingOptions(provider: provider),
                    makeClientSession: { ClientSession.current(
                        storage: instanceIDStorage,
                        logger: ConsoleLogger(level: .off)
                    ) }
                )
                await firstClient.initialize()
                #expect(await waitUntil { provider.read() != nil })
                firstClient.close()
                let instanceIDRecord = try #require(defaults.string(forKey: Self.instanceIDKey))
                let instanceID = try #require(
                    JSONDecoder().decode(StoredInstanceID.self, from: Data(instanceIDRecord.utf8)).id
                )

                let relaunch = ClientFixture()
                relaunch.serveStream()
                let client = try relaunch.makeClient(
                    timeout: 0.3,
                    caching: CachingOptions(provider: provider),
                    makeClientSession: { ClientSession.current(
                        storage: instanceIDStorage,
                        logger: ConsoleLogger(level: .off)
                    ) }
                )
                defer { client.close() }
                await client.initialize()

                #expect(client.value(for: "dark-mode", default: false) == true)
                #expect(defaults.string(forKey: Self.instanceIDKey) == instanceIDRecord)
                let entry = try JSONDecoder().decode(
                    StoredCachedValuesEntry.self,
                    from: Data(#require(defaults.string(forKey: Self.cachedValuesKey)).utf8)
                )
                #expect(entry.contextTag.anonymousInstanceId == instanceID)
                #expect(Set(defaults.dictionaryRepresentation().keys
                        .filter { $0.hasPrefix("configdirector-sdk") })
                    == [Self.instanceIDKey, Self.cachedValuesKey])
            }
        }

        @Test func throwsWhenAnotherDomainOverridesTheWrite() async throws {
            try await withDefaults { defaults in
                defaults.setVolatileDomain(
                    [Self.cachedValuesKey: "managed"],
                    forName: UserDefaults.argumentDomain
                )
                defer { defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
                let provider = UserDefaultsCachingProvider(
                    clientSDKKeyDigest: Self.clientSDKKeyDigest,
                    defaults: defaults
                )

                #expect(throws: UserDefaultsCachingProvider.WriteRefused.self) {
                    try provider.write("the entry")
                }
            }
        }
    }
}

private struct StoredInstanceID: Decodable {
    var id: String
}
