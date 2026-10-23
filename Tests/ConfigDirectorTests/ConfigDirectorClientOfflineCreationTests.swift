@_spi(ConfigDirectorWrapper) @testable import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientOfflineCreationTests {
    private let offlineValues: [String: ServedValue] = ["dark-mode": true, "max-retries": 3]

    @Test func rejectsValuesGivenWhenStreaming() {
        let fixture = ClientFixture()

        #expect(throws: ConfigDirectorError.valuesRequireOfflineMode) {
            try fixture.makeClient(mode: .streaming, values: offlineValues)
        }
    }

    @Test func rejectsValuesGivenWhenPolling() {
        let fixture = ClientFixture()

        #expect(throws: ConfigDirectorError.valuesRequireOfflineMode) {
            try fixture.makeClient(mode: .polling, values: offlineValues)
        }
    }

    @Test func rejectsABlankKeyAmongTheValues() {
        let fixture = ClientFixture()

        #expect(throws: ConfigDirectorError.invalidOfflineValue(key: " ")) {
            try fixture.makeClient(mode: .offline, values: [" ": true])
        }
    }

    @Test func rejectsANumberThatIsNotFinite() {
        let fixture = ClientFixture()

        #expect(throws: ConfigDirectorError.invalidOfflineValue(key: "discount-rate")) {
            try fixture.makeClient(mode: .offline, values: ["discount-rate": .float(.nan)])
        }
    }

    @Test func rejectsANumberThatIsNotFiniteInsideAJSONValue() {
        let fixture = ClientFixture()

        #expect(throws: ConfigDirectorError.invalidOfflineValue(key: "theme")) {
            try fixture.makeClient(mode: .offline, values: ["theme": ["radius": .float(.infinity)]])
        }
    }

    @Test func ignoresTheTimeout() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(mode: .offline, values: offlineValues, timeout: 0)
        defer { client.close() }

        await client.initialize()

        #expect(client.isReady)
        #expect(client.value(for: "max-retries", default: 0) == 3)
    }

    @Test func ignoresAPollingIntervalBelowTheMinimum() async throws {
        let fixture = ClientFixture()
        let logger = RecordingLogger()
        let client = try fixture.makeClient(
            mode: .offline,
            values: offlineValues,
            pollingInterval: 1,
            logger: logger
        )
        defer { client.close() }

        await client.initialize()

        #expect(client.isReady)
        #expect(logger.warnings.isEmpty)
    }

    @Test func ignoresABaseURLThatIsNotAbsolute() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(
            mode: .offline,
            values: offlineValues,
            baseURL: #require(URL(string: "/client"))
        )
        defer { client.close() }

        await client.initialize()

        #expect(client.isReady)
    }

    @Test func doesNotLookUpTheStoredInstanceID() throws {
        let fixture = ClientFixture()
        let lookedUp = Locked(false)

        let client = try fixture.makeClient(
            mode: .offline,
            values: offlineValues,
            makeClientSession: {
                lookedUp.withLock { $0 = true }
                return ClientSession(instanceID: "instance-1", ephemeral: false)
            }
        )
        defer { client.close() }

        #expect(lookedUp.withLock { $0 } == false)
    }

    @Test func acceptsABlankClientSDKKey() async throws {
        let fixture = ClientFixture()
        let client = try fixture.makeClient(clientSDKKey: "", mode: .offline, values: offlineValues)
        defer { client.close() }

        await client.initialize()

        #expect(client.value(for: "max-retries", default: 0) == 3)
    }

    @Test func isCreatedFromTheOptionsAlone() async throws {
        let client = try ConfigDirectorClient(options: ConfigDirectorClientOptions(
            connection: ConnectionOptions(mode: .offline, values: offlineValues),
            logger: ConsoleLogger(level: .off)
        ))
        defer { client.close() }

        await client.initialize()

        #expect(client.isReady)
        #expect(client.value(for: "max-retries", default: 0) == 3)
    }

    @Test func isCreatedFromTheOptionsAloneOnBehalfOfAWrapper() async throws {
        let client = try ConfigDirectorClient(
            options: ConfigDirectorClientOptions(
                connection: ConnectionOptions(mode: .offline, values: offlineValues),
                logger: ConsoleLogger(level: .off)
            ),
            identity: .openFeatureProvider(version: "1.0.0")
        )
        defer { client.close() }

        await client.initialize()

        #expect(client.isReady)
        #expect(client.value(for: "max-retries", default: 0) == 3)
    }

    @Test func theOptionsAloneStillNeedAKeyToStream() {
        #expect(throws: ConfigDirectorError.missingClientSDKKey) {
            try ConfigDirectorClient(options: .test())
        }
    }

    @Test func aBlankKeyIsStillRejectedWhenPolling() {
        #expect(throws: ConfigDirectorError.missingClientSDKKey) {
            try ConfigDirectorClient(clientSDKKey: "", options: ConfigDirectorClientOptions(
                connection: ConnectionOptions(mode: .polling),
                logger: ConsoleLogger(level: .off)
            ))
        }
    }
}
