import ConfigDirector
@testable import ConfigDirectorTesting
import Testing

struct TestValueTests {
    @Test func literalsBecomeTheMatchingCase() {
        let values: [String: TestValue] = [
            "flag": true,
            "count": 20,
            "ratio": 2.5,
            "name": "Ada",
            "settings": ["theme": "dark", "limit": 3],
            "tags": ["x", "y"],
        ]

        #expect(values["flag"] == .boolean(true))
        #expect(values["count"] == .integer(20))
        #expect(values["ratio"] == .float(2.5))
        #expect(values["name"] == .string("Ada"))
        #expect(values["settings"] == .object(["theme": .string("dark"), "limit": .integer(3)]))
        #expect(values["tags"] == .array([.string("x"), .string("y")]))
    }
}

struct TestValueConversionTests {
    @Test func eachCaseKeepsItsKindOnTheWayToTheConnection() {
        #expect(TestValue.boolean(true).inMemoryValue == .boolean(true))
        #expect(TestValue.integer(20).inMemoryValue == .integer(20))
        #expect(TestValue.float(2.5).inMemoryValue == .float(2.5))
        #expect(TestValue.string("Ada").inMemoryValue == .string("Ada"))
        #expect(TestValue.object(["limit": 3]).inMemoryValue == .object(["limit": .integer(3)]))
        #expect(TestValue.array([true, "x"]).inMemoryValue == .array([.boolean(true), .string("x")]))
    }
}
