import Foundation

enum ConfigSetSource {
    case noConfigSet
    case cachedValues
    case livePayload
}

final class ConfigStore: Sendable {
    let events = Broadcaster<ClientEvent>()

    /// Kept apart from ``events``: an evaluation is published for every config read, which in a
    /// SwiftUI body means many per frame, and a burst of them must not push a subscriber's buffer
    /// past a ``ClientEvent/ready(_:)`` it has not consumed yet.
    let evaluations = Broadcaster<ConfigEvaluation>()

    private struct State {
        var configs: [String: ConfigState] = [:]
        var configSetSource = ConfigSetSource.noConfigSet
        var hasStartedCachedValuesAdoption = false
        var context: ConfigDirectorContext?
        var isReady = false
        var isClosed = false
        var pendingReason: ConnectReason = .initialization
        var pendingContext: ConfigDirectorContext?
        var hasPendingContext = false
        var readyWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let logger: any ConfigDirectorLogger
    private let telemetry: any TelemetryClient
    private let caching: CachingPlan
    private let watchers = ConfigWatchers()
    private let state = Locked(State())

    init(logger: any ConfigDirectorLogger, telemetry: any TelemetryClient, caching: CachingPlan) {
        self.logger = logger
        self.telemetry = telemetry
        self.caching = caching
    }

    var hasReceivedConfigSet: Bool {
        state.withLock { $0.configSetSource == .livePayload }
    }

    var isReady: Bool {
        state.withLock { $0.isReady }
    }

    var context: ConfigDirectorContext? {
        state.withLock { $0.context }
    }

    func beginConnect(
        reason: ConnectReason,
        suppliedContext: ConfigDirectorContext?
    ) -> ConfigDirectorContext? {
        let context = contextToConnectWith(suppliedContext, reason: reason)
        state.withLock {
            $0.isReady = false
            $0.pendingReason = reason
            $0.pendingContext = context
            $0.hasPendingContext = true
        }
        if reason == .initialization {
            adoptCachedValuesOnce(launchContext: context)
        }
        return context
    }

    func abandonConnect() {
        state.withLock {
            $0.pendingContext = nil
            $0.hasPendingContext = false
        }
    }

    /// A pending context takes effect when the transport connects with it or when the first config
    /// state evaluated against it arrives, whichever happens first.
    func applyPendingContext() {
        let (didApply, context) = state.withLock { state -> (Bool, ConfigDirectorContext?) in
            guard state.hasPendingContext else { return (false, nil) }
            state.context = state.pendingContext
            state.pendingContext = nil
            state.hasPendingContext = false
            return (true, state.context)
        }
        guard didApply else { return }

        telemetry.updateContext(context)
        events.emit(.contextUpdated(context))
    }

    func markNotReady() {
        state.withLock { $0.isReady = false }
    }

    func waitUntilReady(timeout: TimeInterval) async {
        let id = UUID()
        let timeoutTask = Task { [weak self] in
            let slept: Void? = try? await Task.sleep(seconds: timeout)
            guard slept != nil else { return }
            self?.resumeReadyWaiter(id)
        }
        defer { timeoutTask.cancel() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let isSettled = state.withLock { state -> Bool in
                    guard !state.isReady, !state.isClosed, !Task.isCancelled else { return true }
                    state.readyWaiters[id] = continuation
                    return false
                }

                if isSettled {
                    continuation.resume()
                }
            }
        } onCancel: {
            resumeReadyWaiter(id)
        }
    }

    func applyReceivedConfigSet(_ configSet: ConfigSet) {
        let keys = Array(configSet.configs.keys)
        let merged = state.withLock { state -> MergedConfigSet in
            let holdsConfigs = state.configSetSource != .noConfigSet
            let isDelta = holdsConfigs && configSet.kind == .delta
            let replacesPrevious = holdsConfigs && !isDelta
            let removedKeys = replacesPrevious
                ? state.configs.keys.filter { configSet.configs[$0] == nil }
                : []
            if isDelta {
                state.configs.merge(configSet.configs) { _, updated in updated }
            } else {
                state.configs = configSet.configs
            }
            state.configSetSource = .livePayload
            return MergedConfigSet(isDelta: isDelta, removedKeys: removedKeys, configs: state.configs)
        }

        markReady()
        keepOnDevice(merged.configs, from: configSet)
        events.emit(.configsUpdated(ConfigsUpdate(keys: keys, removedKeys: merged.removedKeys)))
        if merged.isDelta {
            watchers.reevaluate(keys: keys)
        } else {
            watchers.reevaluateAll()
        }
        logger.debug("Config state received from the server: \(keys), removed: \(merged.removedKeys)")
    }

    func close() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isClosed = true
            state.isReady = false
            defer { state.readyWaiters.removeAll() }
            return Array(state.readyWaiters.values)
        }

        for waiter in waiters {
            waiter.resume()
        }
        watchers.finishAll()
        events.finish()
        evaluations.finish()
    }

    private func markReady() {
        applyPendingContext()

        let (waiters, reason) = state.withLock { state -> (
            [CheckedContinuation<Void, Never>],
            ConnectReason?
        ) in
            guard !state.isReady, !state.isClosed else { return ([], nil) }
            state.isReady = true
            let waiters = Array(state.readyWaiters.values)
            state.readyWaiters.removeAll()
            return (waiters, state.pendingReason)
        }

        guard let reason else { return }

        for waiter in waiters {
            waiter.resume()
        }
        events.emit(.ready(reason))
        logger.debug("Received config state from the server, the client is ready")
    }

    private func adoptCachedValuesOnce(launchContext: ConfigDirectorContext?) {
        guard case let .keepValues(store) = caching else { return }
        let isFirst = state.withLock { state -> Bool in
            defer { state.hasStartedCachedValuesAdoption = true }
            return !state.hasStartedCachedValuesAdoption
        }
        guard isFirst else { return }

        let launchContextTag = store.contextTag(for: launchContext)
        Task { [weak self] in
            switch await store.read() {
            case let .stored(cachedValues):
                self?.adopt(cachedValues, launchContextTag: launchContextTag)
            case .nothingStored, .firstFormatEntry, .notAnEntry, .storageFailed:
                break
            }
        }
    }

    private func adopt(_ cachedValues: CachedValues, launchContextTag: ContextTag) {
        let keys = Array(cachedValues.configs.keys)
        let adoption = state.withLock { state -> CachedValuesAdoption in
            let adoption = CachedValuesAdoption.decide(
                cachedValues,
                launchContextTag: launchContextTag,
                hasReceivedLiveValues: state.configSetSource == .livePayload,
                isClosed: state.isClosed
            )
            guard adoption == .adopt else { return adoption }
            state.configs = cachedValues.configs
            state.configSetSource = .cachedValues
            return adoption
        }

        switch adoption {
        case .adopt:
            events.emit(.cachedValuesLoaded)
            events.emit(.configsUpdated(ConfigsUpdate(keys: keys)))
            watchers.reevaluateAll()
            logger.debug("Serving the values kept on the device until live values arrive: \(keys)")
        case .liveValuesAlreadyArrived:
            logger.debug("The values kept on the device were not adopted: live values already arrived")
        case .contextMismatch:
            logger.debug("The values kept on the device were not adopted: the launch context differs")
        case .clientClosed:
            break
        }
    }

    private func keepOnDevice(_ configs: [String: ConfigState], from configSet: ConfigSet) {
        guard case let .keepValues(store) = caching else { return }
        let context = state.withLock { $0.context }

        store.replace(CachedValues(
            contextTag: store.contextTag(for: context),
            environmentID: configSet.environmentID,
            projectID: configSet.projectID,
            configs: configs,
            receivedAt: Date().millisecondsSince1970
        ))
    }

    private func contextToConnectWith(
        _ suppliedContext: ConfigDirectorContext?,
        reason: ConnectReason
    ) -> ConfigDirectorContext? {
        switch ContextAdmission(of: suppliedContext) {
        case let .admitted(context):
            return context
        case let .ignoredForAnInvalidContextKind(contextKindSample):
            logger.error("""
            Ignored the context supplied for \(reason) because its context kind '\(contextKindSample)' is \
            invalid, so configs are evaluated as if no context was supplied. A context kind has 1 to 64 \
            characters: lowercase ASCII letters, digits, '-' and '_'.
            """)
            telemetry.recordInvalidContextSubmission(contextKindSample: contextKindSample)
            return nil
        }
    }

    private func resumeReadyWaiter(_ id: UUID) {
        state.withLock { $0.readyWaiters.removeValue(forKey: id) }?.resume()
    }
}

extension ConfigStore {
    func evaluate<Value: ConfigValue>(
        _ key: String,
        default defaultValue: Value
    ) -> (value: Value, evaluation: ConfigEvaluation) {
        evaluateAndRecord(key: key, default: defaultValue) {
            ConfigValueParser.parse($0, default: defaultValue)
        }
    }

    func evaluate<Value: Decodable & Sendable>(
        _ key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> (value: Value, evaluation: ConfigEvaluation) {
        evaluateAndRecord(key: key, default: defaultValue) {
            ConfigValueParser.parseJSON($0, as: type, default: defaultValue)
        }
    }

    func values<Value: ConfigValue>(
        for key: String,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        watchers.stream(for: key) { [weak self] in
            self?.evaluate(key, default: defaultValue).value ?? defaultValue
        }
    }

    func values<Value: Decodable & Sendable & Equatable>(
        for key: String,
        as type: Value.Type,
        default defaultValue: Value
    ) -> AsyncStream<Value> {
        watchers.stream(for: key) { [weak self] in
            self?.evaluate(key, as: type, default: defaultValue).value ?? defaultValue
        }
    }

    private func evaluateAndRecord<Value: Sendable>(
        key: String,
        default defaultValue: Value,
        parse: (ConfigState) -> EvaluationResult<Value>
    ) -> (value: Value, evaluation: ConfigEvaluation) {
        let (configState, isReady, context, source) = state.withLock {
            ($0.configs[key], $0.isReady, $0.context, $0.configSetSource)
        }

        let result = (configState.map(parse) ?? EvaluationResult(
            value: defaultValue,
            usedDefault: true,
            reason: isReady ? .configStateMissing : .clientNotReady
        )).asServedFrom(source)

        telemetry.evaluatedConfig(EvaluatedConfigEvent(
            contextID: context?.id,
            key: key,
            type: configState?.type,
            defaultValue: TelemetryValue(value: String(describing: defaultValue), type: configState?.type),
            requestedType: String(describing: Value.self),
            evaluatedValue: TelemetryValue(
                value: String(describing: result.value),
                valueID: result.valueID,
                type: configState?.type
            ),
            evaluatedValueID: result.valueID,
            usedDefault: result.usedDefault,
            evaluationReason: result.reason
        ))

        let evaluation = ConfigEvaluation(
            key: key,
            value: ConfigEvaluationValue(result.value),
            valueID: result.valueID,
            isDefaultValue: result.usedDefault,
            reason: result.reason,
            context: context
        )
        evaluations.emit(evaluation)
        logger.debug("Evaluated '\(key)' to '\(result.value)' (\(result.reason.rawValue))")

        return (result.value, evaluation)
    }
}

private struct MergedConfigSet {
    var isDelta: Bool
    var removedKeys: [String]
    var configs: [String: ConfigState]
}
