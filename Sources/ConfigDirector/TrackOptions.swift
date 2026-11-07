import Foundation

/// What a tracked event carries besides its name.
///
/// ```swift
/// client.track(
///     "checkout-completed",
///     options: TrackOptions(value: 49.9, details: ["plan": "pro"])
/// )
/// ```
public struct TrackOptions: Sendable {
    /// A number the event measures, such as an amount of money, a count or a duration. A value that
    /// is not a finite number is left out and the event is still reported.
    public var value: TrackedEventValue?

    /// Details of the event. Details with more than 20 top-level keys, or larger than 1 KB as JSON,
    /// are left out and the event is still reported.
    public var details: TrackedEventDetails?

    public init(value: TrackedEventValue? = nil, details: TrackedEventDetails? = nil) {
        self.value = value
        self.details = details
    }
}

/// A number a tracked event measures. ConfigDirector stores it as an exact decimal, so it is sent as
/// written, without rounding it.
///
/// A literal is enough for a fixed number. A variable names its case:
///
/// ```swift
/// TrackOptions(value: 3)
/// TrackOptions(value: 49.9)
/// TrackOptions(value: .double(duration))
/// TrackOptions(value: .decimal(order.total))
/// ```
public enum TrackedEventValue: Sendable, Equatable {
    case int(Int)
    case double(Double)

    /// A number sent with every digit it holds, the choice for an amount of money.
    case decimal(Decimal)
}

extension TrackedEventValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension TrackedEventValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension TrackedEventValue: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .decimal(value): try container.encode(value)
        }
    }
}

/// Details of a tracked event, such as the plan a customer chose. Details with more than 20
/// top-level keys, or larger than 1 KB as JSON, are left out and the event is still reported.
public typealias TrackedEventDetails = [String: TrackedEventDetailValue]

/// A value in the details of a tracked event.
///
/// Values are usually written as literals rather than spelled out:
///
/// ```swift
/// let details: TrackedEventDetails = [
///     "plan": "pro",
///     "seats": 12,
///     "trial": true,
///     "regions": ["us-east", "eu-west"],
///     "startedAt": .date(subscription.startDate),
/// ]
/// ```
public enum TrackedEventDetailValue: Sendable, Equatable {
    case string(String)
    case int(Int)

    /// A value that is not finite, such as `.nan` or `.infinity`, has no JSON form and is sent as
    /// `null`.
    case double(Double)
    case bool(Bool)

    /// A date, sent as ISO 8601 text.
    case date(Date)
    case array([TrackedEventDetailValue])
    case dictionary([String: TrackedEventDetailValue])
    case null
}

extension TrackedEventDetailValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension TrackedEventDetailValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension TrackedEventDetailValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension TrackedEventDetailValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension TrackedEventDetailValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: TrackedEventDetailValue...) {
        self = .array(elements)
    }
}

extension TrackedEventDetailValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, TrackedEventDetailValue)...) {
        self = .dictionary(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension TrackedEventDetailValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null
    }
}

extension TrackedEventDetailValue: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value) where value.isFinite: try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .dictionary(values): try container.encode(values)
        case .double, .date: try container.encode(asSent)
        case .null: try container.encodeNil()
        }
    }
}

extension TrackedEventDetailValue {
    var asSent: TrackedEventDetailValue {
        switch self {
        case let .double(value) where !value.isFinite: .null
        case let .date(value): .string(value.telemetryTimestamp)
        case let .array(values): .array(values.map(\.asSent))
        case let .dictionary(values): .dictionary(values.mapValues(\.asSent))
        case .string, .int, .double, .bool, .null: self
        }
    }
}
