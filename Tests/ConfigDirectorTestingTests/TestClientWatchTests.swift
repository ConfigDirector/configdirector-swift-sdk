import ConfigDirector
import ConfigDirectorTesting
import Foundation
import Testing

private let userA = ConfigDirectorContext(id: "user-a")
private let userB = ConfigDirectorContext(id: "user-b")

/// Watches and events under a test client, from the conformance scenarios of the testing contract.
struct TestClientWatchTests {
    private let fixture = TestClientFixture()

    @Test func s4SetValueFiresTheWatcherAndListsOnlyTheKey() async throws {
        let testClient = fixture.makeTestClient(values: ["dark-mode": false, "other": 1])
        defer { testClient.client.close() }
        let client = testClient.client
        let events = StreamReader(client.events)
        let values = StreamReader(client.values(for: "dark-mode", default: false))
        await client.initialize()
        #expect(await values.next() == false)
        _ = await events.next()
        _ = await events.next()
        _ = await events.next()

        testClient.setValue(true, for: "dark-mode")

        #expect(await values.next() == true)
        let event = try #require(await events.next())
        let update = try #require(configsUpdate(of: event))
        #expect(update.keys == ["dark-mode"])
        #expect(update.removedKeys.isEmpty)
    }

    @Test func s5SetValueOfAnotherKeyLeavesAWatcherAlone() async {
        let testClient = fixture.makeTestClient(values: ["a": 1, "b": 2])
        defer { testClient.client.close() }
        let aValues = testClient.client.values(for: "a", default: 0)
        await testClient.client.initialize()

        testClient.setValue(3, for: "b")
        testClient.client.close()

        let seen = await Array(aValues)
        #expect(seen == [1])
    }

    @Test func s7RemoveValueHandsTheWatcherTheDefaultAndReportsTheKeyAsRemoved() async throws {
        let testClient = fixture.makeTestClient(values: ["dark-mode": true, "other": 1])
        defer { testClient.client.close() }
        let client = testClient.client
        let values = StreamReader(client.values(for: "dark-mode", default: false))
        await client.initialize()
        #expect(await values.next() == true)
        let events = StreamReader(client.events)

        testClient.removeValue(for: "dark-mode")

        #expect(await values.next() == false)
        let event = try #require(await events.next())
        let update = try #require(configsUpdate(of: event))
        #expect(update.keys == ["other"])
        #expect(update.removedKeys == ["dark-mode"])
    }

    @Test func s16AValuesStreamEmitsEachValueTheTestClientServes() async {
        let testClient = fixture.makeTestClient(values: ["greeting": "hello"])
        defer { testClient.client.close() }
        let greetings = StreamReader(testClient.client.values(for: "greeting", default: "none"))
        #expect(await greetings.next() == "none")

        await testClient.client.initialize()
        #expect(await greetings.next() == "hello")

        testClient.setValue("hi", for: "greeting")
        #expect(await greetings.next() == "hi")

        testClient.removeValue(for: "greeting")
        #expect(await greetings.next() == "none")
    }

    @Test func s39InitializePublishesContextUpdatedThenReadyThenConfigsUpdated() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        let events = StreamReader(testClient.client.events)

        await testClient.client.initialize(context: userA)

        guard case let .contextUpdated(context) = try #require(await events.next()) else {
            Issue.record("expected contextUpdated first")
            return
        }
        #expect(context == userA)
        #expect(try readyReason(of: #require(await events.next())) == .initialization)
        #expect(try configsUpdate(of: #require(await events.next()))?.keys == ["flag"])
    }

    @Test func s41AnOperationCalledFromAWatcherIsDeliveredAfterTheOuterUpdate() async {
        let testClient = fixture.makeTestClient(values: ["a": 1])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize()
        let bValues = StreamReader(client.values(for: "b", default: 0))
        #expect(await bValues.next() == 0)
        let watching = Task {
            for await value in client.values(for: "a", default: 0) where value > 1 {
                testClient.setValue(.integer(value * 2), for: "b")
            }
        }
        defer { watching.cancel() }

        testClient.setValue(5, for: "a")

        #expect(await bValues.next() == 10)
        #expect(client.value(for: "a", default: 0) == 5)
        #expect(client.value(for: "b", default: 0) == 10)
    }
}
