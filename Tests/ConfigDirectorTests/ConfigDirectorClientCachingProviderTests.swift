@testable import ConfigDirector
import Foundation
import Testing

/// How the client treats its caching provider: the option that turns it off, the size limit, and a
/// provider that fails.
struct ConfigDirectorClientCachingProviderTests {
    private let provider = RecordingCachingProvider()
    private let logger = RecordingLogger()

    @Test func readsAndWritesNothingWhenCachingIsOff() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(caching: CachingOptions(enabled: false, provider: provider))
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        await settle()
        #expect(client.isReady)
        #expect(provider.reads == 0)
        #expect(provider.writes.isEmpty)
    }

    @Test func readsAndWritesNothingInOfflineMode() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(
            mode: .offline,
            values: ["dark-mode": true],
            caching: CachingOptions(provider: provider)
        )
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        await settle()
        #expect(client.value(for: "dark-mode", default: false) == true)
        #expect(provider.reads == 0)
        #expect(provider.writes.isEmpty)
    }

    @Test func removesTheEntryAndWarnsOnceWhenItExceedsTheProviderLimit() async throws {
        let tinyLimitProvider = RecordingCachingProvider(stored: "an entry from an earlier run", limit: 10)
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(
            caching: CachingOptions(provider: tinyLimitProvider),
            logger: logger
        )
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))
        #expect(await waitUntil { tinyLimitProvider.removes >= 2 })

        fixture.pushToStream(deltaConfigSet([ServedConfig("max-retries", "integer", "5")]))

        #expect(await waitUntil { tinyLimitProvider.removes >= 3 })
        #expect(tinyLimitProvider.stored == nil)
        #expect(tinyLimitProvider.writes.isEmpty)
        #expect(logger.warnings.filter { $0.contains("exceed the caching provider's limit of 10 bytes") }
            .count == 1)
    }

    @Test func honorsTheLimitOfTheGivenProviderInsteadOfTheDefaultOne() async throws {
        let largeLimitProvider = RecordingCachingProvider(limit: 2 * 1024 * 1024)
        let fixture = ClientFixture()
        let largeValue = String(repeating: "x", count: 300 * 1024)
        fixture.serveStream(configSetJSON([ServedConfig("banner", "string", largeValue)]))
        let client = try fixture.makeClient(caching: CachingOptions(provider: largeLimitProvider))
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(await waitUntil { largeLimitProvider.writes.count == 1 })
        #expect(largeLimitProvider.writes.first?.utf8.count ?? 0 > 262_144)
        #expect(largeLimitProvider.removes == 0)
        #expect(UserDefaults.standard.object(forKey: "configdirector-sdk.cached-values."
                + "cc677751b8441e282621773a9be4622b11cd5bcffce54caabdd19f60e07d556c") == nil)
    }

    @Test func aProviderThatThrowsOnReadLeavesTheEntryAndServesInCodeDefaults() async throws {
        try await keepValuesOnDevice(in: provider)
        provider.failReads()
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider, logger: logger)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.value(for: "dark-mode", default: false) == false)
        #expect(provider.removes == 0)
        #expect(provider.stored != nil)
        #expect(logger.warnings.filter { $0.contains("Could not read the values kept on the device") }
            .count == 1)
    }

    @Test func aProviderThatThrowsOnWriteLeavesTheClientRunningAndWarnsOnce() async throws {
        provider.failWrites()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(caching: CachingOptions(provider: provider), logger: logger)
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        fixture.pushToStream(deltaConfigSet([ServedConfig("max-retries", "integer", "5")]))

        #expect(await waitUntil { client.value(for: "max-retries", default: 0) == 5 })
        #expect(client.isReady)
        #expect(await waitUntil {
            logger.warnings.contains { $0.contains("Could not keep the values on the device") }
        })
        await settle()
        #expect(logger.warnings.filter { $0.contains("Could not keep the values on the device") }.count == 1)
    }

    @Test func aProviderThatThrowsOnRemoveLeavesTheClientRunningAndWarnsOnce() async throws {
        let failingRemoveProvider = RecordingCachingProvider(stored: "not an entry", limit: 10)
        failingRemoveProvider.failRemoves()
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(
            caching: CachingOptions(provider: failingRemoveProvider),
            logger: logger
        )
        defer { client.close() }
        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        fixture.pushToStream(deltaConfigSet([ServedConfig("max-retries", "integer", "5")]))

        #expect(await waitUntil { failingRemoveProvider.removes >= 3 })
        #expect(client.isReady)
        #expect(client.value(for: "max-retries", default: 0) == 5)
        #expect(logger.warnings.filter { $0.contains("Could not remove the values kept on the device") }
            .count == 1)
    }
}
