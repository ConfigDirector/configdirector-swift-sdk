@testable import ConfigDirector
import Foundation

/// Serves scripted HTTP responses, one per connection attempt, so reconnection behavior can be
/// driven from a test. Responses can be left open to model a stream that is still connected.
///
/// Everything is keyed by URL. A client whose reconnect loop is still winding down at the end of a
/// test would otherwise consume the response the next test just queued.
final class StubURLProtocol: URLProtocol {
    struct Response: Sendable {
        var statusCode = 200
        var headers: [String: String] = ["Content-Type": "text/event-stream"]
        var chunks: [String] = []

        /// When false the response is left open, the way a healthy server-sent events stream is.
        var endsStream = true

        var isHeldUntilReleased = false
    }

    struct RecordedRequest: Sendable {
        var method: String?
        var headers: [String: String]
        var body: String?
        var timeout: TimeInterval
        var cachePolicy: URLRequest.CachePolicy
    }

    private enum Reply {
        case answerNow(Response)
        case heldUntilReleased
    }

    private struct HeldRequest {
        var connection: StubURLProtocol
        var response: Response
    }

    private struct State {
        var queues: [String: [Response]] = [:]
        var recorded: [String: [RecordedRequest]] = [:]
        var cancelled: [String: Int] = [:]
        var held: [String: [HeldRequest]] = [:]
        var urlsWithNoChangeSinceTimestamp: Set<String> = []
    }

    private static let state = Locked(State())

    /// The connections that are still open, so a test can send more down a stream it has already
    /// scripted, the way the server pushes a config update.
    private static let live = Locked<[String: [StubURLProtocol]]>([:])

    static func enqueue(_ responses: [Response], for url: URL) {
        state.withLock { $0.queues[url.absoluteString, default: []].append(contentsOf: responses) }
    }

    static func answerTimestampedRequestsWithNoChange(for url: URL) {
        state.withLock { _ = $0.urlsWithNoChangeSinceTimestamp.insert(url.absoluteString) }
    }

    static func recorded(for url: URL) -> [RecordedRequest] {
        state.withLock { $0.recorded[url.absoluteString] ?? [] }
    }

    /// How many connections to `url` were cancelled by the client rather than ended by the server.
    static func cancelled(for url: URL) -> Int {
        state.withLock { $0.cancelled[url.absoluteString] ?? 0 }
    }

    static func releaseHeldResponses(for url: URL) {
        let held = state.withLock { state in
            state.held.removeValue(forKey: url.absoluteString) ?? []
        }
        for request in held {
            request.connection.answer(with: request.response)
        }
    }

    /// Sends `text` down every open connection to `url`.
    static func push(_ text: String, to url: URL) {
        for connection in live.withLock({ $0[url.absoluteString] ?? [] }) {
            connection.client?.urlProtocol(connection, didLoad: Data(text.utf8))
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        switch Self.reply(recording: self) {
        case let .answerNow(response):
            answer(with: response)
        case .heldUntilReleased:
            break
        }
    }

    private func answer(with response: Response) {
        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                  url: url,
                  statusCode: response.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: response.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)

        for chunk in response.chunks {
            client?.urlProtocol(self, didLoad: Data(chunk.utf8))
        }

        if response.endsStream {
            client?.urlProtocolDidFinishLoading(self)
        } else {
            Self.live.withLock { $0[url.absoluteString, default: []].append(self) }
        }
    }

    override func stopLoading() {
        let key = request.url?.absoluteString ?? ""
        Self.state.withLock { state in
            state.cancelled[key, default: 0] += 1
            state.held[key]?.removeAll { $0.connection === self }
        }
        Self.live.withLock { $0[key]?.removeAll { $0 === self } }
    }

    /// Takes the next scripted response, defaulting to one that stays open so a client that
    /// reconnects more often than the test scripted does not spin.
    private static func reply(recording connection: StubURLProtocol) -> Reply {
        let request = connection.request
        let key = request.url?.absoluteString ?? ""

        return state.withLock { state -> Reply in
            let recordedRequest = RecordedRequest(
                method: request.httpMethod,
                headers: request.allHTTPHeaderFields ?? [:],
                body: body(of: request),
                timeout: request.timeoutInterval,
                cachePolicy: request.cachePolicy
            )
            state.recorded[key, default: []].append(recordedRequest)

            let carriesATimestamp = recordedRequest.payload?.lastUpdateTimestamp != nil
            if carriesATimestamp, state.urlsWithNoChangeSinceTimestamp.contains(key) {
                return .answerNow(.json("", statusCode: 204))
            }

            guard var queue = state.queues[key], !queue.isEmpty else {
                return .answerNow(Response(endsStream: false))
            }
            let response = queue.removeFirst()
            state.queues[key] = queue
            guard response.isHeldUntilReleased else { return .answerNow(response) }

            state.held[key, default: []].append(HeldRequest(connection: connection, response: response))
            return .heldUntilReleased
        }
    }

    /// URLSession turns a request body into a stream before a protocol sees it, so both have to be
    /// handled to read back what was sent.
    private static func body(of request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }

        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }

        return String(decoding: data, as: UTF8.self)
    }
}
