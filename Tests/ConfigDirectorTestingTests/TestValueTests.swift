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
