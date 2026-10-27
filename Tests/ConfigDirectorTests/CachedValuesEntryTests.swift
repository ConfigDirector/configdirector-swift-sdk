@testable import ConfigDirector
import Foundation
import Testing

/// What the entry kept on the device holds and which launches it is adopted on.
struct CachedValuesEntryTests {
    private static let firstFormatEntry = """
    {"formatVersion":1,"clientSdkKey":"sdk-key","contextTag":{"contextKind":"user","contextId":"user-123"},\
    "environmentId":"env","projectId":"proj","configs":{"dark-mode":{"id":"dark-mode","key":"dark-mode",\
    "type":"boolean","value":"true","valueId":"on"}},"receivedAt":1761000000000}
    """

    private let provider = RecordingCachingProvider()

    @Test func theEntryHoldsTheFormatVersionTheContextTagTheIDsTheConfigsAndTheTime() async throws {
        let before = Int64(Date().timeIntervalSince1970 * 1000)

        try await keepValuesOnDevice(
            in: provider,
            context: ConfigDirectorContext(id: "device-7", kind: "device")
        )

        let entry = try #require(try provider.storedEntry())
        #expect(entry.formatVersion == 2)
        #expect(entry.contextTag.contextKind == "device")
        #expect(entry.contextTag.contextId == "device-7")
        #expect(entry.contextTag.anonymousInstanceId == nil)
        #expect(entry.environmentId == "env")
        #expect(entry.projectId == "proj")
        #expect(entry.receivedAt >= before)
        let darkMode = try #require(entry.configs["dark-mode"])
        #expect(darkMode.id == "dark-mode")
        #expect(darkMode.key == "dark-mode")
        #expect(darkMode.type == "boolean")
        #expect(darkMode.value == "true")
        #expect(darkMode.valueId == "on")
    }

    @Test func handsTheCachingProviderTheDigestOfTheClientSDKKeyNeverTheKey() async throws {
        try await keepValuesOnDevice(in: provider)

        let written = try #require(provider.stored)
        #expect(!written.contains("sdk-key"))
        #expect(try provider.storedEntry()?.clientSdkKeyDigest
            == "cc677751b8441e282621773a9be4622b11cd5bcffce54caabdd19f60e07d556c")
    }

    @Test func aContextWithoutAnIDIsTaggedWithTheInstanceID() async throws {
        try await keepValuesOnDevice(in: provider, context: nil)

        let entry = try #require(try provider.storedEntry())
        #expect(entry.contextTag.contextKind == "user")
        #expect(entry.contextTag.contextId == nil)
        #expect(entry.contextTag.anonymousInstanceId == "instance-1")
    }

    @Test func aRelaunchOfTheSameInstallWithoutAnIDAdoptsTheKeptValues() async throws {
        try await keepValuesOnDevice(in: provider, context: nil)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }

        await client.initialize()

        #expect(client.value(for: "dark-mode", default: false) == true)
    }

    @Test func aRelaunchWithAnotherInstanceIDWithoutAnIDDoesNotAdoptTheKeptValues() async throws {
        try await keepValuesOnDevice(in: provider, context: nil)
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(
            provider: provider,
            makeClientSession: { ClientSession(instanceID: "instance-2", ephemeral: true) }
        )
        defer { client.close() }

        await client.initialize()

        #expect(client.value(for: "dark-mode", default: false) == false)
    }

    @Test func aRelaunchWithAnotherContextKindDoesNotAdoptTheKeptValues() async throws {
        try await keepValuesOnDevice(in: provider, context: ConfigDirectorContext(id: "7", kind: "device"))
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "7"))

        #expect(client.value(for: "dark-mode", default: false) == false)
    }

    @Test func traitsAndNameTakeNoPartInTheMatch() async throws {
        try await keepValuesOnDevice(
            in: provider,
            context: ConfigDirectorContext(id: "user-123", name: "Ada")
        )
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(provider: provider)
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123", traits: ["plan": "pro"]))

        #expect(client.value(for: "dark-mode", default: false) == true)
    }

    @Test func removesAnEntryWithAnUnknownFormatVersion() async throws {
        try await keepValuesOnDevice(in: provider)
        let fromAnotherVersion = try #require(provider.stored).replacingOccurrences(
            of: #""formatVersion":2"#,
            with: #""formatVersion":3"#
        )
        let providerFromAnotherVersion = RecordingCachingProvider(stored: fromAnotherVersion)
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(
            provider: providerFromAnotherVersion,
            logger: logger
        )
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.value(for: "dark-mode", default: false) == false)
        #expect(providerFromAnotherVersion.removes == 1)
        #expect(providerFromAnotherVersion.stored == nil)
        #expect(logger.warnings.filter { $0.contains("could not be read and were removed") }.count == 1)
    }

    @Test func removesTheEntryAnEarlierReleaseKeptWithoutAWarning() async throws {
        let providerFromAnEarlierRelease = RecordingCachingProvider(stored: Self.firstFormatEntry)
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClientWithoutNetwork(
            provider: providerFromAnEarlierRelease,
            logger: logger
        )
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.value(for: "dark-mode", default: false) == false)
        #expect(providerFromAnEarlierRelease.removes == 1)
        #expect(providerFromAnEarlierRelease.stored == nil)
        #expect(!logger.warnings.contains { $0.contains("on the device") })
    }

    @Test func removesAnEntryWrittenForAnotherClientSDKKey() async throws {
        try await keepValuesOnDevice(in: provider)
        let logger = RecordingLogger()
        let fixture = ClientFixture()
        let client = try fixture.makeClient(
            clientSDKKey: "another-key",
            timeout: 0.3,
            caching: CachingOptions(provider: provider),
            logger: logger
        )
        defer { client.close() }

        await client.initialize(context: ConfigDirectorContext(id: "user-123"))

        #expect(client.value(for: "dark-mode", default: false) == false)
        #expect(provider.removes == 1)
        #expect(logger.warnings.filter { $0.contains("could not be read and were removed") }.count == 1)
    }
}
