@testable import ConfigDirectorSample
import ConfigDirectorTesting
import Testing

/// Runs inside the sample app, so the app links `ConfigDirector` and this bundle links it again
/// through `ConfigDirectorTesting`; building this target is what proves the two can coexist.
struct SampleUserTests {
    @Test func evaluatesConfigsAgainstTheChosenUser() async {
        let testClient = makeTestClient(values: ["welcome-message": "Welcome, beta tester"])
        defer { testClient.client.close() }

        await testClient.client.initialize(context: SampleUser.betaTester.context)

        #expect(testClient.contextUpdates == [SampleUser.betaTester.context])
        #expect(testClient.client.context?.traits?["role"] == "beta")
        #expect(testClient.client.value(for: "welcome-message", default: "") == "Welcome, beta tester")
    }
}
