import Foundation

/// Why a config evaluated to the value it did.
public enum EvaluationReason: String, Sendable {
    /// The config state was found and its value matched the requested type.
    case foundMatch = "found-match"

    /// The value was served from the values kept on the device from an earlier launch, before
    /// live values arrived. It is not an in-code default value.
    case cached

    /// No state was received for the config key.
    case configStateMissing = "config-state-missing"

    /// The client had not received config state yet.
    case clientNotReady = "client-not-ready"

    /// The config's type is incompatible with the requested type, or its JSON document does not
    /// decode into that type.
    case typeMismatch = "type-mismatch"

    /// The config has no value for the current context.
    case valueMissing = "value-missing"

    /// The config value could not be parsed as a number.
    case invalidNumber = "invalid-number"

    /// The config value could not be parsed as JSON.
    case invalidJSON = "invalid-json"

    /// The config value could not be parsed as a boolean.
    case invalidBoolean = "invalid-boolean"

    /// A server SDK skipped a percentage rollout because the context has no identifier to place it
    /// in a share, and returned the default targeting rule value. This SDK never returns it: a
    /// context without an identifier gets one derived from an ID the SDK stores for the app install.
    case rolloutSkippedNoIdentifier = "rollout-skipped-no-identifier"
}

/// One of the values a config can serve, such as the control or a treatment of an experiment.
public struct Variation: Sendable, Equatable {
    /// The ID ConfigDirector assigned to the variation, which stays the same when it is renamed.
    public let id: String

    /// The variation's name, or `nil` when it has none.
    public let name: String?

    /// Creates a variation with `id` and, when it has one, `name`.
    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

/// The value a config evaluated to.
///
/// It holds the value as the type the config was read as, which ``as(_:)`` hands back, alongside a
/// textual form for logging. Two values are equal when their textual forms match.
public struct ConfigEvaluationValue: Sendable, Equatable, CustomStringConvertible {
    /// A textual form of the value, the same one the SDK reports in telemetry.
    public let description: String

    private let value: any Sendable

    init(_ value: some Sendable) {
        self.value = value
        description = String(describing: value)
    }

    /// The value as `type`, or `nil` when the config was evaluated as a different type.
    ///
    /// ```swift
    /// for await evaluation in client.evaluations {
    ///     if let isOn = evaluation.value.as(Bool.self) {
    ///         logger.debug("'\(evaluation.key)' is \(isOn)")
    ///     }
    /// }
    /// ```
    public func `as`<Value: Sendable>(_ type: Value.Type) -> Value? {
        value as? Value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.description == rhs.description
    }
}

/// The outcome of evaluating a single config.
public struct ConfigEvaluation: Sendable, Equatable {
    /// The key of the config that was evaluated.
    public let key: String

    /// The value the config evaluated to, which is the in-code default value supplied by the caller
    /// when ``isDefaultValue`` is `true`.
    public let value: ConfigEvaluationValue

    /// Identifies the specific config value that was served, for telemetry. It is `nil` when the
    /// in-code default value was returned.
    public let valueID: String?

    /// The variation that was served. It is `nil` when the config has no variations or the in-code
    /// default value is returned.
    public let variation: Variation?

    /// Whether the in-code default value provided by the caller was returned.
    public let isDefaultValue: Bool

    /// Why the config evaluated to ``value``.
    public let reason: EvaluationReason

    /// The context the config was evaluated against, if one was set.
    public let context: ConfigDirectorContext?
}
