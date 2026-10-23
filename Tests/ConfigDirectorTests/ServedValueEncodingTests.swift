@testable import ConfigDirector
import Foundation
import Testing

struct ServedValueEncodingTests {
    private func encoded(_ value: ServedValue) throws(ConfigDirectorError) -> ConfigState {
        try value.configState(key: "k")
    }

    @Test func aBooleanIsABooleanConfig() throws {
        let state = try encoded(.boolean(true))

        #expect(state.key == "k")
        #expect(state.type == .boolean)
        #expect(state.value == "true")
        #expect(state.valueID == ValueID.make(for: "true"))
        #expect(state.id.isEmpty == false)
    }

    @Test func anIntegerIsAnIntegerConfig() throws {
        #expect(try encoded(.integer(20)).type == .integer)
        #expect(try encoded(.integer(20)).value == "20")
        #expect(try encoded(.integer(-3_000_000_000)).value == "-3000000000")
    }

    @Test func aFloatIsAFloatConfigWrittenInPlainNotation() throws {
        #expect(try encoded(.float(2.5)).type == .float)
        #expect(try encoded(.float(2.5)).value == "2.5")
        #expect(try encoded(.float(2.0)).value == "2.0")
        #expect(try encoded(.float(1e21)).value == "1000000000000000000000")
        #expect(try encoded(.float(-2.5e20)).value == "-250000000000000000000")
        #expect(try encoded(.float(1e-7)).value == "0.0000001")
        #expect(try encoded(.float(1.5e-5)).value == "0.000015")
        #expect(try encoded(.float(0.1)).value == "0.1")
    }

    @Test func aStringIsAStringConfigEvenWhenItSpellsJSON() throws {
        let state = try encoded(.string(#"{"a":1}"#))

        #expect(state.type == .string)
        #expect(state.value == #"{"a":1}"#)
    }

    @Test func anObjectIsAJSONConfigWithSortedKeys() throws {
        let state = try encoded(.object(["b": .integer(1), "a": .string("x"), "c": .boolean(false)]))

        #expect(state.type == .json)
        #expect(state.value == #"{"a":"x","b":1,"c":false}"#)
        #expect(state.valueID == ValueID.make(for: #"{"a":"x","b":1,"c":false}"#))
    }

    @Test func anArrayIsAJSONConfigInOrder() throws {
        let state = try encoded(.array([.integer(1), .boolean(true), .string("s"), .float(2.5)]))

        #expect(state.type == .json)
        #expect(state.value == #"[1,true,"s",2.5]"#)
    }

    @Test func nestedDocumentsAreEncodedRecursively() throws {
        let state = try encoded(.object([
            "theme": .object(["colors": .array([.string("blue"), .string("red")]), "radius": .float(1e21)]),
            "tags": .array([.object(["id": .integer(1)])]),
        ]))

        #expect(
            state.value
                == #"{"tags":[{"id":1}],"theme":{"colors":["blue","red"],"radius":1000000000000000000000}}"#
        )
    }

    @Test func stringsAreEscapedAsJSONRequiresAndNonASCIIIsKept() throws {
        let state = try encoded(.array([.string("a\"b\\c\n\t\u{1}"), .string("héllo")]))

        #expect(state.value == #"["a\"b\\c\n\t\u0001","héllo"]"#)
    }
}
