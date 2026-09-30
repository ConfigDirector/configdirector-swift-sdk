@testable import ConfigDirector
import Foundation
import Testing

/// The in-memory connection encodes each value the way the ConfigDirector backend serves it.
struct InMemoryValueEncodingTests {
    private func encoded(_ value: InMemoryValue) -> ConfigState {
        value.configState(key: "k")
    }

    @Test func aBooleanIsABooleanConfig() {
        let state = encoded(.boolean(true))

        #expect(state.key == "k")
        #expect(state.type == .boolean)
        #expect(state.value == "true")
        #expect(state.valueID == ValueID.make(for: "true"))
        #expect(state.id.isEmpty == false)
    }

    @Test func anIntegerIsAnIntegerConfig() {
        #expect(encoded(.integer(20)).type == .integer)
        #expect(encoded(.integer(20)).value == "20")
        #expect(encoded(.integer(-3_000_000_000)).value == "-3000000000")
    }

    @Test func aFloatIsAFloatConfigWrittenInPlainNotation() {
        #expect(encoded(.float(2.5)).type == .float)
        #expect(encoded(.float(2.5)).value == "2.5")
        #expect(encoded(.float(2.0)).value == "2.0")
        #expect(encoded(.float(1e21)).value == "1000000000000000000000")
        #expect(encoded(.float(-2.5e20)).value == "-250000000000000000000")
        #expect(encoded(.float(1e-7)).value == "0.0000001")
        #expect(encoded(.float(1.5e-5)).value == "0.000015")
        #expect(encoded(.float(0.1)).value == "0.1")
    }

    @Test func aStringIsAStringConfigEvenWhenItSpellsJSON() {
        let state = encoded(.string(#"{"a":1}"#))

        #expect(state.type == .string)
        #expect(state.value == #"{"a":1}"#)
    }

    @Test func anObjectIsAJSONConfigWithSortedKeys() {
        let state = encoded(.object(["b": .integer(1), "a": .string("x"), "c": .boolean(false)]))

        #expect(state.type == .json)
        #expect(state.value == #"{"a":"x","b":1,"c":false}"#)
        #expect(state.valueID == ValueID.make(for: #"{"a":"x","b":1,"c":false}"#))
    }

    @Test func anArrayIsAJSONConfigInOrder() {
        let state = encoded(.array([.integer(1), .boolean(true), .string("s"), .float(2.5)]))

        #expect(state.type == .json)
        #expect(state.value == #"[1,true,"s",2.5]"#)
    }

    @Test func nestedDocumentsAreEncodedRecursively() {
        let state = encoded(.object([
            "theme": .object(["colors": .array([.string("blue"), .string("red")]), "radius": .float(1e21)]),
            "tags": .array([.object(["id": .integer(1)])]),
        ]))

        #expect(
            state.value
                == #"{"tags":[{"id":1}],"theme":{"colors":["blue","red"],"radius":1000000000000000000000}}"#
        )
    }

    @Test func stringsAreEscapedAsJSONRequiresAndNonASCIIIsKept() {
        let state = encoded(.array([.string("a\"b\\c\n\t\u{1}"), .string("héllo")]))

        #expect(state.value == #"["a\"b\\c\n\t\u0001","héllo"]"#)
    }
}
