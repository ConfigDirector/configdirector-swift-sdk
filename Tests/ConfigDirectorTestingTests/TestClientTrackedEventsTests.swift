import ConfigDirector
import ConfigDirectorTesting
import Foundation
import Testing

private let userA = ConfigDirectorContext(id: "user-a")
private let userB = ConfigDirectorContext(id: "user-b")

struct TestClientTrackedEventsTests {
    private let fixture = TestClientFixture()

    @Test func recordsTrackedEventsInCallOrderWithTheirValueAndDetails() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        await testClient.client.initialize(context: userA)

        testClient.client.track("added-to-cart", options: TrackOptions(value: 3))
        testClient.client.track(
            "checkout-completed",
            options: TrackOptions(value: 49.9, details: ["plan": "pro"])
        )

        #expect(testClient.trackedEvents == [
            TrackedEvent(name: "added-to-cart", context: userA, value: 3),
            TrackedEvent(name: "checkout-completed", context: userA, value: 49.9, details: ["plan": "pro"]),
        ])
    }

    @Test func recordsTheContextTheClientHadAtEachCall() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize(context: userA)

        client.track("before-the-update")
        await client.updateContext(userB)
        client.track("after-the-update")

        #expect(testClient.trackedEvents == [
            TrackedEvent(name: "before-the-update", context: userA),
            TrackedEvent(name: "after-the-update", context: userB),
        ])
    }

    @Test func recordsAnEventTrackedBeforeTheClientHasAContextWithoutOne() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        testClient.client.track("app-opened")

        #expect(testClient.trackedEvents == [TrackedEvent(name: "app-opened")])
        #expect(fixture.logger.warnings.isEmpty)
    }

    @Test func recordsAnAnonymousContextAsItWasGiven() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        let anonymous = ConfigDirectorContext(id: "user-a", isAnonymous: true)
        await testClient.client.initialize(context: anonymous)

        testClient.client.track("app-opened")

        #expect(testClient.trackedEvents == [TrackedEvent(name: "app-opened", context: anonymous)])
    }

    @Test func doesNotRecordAnEventWhoseNameTheSDKWouldNotReportAndWarnsEachTime() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        testClient.client.track("")
        testClient.client.track(String(repeating: "n", count: 151))

        #expect(testClient.trackedEvents.isEmpty)
        #expect(fixture.logger.warnings.count == 2)
    }

    @Test func leavesOutOfTheRecordAValueTheSDKWouldLeaveOutAndWarns() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        testClient.client.track("checkout-completed", options: TrackOptions(value: .double(.nan)))

        #expect(testClient.trackedEvents == [TrackedEvent(name: "checkout-completed")])
        #expect(fixture.logger.warnings.count == 1)
    }

    @Test func leavesOutOfTheRecordDetailsTheSDKWouldLeaveOutAndWarns() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        let oversizedNote = String(repeating: "a", count: 1014)

        testClient.client.track(
            "checkout-completed",
            options: TrackOptions(details: ["note": .string(oversizedNote)])
        )

        #expect(testClient.trackedEvents == [TrackedEvent(name: "checkout-completed")])
        #expect(fixture.logger.warnings.count == 1)
    }

    @Test func recordsADateInDetailsAsTheTextTheSDKSends() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        testClient.client.track(
            "trial-started",
            options: TrackOptions(details: ["at": .date(Date(timeIntervalSince1970: 1_800_000_000.25))])
        )

        #expect(testClient.trackedEvents == [
            TrackedEvent(name: "trial-started", details: ["at": "2027-01-15T08:00:00.250Z"]),
        ])
    }

    @Test func recordsADateNestedInDetailsAsTheTextTheSDKSends() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        testClient.client.track(
            "trial-started",
            options: TrackOptions(details: [
                "trial": ["at": .date(Date(timeIntervalSince1970: 1_800_000_000.25))],
            ])
        )

        #expect(testClient.trackedEvents == [
            TrackedEvent(name: "trial-started", details: ["trial": ["at": "2027-01-15T08:00:00.250Z"]]),
        ])
    }

    @Test func recordsANumberInDetailsThatIsNotFiniteAsTheNullTheSDKSends() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        testClient.client.track(
            "checkout-completed",
            options: TrackOptions(details: ["ratios": [.double(.nan), .double(.infinity), 0.5]])
        )

        #expect(testClient.trackedEvents == [
            TrackedEvent(name: "checkout-completed", details: ["ratios": [nil, nil, 0.5]]),
        ])
        #expect(fixture.logger.warnings.isEmpty)
    }

    @Test func recordsBeyondTheLimitOfATelemetryBatch() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }

        for index in 0 ..< 1001 {
            testClient.client.track("event-\(index)")
        }

        #expect(testClient.trackedEvents.count == 1001)
        #expect(fixture.logger.warnings.isEmpty)
    }

    @Test func aSharedTestClientClearsTheRecordAndKeepsRecording() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        testClient.client.track("first-test")

        testClient.trackedEvents.removeAll()
        testClient.client.track("second-test")

        #expect(testClient.trackedEvents == [TrackedEvent(name: "second-test")])
    }

    @Test func replaceValuesLeavesTheRecordAlone() {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        testClient.client.track("app-opened")

        testClient.replaceValues(["new-checkout": true])

        #expect(testClient.trackedEvents == [TrackedEvent(name: "app-opened")])
    }

    @Test func eachTestClientKeepsItsOwnRecord() {
        let first = fixture.makeTestClient()
        defer { first.client.close() }
        let second = fixture.makeTestClient()
        defer { second.client.close() }

        first.client.track("first-client")
        second.client.track("second-client")

        #expect(first.trackedEvents == [TrackedEvent(name: "first-client")])
        #expect(second.trackedEvents == [TrackedEvent(name: "second-client")])
    }
}
