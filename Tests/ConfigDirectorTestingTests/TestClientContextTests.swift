import ConfigDirector
import ConfigDirectorTesting
import Foundation
import Testing

private let userA = ConfigDirectorContext(id: "user-a")
private let userB = ConfigDirectorContext(id: "user-b")

/// Context updates, resumes, and closing, from the conformance scenarios of the testing contract.
struct TestClientContextTests {
    private let fixture = TestClientFixture()

    @Test func s13ContextUpdatesRecordsInitializeAndUpdateContextOnly() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        let client = testClient.client

        await client.initialize(context: userA)
        await client.updateContext(userB)
        client.pauseNetwork()
        await client.resumeNetwork()

        #expect(testClient.contextUpdates == [userA, userB])
        #expect(client.isReady)
    }

    @Test func initializeWithoutAContextRecordsAnEmptyContext() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        await testClient.client.initialize()

        #expect(testClient.contextUpdates == [ConfigDirectorContext()])
    }

    @Test func s26AHeldUpdateContextStaysPendingUntilCompleted() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize(context: userA)
        let events = StreamReader(client.events)
        testClient.holdContextUpdate()

        let update = Task { await client.updateContext(userB) }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        #expect(client.isReady == false)
        #expect(client.context == userA)
        #expect(client.value(for: "flag", default: false) == true)

        testClient.completeContextUpdate()
        await update.value

        #expect(client.isReady)
        #expect(client.context == userB)
        #expect(testClient.contextUpdates == [userA, userB])
        let ready = try #require(await events.next { readyReason(of: $0) != nil })
        #expect(readyReason(of: ready) == .contextUpdate)
    }

    @Test func s42AnInitializationHoldNeverHoldsAnUpdateContext() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize(context: userA)
        testClient.holdInitialization()

        let startedAt = Date()
        await client.updateContext(userB)
        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(client.isReady)
        #expect(testClient.contextUpdates == [userA, userB])

        let initialization = Task { await client.initialize(context: userA) }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        #expect(client.isReady == false)
        testClient.completeInitialization()
        await initialization.value
        #expect(client.isReady)
    }

    @Test func s43AFailedUpdateContextCompletesPromptlyAndServesTheLastValues() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize(context: userA)
        testClient.failContextUpdate()

        let startedAt = Date()
        await client.updateContext(userB)

        #expect(Date().timeIntervalSince(startedAt) < 1)
        #expect(client.isReady == false)
        #expect(client.context == userA)
        #expect(client.value(for: "flag", default: false) == true)
        #expect(fixture.logger.errors == ["An error occurred during context update"])
        #expect(fixture.logger.errorDescriptions.contains { $0.contains("failed this context update") })
    }

    @Test func s44AResumeIsNeverHeldAndLeavesTheContextUpdateHoldArmed() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize(context: userA)
        testClient.holdContextUpdate()
        client.pauseNetwork()
        #expect(client.isReady == false)

        await client.resumeNetwork()
        #expect(client.isReady)
        #expect(client.value(for: "flag", default: false) == true)

        let update = Task { await client.updateContext(userB) }
        #expect(await waitUntil { testClient.isHoldingAnAttempt })
        #expect(client.isReady == false)
        testClient.completeContextUpdate()
        await update.value
        #expect(client.isReady)
    }

    @Test func valuesSetWhilePausedAreDeliveredOnResume() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize()
        client.pauseNetwork()

        testClient.setValue(false, for: "flag")
        #expect(client.value(for: "flag", default: true) == true)

        await client.resumeNetwork()

        #expect(client.value(for: "flag", default: true) == false)
    }

    @Test func s14TheControlsAreSilentNoOpsAfterClose() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        let client = testClient.client
        let values = StreamReader(client.values(for: "flag", default: false))
        #expect(await values.next() == false)
        await client.initialize()
        #expect(await values.next() == true)

        client.close()
        testClient.setValue(false, for: "flag")
        testClient.removeValue(for: "flag")
        testClient.replaceValues(["count": 1])
        testClient.holdInitialization()
        testClient.completeInitialization()
        testClient.failInitialization()
        testClient.holdContextUpdate()
        testClient.completeContextUpdate()
        testClient.failContextUpdate()

        #expect(await values.next() == nil, "the stream finished on close and yields nothing more")
        #expect(client.isReady == false)
        #expect(fixture.logger.errors.isEmpty)
    }
}
