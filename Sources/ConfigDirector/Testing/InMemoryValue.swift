import Foundation

package enum InMemoryValue: Sendable, Equatable {
    case boolean(Bool)
    case integer(Int)
    case float(Double)
    case string(String)
    case object([String: InMemoryValue])
    case array([InMemoryValue])
}

extension InMemoryValue {
    func configState(key: String) -> ConfigState {
        let (type, text) = encoded
        return ConfigState(
            id: UUID().uuidString,
            key: key,
            type: type,
            value: text,
            valueID: ValueID.make(for: text)
        )
    }

    private var encoded: (ConfigType, String) {
        switch self {
        case let .boolean(value): (.boolean, value ? "true" : "false")
        case let .integer(value): (.integer, String(value))
        case let .float(value): (.float, Self.plainDecimal(value))
        case let .string(value): (.string, value)
        case .object, .array: (.json, json)
        }
    }

    private var json: String {
        var text = ""
        writeJSON(into: &text)
        return text
    }

    private func writeJSON(into text: inout String) {
        switch self {
        case let .boolean(value):
            text += value ? "true" : "false"
        case let .integer(value):
            text += String(value)
        case let .float(value):
            text += Self.plainDecimal(value)
        case let .string(value):
            Self.writeJSONString(value, into: &text)
        case let .object(members):
            text += "{"
            for (index, key) in members.keys.sorted().enumerated() {
                if index > 0 {
                    text += ","
                }
                Self.writeJSONString(key, into: &text)
                text += ":"
                members[key]?.writeJSON(into: &text)
            }
            text += "}"
        case let .array(elements):
            text += "["
            for (index, element) in elements.enumerated() {
                if index > 0 {
                    text += ","
                }
                element.writeJSON(into: &text)
            }
            text += "]"
        }
    }

    private static func writeJSONString(_ value: String, into text: inout String) {
        text += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{8}": text += "\\b"
            case "\u{C}": text += "\\f"
            case ..<" ":
                let hex = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }

    /// Swift writes large and small doubles with an exponent; ConfigDirector serves plain decimals.
    static func plainDecimal(_ value: Double) -> String {
        precondition(value.isFinite, "A test value must be a finite number, not \(value).")
        let text = "\(value)"
        guard let exponentMarker = text.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return text }

        let mantissa = text[..<exponentMarker]
        let exponentText = text[text.index(after: exponentMarker)...].replacingOccurrences(of: "+", with: "")
        let exponent = Int(exponentText) ?? 0
        let sign = mantissa.hasPrefix("-") ? "-" : ""
        let unsigned = mantissa.drop(while: { $0 == "-" })
        let digits = unsigned.filter { $0 != "." }
        let integerDigits = unsigned.firstIndex(of: ".").map { unsigned.distance(
            from: unsigned.startIndex,
            to: $0
        ) }
        let pointPosition = (integerDigits ?? unsigned.count) + exponent

        if pointPosition <= 0 {
            return sign + "0." + String(repeating: "0", count: -pointPosition) + digits
        }
        if pointPosition >= digits.count {
            return sign + digits + String(repeating: "0", count: pointPosition - digits.count)
        }
        let splitIndex = digits.index(digits.startIndex, offsetBy: pointPosition)
        return sign + digits[..<splitIndex] + "." + digits[splitIndex...]
    }
}
