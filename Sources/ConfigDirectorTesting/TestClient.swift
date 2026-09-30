import ConfigDirector
import Foundation

/// Creates a test client: the SDK's real `ConfigDirectorClient` connected to an
/// in-memory server that the test controls through the returned ``TestClient``. Nothing reaches the
/// network, no telemetry is sent, and the app lifecycle is not observed.
///
/// The client starts uninitialized, like a production client, because the code under test usually
/// owns the call to `initialize`. With nothing held or failed, `initialize` completes at once with
/// the client ready and serving `values`.
///
/// ```swift
/// let testClient = makeTestClient(values: ["new-checkout": true, "max-items": 20])
/// await testClient.client.initialize()
///
/// let checkout = Checkout(client: testClient.client)
/// #expect(checkout.isNewCheckoutEnabled)
///
/// testClient.setValue(false, for: "new-checkout")
/// #expect(!checkout.isNewCheckoutEnabled)
/// ```
///
/// - Parameters:
///   - values: The values to serve, keyed by config key. A blank key or a number that is not
///     finite is a programming error and traps.
///   - timeout: The client's connection timeout, which bounds how long a held attempt waits. The
///     SDK's production default when not given.
///   - logger: Where the client logs. The SDK's `ConsoleLogger` when not given.
public func makeTestClient(
    values: [String: TestValue] = [:],
    timeout: TimeInterval = ConnectionOptions().timeout,
    logger: any ConfigDirectorLogger = ConsoleLogger()
) -> TestClient {
    TestClient(connection: InMemoryConnection(
        values: values.mapValues(\.inMemoryValue),
        timeout: timeout,
        logger: logger
    ))
}

/// The controls of a test client made by ``makeTestClient(values:timeout:logger:)``, and the
/// ``client`` they drive.
///
/// Every value the test client serves is served to every context. The initialization controls act
/// only on `initialize` and the context update controls only on `updateContext`; `resumeNetwork` is
/// never held or failed. After `close`, every control is a silent no-op.
public final class TestClient: Sendable {
    private let connection: InMemoryConnection

    init(connection: InMemoryConnection) {
        self.connection = connection
    }

    /// The client under test. It is a `ConfigDirectorClient` like any other, so it
    /// goes anywhere production code accepts one. Close it when the test is done, as production
    /// code would.
    public var client: ConfigDirectorClient {
        connection.client
    }

    /// The context of every `initialize` and `updateContext` call, in call order. `initialize`
    /// without a context records an empty context. `resumeNetwork` is not recorded.
    public var contextUpdates: [ConfigDirectorContext] {
        connection.contextUpdates
    }

    package var isHoldingAnAttempt: Bool {
        connection.isHoldingAnAttempt
    }

    /// Stores `value` under `key` and, once the client is connected, delivers an update carrying
    /// only `key`: `values(for:)` streams of `key` yield it, `configsUpdated` lists it, and reads
    /// return it. A blank key or a number that is not finite is a programming error and traps.
    public func setValue(_ value: TestValue, for key: String) {
        connection.setValue(value.inMemoryValue, for: key)
    }

    /// Removes the value under `key` and, once the client is connected, delivers a full update
    /// without it: reads of `key` return the in-code default value with the `configStateMissing`
    /// reason, `values(for:)` streams of `key` yield that default, and `configsUpdated` lists `key`
    /// in its `removedKeys`.
    public func removeValue(for key: String) {
        connection.removeValue(for: key)
    }

    /// Replaces every stored value with `values`, disarms any armed hold or failure, and, once the
    /// client is connected, delivers a full update. Use it to reset a test client shared across
    /// tests.
    public func replaceValues(_ values: [String: TestValue]) {
        connection.replaceValues(values.mapValues(\.inMemoryValue))
    }

    /// Makes the next `initialize` wait, not ready, until ``completeInitialization()`` or
    /// ``failInitialization()``, or until the client's connection timeout elapses.
    public func holdInitialization() {
        connection.holdInitialization()
    }

    /// Delivers the stored values to a held `initialize`, so the client is ready when this returns,
    /// and then lets `initialize` complete. Called while a hold is armed but no `initialize` has
    /// picked it up, it disarms the hold.
    public func completeInitialization() {
        connection.completeInitialization()
    }

    /// Fails a held `initialize` the way an invalid SDK key does: it completes promptly, the client
    /// is not ready, and the client logs the error. Called while no `initialize` is held, it arms
    /// the next one to fail.
    public func failInitialization() {
        connection.failInitialization()
    }

    /// As ``holdInitialization()``, for the next `updateContext`.
    public func holdContextUpdate() {
        connection.holdContextUpdate()
    }

    /// As ``completeInitialization()``, for a held `updateContext`.
    public func completeContextUpdate() {
        connection.completeContextUpdate()
    }

    /// As ``failInitialization()``, for a held `updateContext`.
    public func failContextUpdate() {
        connection.failContextUpdate()
    }
}
