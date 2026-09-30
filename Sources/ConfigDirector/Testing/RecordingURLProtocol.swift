import Foundation

/// Fails every request and counts it, so a test can prove the test client never reached for the
/// network.
final class RecordingURLProtocol: URLProtocol {
    private static let count = Locked(0)

    static var requestCount: Int {
        count.withLock { $0 }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.count.withLock { $0 += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
