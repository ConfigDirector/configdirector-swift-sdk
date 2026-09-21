@_spi(ConfigDirectorWrapper) import ConfigDirector
import Foundation
import Testing

struct ConfigDirectorClientSDKIdentityTests {
    @Test func aWrapperIdentityIsSentToTheServerInPlaceOfTheSDKIdentity() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(identity: .openFeatureProvider(version: "9.8.7"))
        defer { client.close() }

        await client.initialize()

        let payload = try #require(fixture.streamRequests.first?.payload)
        #expect(payload.metaContext.sdkName == "swift-openfeature-client-provider")
        #expect(payload.metaContext.sdkVersion == "9.8.7")
    }

    @Test func aWrapperIdentityIsReportedWithTelemetry() async throws {
        let fixture = ClientFixture()
        fixture.serveStream(servedConfigSet)
        let client = try fixture.makeClient(identity: .openFeatureProvider(version: "9.8.7"))
        defer { client.close() }
        await client.initialize()

        _ = client.value(for: "dark-mode", default: false)

        _ = await waitUntil { !fixture.telemetryReports().isEmpty }
        let report = try #require(fixture.telemetryReports().first)
        #expect(report.metaContext.sdkName == "swift-openfeature-client-provider")
        #expect(report.metaContext.sdkVersion == "9.8.7")
    }

    @Test func theWrapperInitializerValidatesTheSDKKeyLikeThePublicOne() {
        #expect(throws: ConfigDirectorError.missingClientSDKKey) {
            try ConfigDirectorClient(
                clientSDKKey: " ",
                options: .test(),
                identity: .openFeatureProvider(version: "9.8.7")
            )
        }
    }
}
