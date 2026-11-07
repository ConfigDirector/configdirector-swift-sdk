@testable import ConfigDirector
import Foundation
import Testing

extension ConfigValueParserTests {
    struct JSONDocuments {
        private let fallback = Theme(primaryColor: "red", cornerRadius: 0)

        @Test func areDecodedIntoTheRequestedType() {
            let result = ConfigValueParser.parseJSON(
                .make(
                    key: "theme",
                    type: .json,
                    value: #"{"primaryColor":"blue","cornerRadius":8}"#,
                    valueID: "blue"
                ),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == Theme(primaryColor: "blue", cornerRadius: 8))
            #expect(result.valueID == "blue")
            #expect(result.usedDefault == false)
            #expect(result.reason == .foundMatch)
        }

        @Test func fallBackAsInvalidJSONWhenTheDocumentIsMalformed() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: .json, value: "not json at all", valueID: "broken"),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.valueID == nil)
            #expect(result.reason == .invalidJSON)
        }

        @Test func fallBackAsATypeMismatchWhenADocumentLacksAField() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: .json, value: #"{"primaryColor":"blue"}"#, valueID: "partial"),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.valueID == nil)
            #expect(result.reason == .typeMismatch)
        }

        @Test func fallBackAsATypeMismatchWhenAFieldHoldsAnotherType() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: .json, value: #"{"primaryColor":"blue","cornerRadius":"eight"}"#),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.reason == .typeMismatch)
        }

        @Test func fallBackAsATypeMismatchWhenANumberDoesNotFitItsField() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: .json, value: #"{"primaryColor":"blue","cornerRadius":8.5}"#),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.reason == .typeMismatch)
        }

        @Test func fallBackAsATypeMismatchWhenAFieldHoldsAValueItsEnumDoesNotList() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "layout", type: .json, value: #"{"density":"spacious"}"#),
                as: Layout.self,
                default: Layout(density: .compact)
            )

            #expect(result.value == Layout(density: .compact))
            #expect(result.usedDefault)
            #expect(result.reason == .typeMismatch)
        }

        @Test func fallBackAsATypeMismatchWhenTheDocumentIsAnArray() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: .json, value: "[1, 2, 3]"),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.reason == .typeMismatch)
        }

        @Test func fallBackAsATypeMismatchWhenTheDocumentIsNull() {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: .json, value: "null"),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.reason == .typeMismatch)
        }

        @Test(arguments: ConfigType.allCases.filter { $0 != .json })
        func areOnlyDecodedFromJSONConfigs(_ type: ConfigType) {
            let result = ConfigValueParser.parseJSON(
                .make(key: "theme", type: type, value: #"{"primaryColor":"blue","cornerRadius":8}"#),
                as: Theme.self,
                default: fallback
            )

            #expect(result.value == fallback)
            #expect(result.usedDefault)
            #expect(result.reason == .typeMismatch)
        }
    }
}

private struct Layout: Decodable, Equatable {
    enum Density: String, Decodable {
        case compact
    }

    var density: Density
}
