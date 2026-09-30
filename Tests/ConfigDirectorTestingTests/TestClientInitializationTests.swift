import ConfigDirector
import ConfigDirectorTesting
import Foundation
import Testing

private let userA = ConfigDirectorContext(id: "user-a")
private let userB = ConfigDirectorContext(id: "user-b")

/// Holding, completing, and failing initialization, from the conformance scenarios of the testing contract.
struct TestClientInitializationTests {
    private let fixture = TestClientFixture()

    @Test func s9AHeldInitializeStaysPendingUntilCompleted() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        let events = StreamReader(client.events)
        testClient.holdInitialization()

        let initialization = Task { await client.initialize() }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        #expect(client.isReady == false)
        #expect(client.isInitializing)
        #expect(client.value(for: "flag", default: false) == false)

        testClient.completeInitialization()
        #expect(client.isReady)
        #expect(client.value(for: "flag", default: false) == true)

        await initialization.value
        #expect(client.isInitializing == false)
        #expect(try readyReason(of: #require(await events.next { readyReason(of: $0) != nil })) ==
            .initialization)
        testClient.setValue(false, for: "flag")
        #expect(client.value(for: "flag", default: true) == false)
    }

    @Test func s10AValueSetWhileHeldIsDeliveredOnCompletion() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        testClient.holdInitialization()

        let initialization = Task { await client.initialize() }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        testClient.setValue(false, for: "flag")
        testClient.setValue(3, for: "count")
        testClient.completeInitialization()
        await initialization.value

        #expect(client.value(for: "flag", default: true) == false)
        #expect(client.value(for: "count", default: 0) == 3)
    }

    @Test func s11AHeldInitializeTimesOutNotReadyAndTheNextOneIsServed() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true], timeout: 0.2)
        defer { testClient.client.close() }
        let client = testClient.client
        let events = StreamReader(client.events)
        testClient.holdInitialization()

        let startedAt = Date()
        await client.initialize(context: userA)

        #expect(Date().timeIntervalSince(startedAt) < 1.5)
        #expect(client.isReady == false)
        #expect(client.isInitializing)
        #expect(client.context == userA)
        #expect(fixture.logger.warnings.contains { $0.contains("Timed out waiting for initialization") })
        #expect(testClient.isHoldingAnAttempt == false)

        testClient.completeInitialization()
        #expect(client.isReady == false)

        await client.initialize(context: userA)

        #expect(client.isReady)
        #expect(client.value(for: "flag", default: false) == true)
        #expect(try readyReason(of: #require(await events.next { readyReason(of: $0) != nil })) ==
            .initialization)
    }

    @Test func aHeldInitializeWaitsTheSDKDefaultTimeoutOfThreeSeconds() async {
        let testClient = makeTestClient(values: ["flag": true], logger: fixture.logger)
        defer { testClient.client.close() }
        testClient.holdInitialization()

        let startedAt = Date()
        await testClient.client.initialize()

        #expect(Date().timeIntervalSince(startedAt) >= 2.5)
        #expect(Date().timeIntervalSince(startedAt) < 6)
        #expect(testClient.client.isReady == false)
    }

    @Test func s12AFailedInitializeCompletesPromptlyAndNotReady() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        testClient.failInitialization()

        let startedAt = Date()
        await client.initialize(context: userA)

        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(client.isReady == false)
        #expect(client.isInitializing == false)
        #expect(client.context == nil)
        #expect(fixture.logger.errors == ["An error occurred during initialization"])
        #expect(fixture.logger.errorDescriptions
            .contains { $0.contains("status: 401") && $0.contains("failed this initialization") })
    }

    @Test func failInitializationFailsAnAttemptThatIsAlreadyHeld() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        let client = testClient.client
        testClient.holdInitialization()

        let initialization = Task { await client.initialize() }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        testClient.failInitialization()
        await initialization.value

        #expect(client.isReady == false)
        #expect(client.isInitializing == false)
        #expect(testClient.isHoldingAnAttempt == false)
        #expect(fixture.logger.errorDescriptions.contains { $0.contains("failed this initialization") })
    }

    @Test func s25TheAttemptAfterAFailureSucceedsWithTheStoredValues() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        let client = testClient.client
        testClient.failInitialization()
        await client.initialize()
        #expect(client.isReady == false)

        testClient.setValue(true, for: "flag")
        await client.initialize()

        #expect(client.isReady)
        #expect(client.value(for: "flag", default: false) == true)
    }

    @Test func s38CompleteInitializationBeforeInitializeDisarmsTheHold() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        testClient.holdInitialization()
        testClient.completeInitialization()

        let startedAt = Date()
        await testClient.client.initialize()

        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(testClient.client.isReady)
    }

    @Test func s40ReplaceValuesDisarmsAHoldAndAFailure() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        testClient.holdInitialization()
        testClient.replaceValues(["count": 1])
        await client.initialize()
        #expect(client.isReady)
        #expect(client.value(for: "count", default: 0) == 1)
        #expect(client.value(for: "flag", default: false) == false)

        testClient.failInitialization()
        testClient.replaceValues(["count": 2])
        await client.initialize()

        #expect(client.isReady)
        #expect(client.value(for: "count", default: 0) == 2)
        #expect(fixture.logger.errors.isEmpty)
    }

    @Test func holdingTwiceArmsOneHold() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        testClient.holdInitialization()
        testClient.holdInitialization()

        let initialization = Task { await testClient.client.initialize() }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        testClient.completeInitialization()
        await initialization.value
        #expect(testClient.client.isReady)

        let startedAt = Date()
        await testClient.client.initialize()

        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(testClient.client.isReady)
    }

    @Test func s33ClosingDuringAHeldInitializeEndsItPromptlyAndHoldsNothing() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        let client = testClient.client
        testClient.holdInitialization()

        let initialization = Task { await client.initialize(); return client.isReady }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })

        let startedAt = Date()
        client.close()
        let readyOnReturn = await initialization.value

        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(readyOnReturn == false)
        #expect(await waitUntil { testClient.isHoldingAnAttempt == false })
        #expect(fixture.logger.warnings.contains { $0.contains("Timed out waiting for initialization") })
    }

    @Test func s17NothingIsHeldAfterClose() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        let client = testClient.client
        await client.initialize()
        testClient.setValue(false, for: "flag")

        client.close()

        #expect(testClient.isHoldingAnAttempt == false)
        #expect(fixture.logger.errors.isEmpty)
    }

    @Test func s23NothingReachesForTheNetwork() async {
        let testClient = fixture.makeTestClient(values: ["flag": true, "count": 2])
        let client = testClient.client
        await client.initialize()
        #expect(client.value(for: "flag", default: false) == true)
        #expect(client.value(for: "count", default: 0) == 2)
        testClient.setValue(false, for: "flag")
        #expect(client.value(for: "flag", default: true) == false)

        client.close()
        _ = await waitUntil(timeout: 0.5) { InMemoryConnection.recordedRequestCount > 0 }

        #expect(InMemoryConnection.recordedRequestCount == 0)
        #expect(fixture.logger.warnings.isEmpty)
    }

    @Test func buildsAndInitializesWithoutAWordAboveDebug() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }

        await testClient.client.initialize()
        testClient.setValue(false, for: "flag")

        #expect(testClient.client.isReady)
        #expect(fixture.logger.messagesAboveDebug.isEmpty)
    }
}
