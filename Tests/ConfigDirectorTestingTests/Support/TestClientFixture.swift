import ConfigDirector
import ConfigDirectorTesting
import Foundation

/// One test client per test, logging into a recorder the test can read.
final class TestClientFixture: Sendable {
    let logger = RecordingLogger()

    func makeTestClient(values: [String: TestValue] = [:], timeout: TimeInterval = 3) -> TestClient {
        ConfigDirectorTesting.makeTestClient(values: values, timeout: timeout, logger: logger)
    }
}

func readyReason(of event: ClientEvent) -> ConnectReason? {
    if case let .ready(reason) = event {
        reason
    } else {
        nil
    }
}

func configsUpdate(of event: ClientEvent) -> ConfigsUpdate? {
    if case let .configsUpdated(update) = event {
        update
    } else {
        nil
    }
}

extension StreamReader {
    func next(
        timeout: TimeInterval = 2,
        where matches: @escaping @Sendable (Element) -> Bool
    ) async -> Element? {
        while let element = await next(timeout: timeout) {
            if matches(element) {
                return element
            }
        }
        return nil
    }
}

extension Array where Element: Sendable {
    /// Drains an `AsyncStream` into an array once the client closes it.
    init(_ stream: AsyncStream<Element>) async {
        self.init()
        for await element in stream {
            append(element)
        }
    }
}
