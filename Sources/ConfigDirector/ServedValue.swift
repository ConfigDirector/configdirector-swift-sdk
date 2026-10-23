/// A config value the client serves as it was given, to every context: an offline value in
/// ``ConnectionOptions/values``, or a value a test client serves. The config type follows from the
/// case: a boolean, integer, float, or string config, or a JSON config for an object or an array.
///
/// Values are usually written as literals rather than spelled out:
///
/// ```swift
/// let values: [String: ServedValue] = [
///     "new-checkout": true,
///     "max-items": 20,
///     "discount": 0.15,
///     "greeting": "hello",
///     "theme": ["color": "blue", "radius": 8],
///     "tags": ["a", "b"],
/// ]
/// ```
///
/// A string is always a string config, so JSON text meant as a JSON config is given as an
/// ``object(_:)`` or an ``array(_:)``. There is no null case: leave the key out instead.
public enum ServedValue: Sendable, Equatable {
    /// A boolean config.
    case boolean(Bool)

    /// An integer config.
    case integer(Int)

    /// A float config. The number must be finite.
    case float(Double)

    /// A string config.
    case string(String)

    /// A JSON config holding an object. Keys are encoded in sorted order.
    case object([String: ServedValue])

    /// A JSON config holding an array.
    case array([ServedValue])
}

extension ServedValue: ExpressibleByBooleanLiteral {
    /// `true` and `false` are ``boolean(_:)`` configs.
    public init(booleanLiteral value: Bool) {
        self = .boolean(value)
    }
}

extension ServedValue: ExpressibleByIntegerLiteral {
    /// A whole number literal is an ``integer(_:)`` config.
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension ServedValue: ExpressibleByFloatLiteral {
    /// A decimal literal is a ``float(_:)`` config.
    public init(floatLiteral value: Double) {
        self = .float(value)
    }
}

extension ServedValue: ExpressibleByStringLiteral {
    /// A string literal is a ``string(_:)`` config.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension ServedValue: ExpressibleByDictionaryLiteral {
    /// A dictionary literal is an ``object(_:)`` config.
    public init(dictionaryLiteral elements: (String, ServedValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension ServedValue: ExpressibleByArrayLiteral {
    /// An array literal is an ``array(_:)`` config.
    public init(arrayLiteral elements: ServedValue...) {
        self = .array(elements)
    }
}
