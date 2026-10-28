import Foundation

public extension ConfigDirectorClient {
    /// Evaluates `key` against the current context and targeting rules.
    ///
    /// Returns `defaultValue` when config state is unavailable — for instance when called before
    /// initialization completes, or when the served value cannot be represented as `Value`.
    func value<Value: ConfigValue>(for key: String, default defaultValue: Value) -> Value {
        store.evaluate(key, default: defaultValue).value
    }

    /// Evaluates a JSON config, decoding it into `type`.
    ///
    /// Returns `defaultValue` when config state is unavailable, when the config is not a JSON config,
    /// or when its document cannot be decoded into `type`.
    ///
    /// ```swift
    /// let theme = client.value(for: "theme", as: Theme.self, default: .fallback)
    /// ```
    func value<Value: Decodable & Sendable>(
        for key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> Value {
        store.evaluate(key, as: type, default: defaultValue).value
    }

    /// Evaluates `key` the way ``value(for:default:)`` does, and returns the evaluation along with
    /// the value.
    ///
    /// The returned `value` is what ``value(for:default:)`` returns, so it is `defaultValue` whenever
    /// the config could not be served as `Value`, and the evaluation's ``ConfigEvaluation/reason``
    /// says why. Use this where the reason matters at the point of the read; ``value(for:default:)``
    /// is enough everywhere else. Like every read, it publishes the evaluation on ``evaluations`` and
    /// reports it in telemetry.
    ///
    /// ```swift
    /// let (darkMode, evaluation) = client.evaluate("dark-mode", default: false)
    /// if evaluation.isDefaultValue {
    ///     logger.notice("'dark-mode' fell back: \(evaluation.reason.rawValue)")
    /// }
    /// ```
    func evaluate<Value: ConfigValue>(
        _ key: String,
        default defaultValue: Value
    ) -> (value: Value, evaluation: ConfigEvaluation) {
        store.evaluate(key, default: defaultValue)
    }

    /// Evaluates a JSON config the way ``value(for:as:default:)`` does, and returns the evaluation
    /// along with the decoded value.
    ///
    /// ```swift
    /// let (theme, evaluation) = client.evaluate("theme", as: Theme.self, default: .fallback)
    /// ```
    func evaluate<Value: Decodable & Sendable>(
        _ key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> (value: Value, evaluation: ConfigEvaluation) {
        store.evaluate(key, as: type, default: defaultValue)
    }

    /// Watches `key` for changes, which can come from an update in the ConfigDirector dashboard or
    /// from a call to ``updateContext(_:)``.
    ///
    /// The stream yields the config's current value immediately and then every time the evaluated
    /// value changes. Consecutive identical values are not re-emitted. When a full update no longer
    /// carries `key`, the stream yields `defaultValue`, as ``value(for:default:)`` would now return
    /// it. Cancelling the consuming task stops watching.
    ///
    /// ```swift
    /// .task {
    ///     for await darkMode in client.values(for: "dark-mode", default: false) {
    ///         self.darkMode = darkMode
    ///     }
    /// }
    /// ```
    func values<Value: ConfigValue>(
        for key: String,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        store.values(for: key, default: defaultValue)
    }

    /// Watches a JSON config for changes, decoding each value into `type`.
    func values<Value: Decodable & Sendable & Equatable>(
        for key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        store.values(for: key, as: type, default: defaultValue)
    }
}
