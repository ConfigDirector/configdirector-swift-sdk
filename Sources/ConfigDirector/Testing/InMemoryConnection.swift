import Foundation

package final class InMemoryConnection: Sendable {
    package let client: ConfigDirectorClient

    private let transport: InMemoryTransport

    package init(values: [String: InMemoryValue], timeout: TimeInterval, logger: any ConfigDirectorLogger) {
        let transport = InMemoryTransport(configs: InMemoryTransport.encode(values))
        self.transport = transport
        do {
            client = try ConfigDirectorClient(
                clientSDKKey: "test-client",
                options: ConfigDirectorClientOptions(
                    metadata: ConfigDirectorMetaContext(appName: "test-client", appVersion: "0.0.0"),
                    connection: ConnectionOptions(timeout: timeout),
                    logger: logger
                ),
                identity: .swiftClientSDK,
                session: RecordingURLProtocol.makeSession(),
                lifecycle: NoLifecycleObserver(),
                telemetryOptions: TelemetryOptions(),
                makeTelemetry: { _, _, _ in DiscardingTelemetry() },
                makeTransport: { _, _, onConfigSet in
                    transport.attach(onConfigSet)
                    return transport
                }
            )
        } catch {
            preconditionFailure("The test client could not build its client: \(error)")
        }
    }

    package var contextUpdates: [ConfigDirectorContext] {
        transport.contextUpdates
    }

    package var isHoldingAnAttempt: Bool {
        transport.isHoldingAnAttempt
    }

    package static var recordedRequestCount: Int {
        RecordingURLProtocol.requestCount
    }

    package func setValue(_ value: InMemoryValue, for key: String) {
        transport.setValue(value, for: key)
    }

    package func removeValue(for key: String) {
        transport.removeValue(for: key)
    }

    package func replaceValues(_ values: [String: InMemoryValue]) {
        transport.replaceValues(values)
    }

    package func holdInitialization() {
        transport.hold(.initialization)
    }

    package func completeInitialization() {
        transport.complete(.initialization)
    }

    package func failInitialization() {
        transport.fail(.initialization)
    }

    package func holdContextUpdate() {
        transport.hold(.contextUpdate)
    }

    package func completeContextUpdate() {
        transport.complete(.contextUpdate)
    }

    package func failContextUpdate() {
        transport.fail(.contextUpdate)
    }
}

private final class InMemoryTransport: Transport {
    enum Operation {
        case initialization
        case contextUpdate

        var reason: ConnectReason {
            switch self {
            case .initialization: .initialization
            case .contextUpdate: .contextUpdate
            }
        }
    }

    private enum Armed {
        case nothing
        case hold
        case failure
    }

    private struct AttemptControls {
        var armed = Armed.nothing
        var held: ConnectionGate?
    }

    private struct State {
        var configs: [String: ConfigState]
        var initialization = AttemptControls()
        var contextUpdate = AttemptControls()
        var contextUpdates: [ConfigDirectorContext] = []
        var isConnected = false
        var pendingDeliveries: [ConfigSet] = []
        var isDelivering = false
        var onConfigSet: ConfigSetHandler?

        subscript(operation: Operation) -> AttemptControls {
            get {
                switch operation {
                case .initialization: initialization
                case .contextUpdate: contextUpdate
                }
            }
            set {
                switch operation {
                case .initialization: initialization = newValue
                case .contextUpdate: contextUpdate = newValue
                }
            }
        }
    }

    private static let fatalStatus = 401

    private let state: Locked<State>

    init(configs: [String: ConfigState]) {
        state = Locked(State(configs: configs))
    }

    static func encode(_ values: [String: InMemoryValue]) -> [String: ConfigState] {
        Dictionary(uniqueKeysWithValues: values.map { key, value in (key, encode(value, for: key)) })
    }

    private static func encode(_ value: InMemoryValue, for key: String) -> ConfigState {
        precondition(
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "A config key must not be blank."
        )
        return value.configState(key: key)
    }

    func attach(_ onConfigSet: @escaping ConfigSetHandler) {
        state.withLock { $0.onConfigSet = onConfigSet }
    }

    var contextUpdates: [ConfigDirectorContext] {
        state.withLock { $0.contextUpdates }
    }

    var isHoldingAnAttempt: Bool {
        state.withLock { $0.initialization.held != nil || $0.contextUpdate.held != nil }
    }

    func setValue(_ value: InMemoryValue, for key: String) {
        let configState = Self.encode(value, for: key)
        state.withLock { state in
            state.configs[key] = configState
            if state.isConnected {
                state.pendingDeliveries.append(Self.deltaUpdate([key: configState]))
            }
        }
        drain()
    }

    func removeValue(for key: String) {
        state.withLock { state in
            state.configs.removeValue(forKey: key)
            if state.isConnected {
                state.pendingDeliveries.append(Self.fullUpdate(state.configs))
            }
        }
        drain()
    }

    func replaceValues(_ values: [String: InMemoryValue]) {
        let configs = Self.encode(values)
        state.withLock { state in
            state.configs = configs
            state.initialization.armed = .nothing
            state.contextUpdate.armed = .nothing
            if state.isConnected {
                state.pendingDeliveries.append(Self.fullUpdate(configs))
            }
        }
        drain()
    }

    func hold(_ operation: Operation) {
        state.withLock { $0[operation].armed = .hold }
    }

    func complete(_ operation: Operation) {
        let held = state.withLock { state -> ConnectionGate? in
            guard let held = state[operation].held else {
                if state[operation].armed == .hold {
                    state[operation].armed = .nothing
                }
                return nil
            }
            state[operation].held = nil
            state.isConnected = true
            state.pendingDeliveries.append(Self.fullUpdate(state.configs))
            return held
        }
        guard let held else { return }

        drain()
        held.settle()
    }

    func fail(_ operation: Operation) {
        let held = state.withLock { state -> ConnectionGate? in
            guard let held = state[operation].held else {
                state[operation].armed = .failure
                return nil
            }
            state[operation].held = nil
            return held
        }

        held?.settle(.failure(Self.fatalFailure(operation.reason)))
    }

    func connect(context: ConfigDirectorContext, timeout: TimeInterval, reason: ConnectReason) async throws {
        let operation: Operation? = switch reason {
        case .initialization: .initialization
        case .contextUpdate: .contextUpdate
        case .networkResume: nil
        }

        let (armed, held) = state.withLock { state -> (Armed, ConnectionGate?) in
            state.isConnected = false
            guard let operation else { return (.nothing, nil) }
            state.contextUpdates.append(context)
            let armed = state[operation].armed
            state[operation].armed = .nothing
            guard armed == .hold else { return (armed, nil) }
            let held = ConnectionGate()
            state[operation].held = held
            return (.hold, held)
        }

        switch armed {
        case .nothing:
            deliverFirstUpdate()
        case .failure:
            throw Self.fatalFailure(reason)
        case .hold:
            guard let operation, let held else { return }
            defer {
                state.withLock { state in
                    if state[operation].held === held {
                        state[operation].held = nil
                    }
                }
            }
            try await held.wait(timeout: timeout)
        }
    }

    func disconnect() {
        endAttempts()
    }

    func close() {
        endAttempts()
    }

    private func endAttempts() {
        let ended = state.withLock { state -> [ConnectionGate] in
            state.isConnected = false
            let held = [state.initialization.held, state.contextUpdate.held].compactMap(\.self)
            state.initialization.held = nil
            state.contextUpdate.held = nil
            return held
        }
        for gate in ended {
            gate.settle()
        }
    }

    private func deliverFirstUpdate() {
        state.withLock { state in
            state.isConnected = true
            state.pendingDeliveries.append(Self.fullUpdate(state.configs))
        }
        drain()
    }

    /// Delivers everything queued, one update at a time, without holding the lock while the client
    /// handles it. A delivery queued from inside the client's own handler waits for the outer one.
    private func drain() {
        let isDelivering = state.withLock { state -> Bool in
            guard !state.isDelivering, !state.pendingDeliveries.isEmpty else { return false }
            state.isDelivering = true
            return true
        }
        guard isDelivering else { return }

        while true {
            let (next, onConfigSet) = state.withLock { state -> (ConfigSet?, ConfigSetHandler?) in
                guard !state.pendingDeliveries.isEmpty else {
                    state.isDelivering = false
                    return (nil, nil)
                }
                return (state.pendingDeliveries.removeFirst(), state.onConfigSet)
            }
            guard let next else { return }
            onConfigSet?(next)
        }
    }

    private static func fullUpdate(_ configs: [String: ConfigState]) -> ConfigSet {
        ConfigSet(environmentID: "test-environment", projectID: "test-project", configs: configs, kind: .full)
    }

    private static func deltaUpdate(_ configs: [String: ConfigState]) -> ConfigSet {
        ConfigSet(
            environmentID: "test-environment",
            projectID: "test-project",
            configs: configs,
            kind: .delta
        )
    }

    private static func fatalFailure(_ reason: ConnectReason) -> ConfigDirectorError {
        .connectionFailed(
            message: """
            Connection failed with status: \(fatalStatus). Error: the test client failed this \(reason). \
            This is an unrecoverable error, will not attempt to reconnect.
            """,
            statusCode: fatalStatus
        )
    }
}

private struct NoLifecycleObserver: AppLifecycleObserver {
    func start(onChange _: @escaping @Sendable (AppLifecyclePhase) -> Void) {}

    func stop() {}
}

private struct DiscardingTelemetry: TelemetryClient {
    func evaluatedConfig(_: EvaluatedConfigEvent) {}

    func updateContext(_: ConfigDirectorContext?) {}

    func flush() async {}

    func close() {}
}
