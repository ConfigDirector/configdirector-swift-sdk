import ConfigDirector
import ConfigDirectorTesting
import Foundation
import Testing

private let userA = ConfigDirectorContext(id: "user-a")
private let userB = ConfigDirectorContext(id: "user-b")

/// The values a test client serves, from the conformance scenarios of the testing contract.
struct TestClientValueTests {
    private let fixture = TestClientFixture()

    @Test func startsUninitializedWithNoValues() async {
        let testClient = makeTestClient()
        defer { testClient.client.close() }
        #expect(testClient.client.isReady == false)
        #expect(testClient.client.isInitializing == false)

        await testClient.client.initialize()

        #expect(testClient.client.isReady)
        #expect(testClient.client.value(for: "flag", default: true) == true)
    }

    @Test func s1ReadsEverySeededValueWithAMatchingAccessor() async {
        let testClient = fixture.makeTestClient(values: [
            "flag": true,
            "count": 20,
            "big": 3_000_000_000,
            "ratio": 2.5,
            "name": "Ada",
            "settings": ["theme": "dark", "limit": 3],
            "tags": ["x", "y"],
        ])
        defer { testClient.client.close() }
        let client = testClient.client

        await client.initialize()

        #expect(client.isReady)
        #expect(client.value(for: "flag", default: false) == true)
        #expect(client.value(for: "count", default: 0) == 20)
        #expect(client.value(for: "big", default: 0) == 3_000_000_000)
        #expect(client.value(for: "ratio", default: 0.0) == 2.5)
        #expect(client.value(for: "name", default: "") == "Ada")
        let settings = client.value(
            for: "settings",
            as: Settings.self,
            default: Settings(theme: "", limit: 0)
        )
        #expect(settings == Settings(theme: "dark", limit: 3))
        #expect(client.value(for: "tags", as: [String].self, default: []) == ["x", "y"])
    }

    @Test func s2ABooleanReadAsAStringIsATypeMismatch() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        await testClient.client.initialize()
        let evaluations = StreamReader(testClient.client.evaluations)

        #expect(testClient.client.value(for: "flag", default: "fallback") == "fallback")

        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.isDefaultValue)
        #expect(evaluation.reason == .typeMismatch)
    }

    @Test func s3SetValueOnAConnectedClientChangesTheNextRead() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        await testClient.client.initialize()

        testClient.setValue(false, for: "flag")

        #expect(testClient.client.value(for: "flag", default: true) == false)
    }

    @Test func s8SetValueBeforeInitializeIsDeliveredByInitialize() async {
        let testClient = fixture.makeTestClient()
        defer { testClient.client.close() }
        testClient.setValue(7, for: "count")

        await testClient.client.initialize()

        #expect(testClient.client.value(for: "count", default: 0) == 7)
    }

    @Test func s6RemoveValueOnAConnectedClientReadsAsTheDefault() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        await testClient.client.initialize()
        let evaluations = StreamReader(testClient.client.evaluations)

        testClient.removeValue(for: "flag")

        #expect(testClient.client.value(for: "flag", default: false) == false)
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .configStateMissing)
    }

    @Test func s24RemoveValueBeforeInitializeReadsAsTheDefault() async throws {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        testClient.removeValue(for: "flag")

        await testClient.client.initialize()

        let evaluations = StreamReader(testClient.client.evaluations)
        #expect(testClient.client.value(for: "flag", default: false) == false)
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .configStateMissing)
    }

    @Test func s32ReplaceValuesServesExactlyTheNewValues() async throws {
        let testClient = fixture.makeTestClient(values: ["a": 1, "b": 2])
        defer { testClient.client.close() }
        let client = testClient.client
        await client.initialize()
        let bValues = StreamReader(client.values(for: "b", default: 0))
        #expect(await bValues.next() == 2)

        testClient.replaceValues(["a": 10, "c": 30])

        #expect(client.value(for: "a", default: 0) == 10)
        #expect(client.value(for: "c", default: 0) == 30)
        #expect(await bValues.next() == 0)
        let evaluations = StreamReader(client.evaluations)
        #expect(client.value(for: "b", default: 0) == 0)
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .configStateMissing)
    }

    @Test func s15TwoTestClientsNeverShareValues() async {
        let first = fixture.makeTestClient(values: ["flag": true])
        let second = fixture.makeTestClient(values: ["flag": false, "only-second": 1])
        defer {
            first.client.close()
            second.client.close()
        }
        await first.client.initialize()
        await second.client.initialize()

        first.setValue(false, for: "flag")
        second.setValue(2, for: "only-second")

        #expect(first.client.value(for: "flag", default: true) == false)
        #expect(second.client.value(for: "flag", default: true) == false)
        #expect(first.client.value(for: "only-second", default: 0) == 0)
        #expect(second.client.value(for: "only-second", default: 0) == 2)
    }

    @Test func servesTheSameValueToEveryContext() async {
        let testClient = fixture.makeTestClient(values: ["flag": true])
        defer { testClient.client.close() }
        await testClient.client.initialize(context: userA)
        #expect(testClient.client.value(for: "flag", default: false) == true)

        await testClient.client.updateContext(userB)

        #expect(testClient.client.value(for: "flag", default: false) == true)
        #expect(testClient.client.context == userB)
    }

    @Test func aStringSpellingJSONIsAStringConfig() async throws {
        let testClient = fixture.makeTestClient(values: ["doc": #"{"a":1}"#])
        defer { testClient.client.close() }
        await testClient.client.initialize()

        #expect(testClient.client.value(for: "doc", default: "") == #"{"a":1}"#)
        let evaluations = StreamReader(testClient.client.evaluations)
        #expect(testClient.client.value(for: "doc", as: [String: Int].self, default: [:]) == [:])
        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .typeMismatch)
    }

    @Test func anEmptyStringServesTheDefaultWithValueMissing() async throws {
        let testClient = fixture.makeTestClient(values: ["name": ""])
        defer { testClient.client.close() }
        await testClient.client.initialize()
        let evaluations = StreamReader(testClient.client.evaluations)

        #expect(testClient.client.value(for: "name", default: "fallback") == "fallback")

        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .valueMissing)
    }

    @Test func aFloatReadAsAnIntIsTruncatedAsInProduction() async throws {
        let testClient = fixture.makeTestClient(values: ["ratio": 2.5])
        defer { testClient.client.close() }
        await testClient.client.initialize()
        let evaluations = StreamReader(testClient.client.evaluations)

        #expect(testClient.client.value(for: "ratio", default: 1) == 2)

        let evaluation = try #require(await evaluations.next())
        #expect(evaluation.reason == .foundMatch)
    }

    @Test func trapsOnABlankKey() async {
        await #expect(processExitsWith: .failure) {
            _ = makeTestClient(values: [" ": true])
        }
    }

    @Test func trapsOnANumberThatIsNotFinite() async {
        await #expect(processExitsWith: .failure) {
            let testClient = makeTestClient()
            testClient.setValue(.float(.nan), for: "ratio")
        }
    }
}

private struct Settings: Codable, Equatable {
    var theme: String
    var limit: Int
}
